package manifest

import (
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
)

// mkRepoDep 在本地仓库写入依赖清单与制品。
func mkRepoDep(t *testing.T, repo, coord, version, manifestBody string) {
	t.Helper()
	parts := strings.SplitN(coord, ":", 2)
	dir := filepath.Join(repo, filepath.FromSlash(parts[0]), parts[1], version)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	body := manifestBody
	if body == "" {
		body = "project {\n  groupId = " + parts[0] + "\n  artifactId = " + parts[1] + "\n  version = " + version + "\n  packaging = library\n}\n"
	}
	if err := os.WriteFile(filepath.Join(dir, "xnull.project"), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, parts[1]+"-"+version+".jar"), []byte(coord+"@"+version), 0o644); err != nil {
		t.Fatal(err)
	}
}

func appProject(t *testing.T, deps string) (string, string) {
	t.Helper()
	dir := t.TempDir()
	repo := t.TempDir()
	body := `project {
  groupId    = g
  artifactId = app
  version    = 1.0.0
  packaging  = app
  dependencies {
` + deps + `  }
}
`
	p := write(t, dir, "xnull.project", body)
	return p, repo
}

func resolveGraph(t *testing.T, proj, repo string) (*Resolved, *Graph, []string) {
	t.Helper()
	t.Setenv("XNULL_REPO", repo)
	res, diags, err := ResolveDependencies(proj, Options{})
	if err != nil || len(diags) > 0 {
		t.Fatalf("解析失败：%v %v", err, diags)
	}
	g, gds := ResolveGraph(res, repo)
	var codes []string
	for _, d := range gds {
		codes = append(codes, d.Code)
	}
	return res, g, codes
}

// S8-03b：传递依赖图。
func TestGraphTransitive(t *testing.T) {
	proj, repo := appProject(t, "    dependency g:a {\n      version = 1.0.0\n    }\n")
	mkRepoDep(t, repo, "g:a", "1.0.0", `project {
  groupId = g
  artifactId = a
  version = 1.0.0
  packaging = library
  dependencies {
    dependency g:b {
      version = 2.0.0
    }
  }
}
`)
	mkRepoDep(t, repo, "g:b", "2.0.0", "")

	res, g, codes := resolveGraph(t, proj, repo)
	if len(codes) != 0 {
		t.Fatalf("不应有诊断：%v", codes)
	}
	for _, want := range []string{"g:a", "g:b"} {
		if g.Selected[want] == "" {
			t.Fatalf("传递依赖 %s 缺失：%v", want, g.Selected)
		}
	}
	// 锁必须包含传递依赖
	lock, lds := GenerateLockForGraph(res, g, repo, nil)
	if len(lds) != 0 {
		t.Fatalf("生成锁失败：%v", lds)
	}
	var coords []string
	for _, e := range lock.Entries {
		coords = append(coords, e.Coordinate)
	}
	sort.Strings(coords)
	if strings.Join(coords, ",") != "g:a,g:b" {
		t.Fatalf("锁条目应含传递依赖：%v", coords)
	}
}

// S8-03b：最近优先 + 同深度冲突（点名全部路径）。
func TestGraphArbitration(t *testing.T) {
	t.Run("最近优先", func(t *testing.T) {
		proj, repo := appProject(t, "    dependency g:x {\n      version = 1.0.0\n    }\n    dependency g:a {\n      version = 1.0.0\n    }\n")
		mkRepoDep(t, repo, "g:x", "1.0.0", "")
		mkRepoDep(t, repo, "g:a", "1.0.0", `project {
  groupId = g
  artifactId = a
  version = 1.0.0
  packaging = library
  dependencies {
    dependency g:x {
      version = 3.0.0
    }
  }
}
`)
		mkRepoDep(t, repo, "g:x", "3.0.0", "")
		_, g, codes := resolveGraph(t, proj, repo)
		if len(codes) != 0 {
			t.Fatalf("不应有诊断：%v", codes)
		}
		if g.Selected["g:x"] != "1.0.0" {
			t.Fatalf("最近优先失败：%v", g.Selected)
		}
	})

	t.Run("同深度冲突", func(t *testing.T) {
		proj, repo := appProject(t, "    dependency g:a {\n      version = 1.0.0\n    }\n    dependency g:b {\n      version = 1.0.0\n    }\n")
		for _, pair := range []struct{ coord, xver string }{{"g:a", "2.0.0"}, {"g:b", "3.0.0"}} {
			mkRepoDep(t, repo, pair.coord, "1.0.0", `project {
  groupId = g
  artifactId = `+strings.TrimPrefix(pair.coord, "g:")+`
  version = 1.0.0
  packaging = library
  dependencies {
    dependency g:x {
      version = `+pair.xver+`
    }
  }
}
`)
		}
		mkRepoDep(t, repo, "g:x", "2.0.0", "")
		mkRepoDep(t, repo, "g:x", "3.0.0", "")
		_, _, codes := resolveGraph(t, proj, repo)
		if !containsCode(codes, "XPD-403") {
			t.Fatalf("同深度冲突应报 XPD-403：%v", codes)
		}
	})
}

func TestGraphConflictPaths(t *testing.T) {
	proj, repo := appProject(t, "    dependency g:a {\n      version = 1.0.0\n    }\n    dependency g:b {\n      version = 1.0.0\n    }\n")
	for _, pair := range []struct{ coord, xver string }{{"g:a", "2.0.0"}, {"g:b", "3.0.0"}} {
		mkRepoDep(t, repo, pair.coord, "1.0.0", `project {
  groupId = g
  artifactId = `+strings.TrimPrefix(pair.coord, "g:")+`
  version = 1.0.0
  packaging = library
  dependencies {
    dependency g:x {
      version = `+pair.xver+`
    }
  }
}
`)
	}
	mkRepoDep(t, repo, "g:x", "2.0.0", "")
	mkRepoDep(t, repo, "g:x", "3.0.0", "")
	t.Setenv("XNULL_REPO", repo)
	res, diags, _ := ResolveDependencies(proj, Options{})
	if len(diags) > 0 {
		t.Fatal(diags)
	}
	_, gds := ResolveGraph(res, repo)
	if len(gds) == 0 {
		t.Fatal("应有冲突诊断")
	}
	msg := gds[0].Message
	for _, want := range []string{"g:a@1.0.0", "g:b@1.0.0", "g:x@2.0.0", "g:x@3.0.0"} {
		if !strings.Contains(msg, want) {
			t.Fatalf("冲突信息缺少路径片段 %q：%s", want, msg)
		}
	}
}

// S8-03b：管理版本恒优先；scope 不传递；exclusions 生效；环失败。
func TestGraphRules(t *testing.T) {
	t.Run("管理版本优先于最近", func(t *testing.T) {
		proj, repo := appProject(t, "    dependency g:x {\n      version = 1.0.0\n    }\n    dependency g:a {\n      version = 1.0.0\n    }\n")
		// 在 app 增加管理版本 x=5.0.0
		data, _ := os.ReadFile(proj)
		body := strings.Replace(string(data), "  dependencies {", `  dependencyManagement {
    dependencies {
      dependency g:x {
        version = 5.0.0
      }
    }
  }
  dependencies {`, 1)
		write(t, filepath.Dir(proj), "xnull.project", body)
		mkRepoDep(t, repo, "g:x", "1.0.0", "")
		mkRepoDep(t, repo, "g:x", "5.0.0", "")
		mkRepoDep(t, repo, "g:a", "1.0.0", `project {
  groupId = g
  artifactId = a
  version = 1.0.0
  packaging = library
  dependencies {
    dependency g:x {
      version = 3.0.0
    }
  }
}
`)
		mkRepoDep(t, repo, "g:x", "3.0.0", "")
		_, g, codes := resolveGraph(t, proj, repo)
		if len(codes) != 0 {
			t.Fatalf("不应有诊断：%v", codes)
		}
		if g.Selected["g:x"] != "5.0.0" {
			t.Fatalf("管理版本未优先：%v", g.Selected)
		}
	})

	t.Run("test scope 不传递", func(t *testing.T) {
		proj, repo := appProject(t, "    dependency g:a {\n      version = 1.0.0\n      scope = test\n    }\n")
		mkRepoDep(t, repo, "g:a", "1.0.0", `project {
  groupId = g
  artifactId = a
  version = 1.0.0
  packaging = library
  dependencies {
    dependency g:b {
      version = 1.0.0
    }
  }
}
`)
		mkRepoDep(t, repo, "g:b", "1.0.0", "")
		_, g, _ := resolveGraph(t, proj, repo)
		if _, ok := g.Selected["g:b"]; ok {
			t.Fatalf("test scope 不应传递：%v", g.Selected)
		}
	})

	t.Run("exclusions 生效", func(t *testing.T) {
		proj, repo := appProject(t, "    dependency g:a {\n      version = 1.0.0\n      exclusions {\n        exclusion g:b\n      }\n    }\n")
		mkRepoDep(t, repo, "g:a", "1.0.0", `project {
  groupId = g
  artifactId = a
  version = 1.0.0
  packaging = library
  dependencies {
    dependency g:b {
      version = 1.0.0
    }
    dependency g:c {
      version = 1.0.0
    }
  }
}
`)
		mkRepoDep(t, repo, "g:b", "1.0.0", "")
		mkRepoDep(t, repo, "g:c", "1.0.0", "")
		_, g, _ := resolveGraph(t, proj, repo)
		if _, ok := g.Selected["g:b"]; ok {
			t.Fatalf("exclusions 未生效：%v", g.Selected)
		}
		if _, ok := g.Selected["g:c"]; !ok {
			t.Fatalf("非排除依赖缺失：%v", g.Selected)
		}
	})

	t.Run("环失败", func(t *testing.T) {
		proj, repo := appProject(t, "    dependency g:a {\n      version = 1.0.0\n    }\n")
		mkRepoDep(t, repo, "g:a", "1.0.0", `project {
  groupId = g
  artifactId = a
  version = 1.0.0
  packaging = library
  dependencies {
    dependency g:a {
      version = 1.0.0
    }
  }
}
`)
		_, _, codes := resolveGraph(t, proj, repo)
		if !containsCode(codes, "XPD-409") {
			t.Fatalf("环依赖应报 XPD-409：%v", codes)
		}
	})
}

func containsCode(codes []string, want string) bool {
	for _, c := range codes {
		if strings.HasPrefix(c, want) {
			return true
		}
	}
	return false
}
