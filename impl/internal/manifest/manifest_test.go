package manifest

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/diag"
)

func write(t *testing.T, dir, name, body string) string {
	t.Helper()
	p := filepath.Join(dir, name)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

// child 生成一个带 parent 引用的子清单。
func child(extra string) string {
	return `project {
  groupId    = g
  artifactId = child
  version    = 1.0.0
  packaging  = app
  parent {
    groupId      = g
    artifactId   = parent
    version      = 1.0.0
    relativePath = ../xnull.project
  }
` + extra + `}
`
}

const parentPOM = `project {
  groupId    = g
  artifactId = parent
  version    = 1.0.0
  packaging  = pom
  properties {
    rev  = 2.0
    only = parent
  }
  configuration {
    k = parent
  }
}
`

func loadProject(t *testing.T, body string, opts Options) (*Resolved, []string) {
	t.Helper()
	dir := t.TempDir()
	write(t, dir, "xnull.project", parentPOM)
	p := write(t, dir, "child/xnull.project", body)
	res, diags, err := Load(p, opts)
	if err != nil {
		t.Fatalf("Load 返回 IO 错误：%v", err)
	}
	var codes []string
	for _, d := range diags {
		codes = append(codes, d.Code)
	}
	return res, codes
}

func hasCode(codes []string, want string) bool {
	for _, c := range codes {
		if strings.HasPrefix(c, want) {
			return true
		}
	}
	return false
}

// S8-02：parent 解析、深度、环、缺失、非 pom。
func TestParentChainRules(t *testing.T) {
	t.Run("单父合并（properties 子覆盖父）", func(t *testing.T) {
		res, codes := loadProject(t, child(`  properties {
    only = child
  }
`), Options{})
		if len(codes) != 0 {
			t.Fatalf("不应有诊断：%v", codes)
		}
		if res.Properties["only"] != "child" || res.Properties["rev"] != "2.0" {
			t.Fatalf("properties 合并错误：%v", res.Properties)
		}
		// 坐标不从父继承：子坐标必须是自己的
		if res.ArtifactID != "child" {
			t.Fatalf("坐标被继承：%s", res.ArtifactID)
		}
	})

	t.Run("缺坐标失败", func(t *testing.T) {
		_, codes := loadProject(t, `project {
  groupId = g
  artifactId = child
  packaging = app
}
`, Options{})
		if !hasCode(codes, "XPD-301") {
			t.Fatalf("缺 version 应报 XPD-301：%v", codes)
		}
	})

	t.Run("深度超限", func(t *testing.T) {
		dir := t.TempDir()
		// p0 ← p1 ← … ← p9（10 层）
		for i := 9; i >= 0; i-- {
			body := "project {\n  groupId = g\n  artifactId = p" + itoa(i) + "\n  version = 1.0.0\n  packaging = pom\n"
			if i > 0 {
				body += "  parent {\n    groupId = g\n    artifactId = p" + itoa(i-1) + "\n    version = 1.0.0\n    relativePath = ../p" + itoa(i-1) + "/xnull.project\n  }\n"
			}
			body += "}\n"
			write(t, dir, "p"+itoa(i)+"/xnull.project", body)
		}
		p := write(t, dir, "leaf/xnull.project", "project {\n  groupId = g\n  artifactId = leaf\n  version = 1.0.0\n  packaging = app\n  parent {\n    groupId = g\n    artifactId = p9\n    version = 1.0.0\n    relativePath = ../p9/xnull.project\n  }\n}\n")
		_, diags, err := Load(p, Options{})
		if err != nil {
			t.Fatal(err)
		}
		if !hasCodes(diags, "XPD-303") {
			t.Fatalf("深度应报 XPD-303：%v", diags)
		}
	})

	t.Run("环与 self-parent", func(t *testing.T) {
		dir := t.TempDir()
		write(t, dir, "a/xnull.project", "project {\n  groupId = g\n  artifactId = a\n  version = 1.0.0\n  packaging = pom\n  parent {\n    groupId = g\n    artifactId = b\n    version = 1.0.0\n    relativePath = ../b/xnull.project\n  }\n}\n")
		write(t, dir, "b/xnull.project", "project {\n  groupId = g\n  artifactId = b\n  version = 1.0.0\n  packaging = pom\n  parent {\n    groupId = g\n    artifactId = a\n    version = 1.0.0\n    relativePath = ../a/xnull.project\n  }\n}\n")
		_, diags, err := Load(filepath.Join(dir, "a/xnull.project"), Options{})
		if err != nil {
			t.Fatal(err)
		}
		if !hasCodes(diags, "XPD-304") {
			t.Fatalf("环应报 XPD-304：%v", diags)
		}

		write(t, dir, "self/xnull.project", "project {\n  groupId = g\n  artifactId = self\n  version = 1.0.0\n  packaging = pom\n  parent {\n    groupId = g\n    artifactId = self\n    version = 1.0.0\n    relativePath = xnull.project\n  }\n}\n")
		_, diags, err = Load(filepath.Join(dir, "self/xnull.project"), Options{})
		if err != nil {
			t.Fatal(err)
		}
		if !hasCodes(diags, "XPD-304") {
			t.Fatalf("self-parent 应报 XPD-304：%v", diags)
		}
	})

	t.Run("parent 缺失/非 pom", func(t *testing.T) {
		dir := t.TempDir()
		p := write(t, dir, "c/xnull.project", "project {\n  groupId = g\n  artifactId = c\n  version = 1.0.0\n  packaging = app\n  parent {\n    groupId = g\n    artifactId = nope\n    version = 1.0.0\n    relativePath = ../nope/xnull.project\n  }\n}\n")
		_, diags, _ := Load(p, Options{})
		if !hasCodes(diags, "XPD-305") {
			t.Fatalf("缺失 parent 应报 XPD-305：%v", diags)
		}

		write(t, dir, "xnull.project", "project {\n  groupId = g\n  artifactId = parent\n  version = 1.0.0\n  packaging = app\n}\n")
		p2 := write(t, dir, "d/xnull.project", child(""))
		_ = p2
		_, diags, _ = Load(filepath.Join(dir, "d/xnull.project"), Options{})
		if !hasCodes(diags, "XPD-306") {
			t.Fatalf("parent 非 pom 应报 XPD-306：%v", diags)
		}
	})
}

// S8-02：变量替换（单次、内置、未解析失败、枚举禁变量）。
func TestPropertySubstitution(t *testing.T) {
	t.Run("属性与内置变量", func(t *testing.T) {
		res, codes := loadProject(t, child(`  properties {
    full = ${rev}-${project.artifactId}
  }
  dependencies {
    dependency g:lib {
      version = ${rev}
    }
  }
`), Options{})
		if len(codes) != 0 {
			t.Fatalf("不应有诊断：%v", codes)
		}
		if res.Properties["full"] != "2.0-child" {
			t.Fatalf("变量替换错误：%v", res.Properties)
		}
		if res.Dependencies["g:lib"] != "2.0" {
			t.Fatalf("依赖版本未替换：%v", res.Dependencies)
		}
	})

	t.Run("未解析变量失败", func(t *testing.T) {
		_, codes := loadProject(t, child(`  properties {
    bad = ${nope}
  }
`), Options{})
		if !hasCode(codes, "XPD-307") {
			t.Fatalf("未解析变量应报 XPD-307：%v", codes)
		}
	})

	t.Run("枚举字段禁变量", func(t *testing.T) {
		_, codes := loadProject(t, `project {
  groupId = g
  artifactId = child
  version = 1.0.0
  packaging = ${kind}
  properties {
    kind = app
  }
}
`, Options{})
		if !hasCode(codes, "XPD-308") {
			t.Fatalf("packaging 变量化应报 XPD-308：%v", codes)
		}
	})
}

// S8-02：profile 激活（-P / platform）与合并（冲突失败、不可覆盖段失败）。
func TestProfiles(t *testing.T) {
	const withProfiles = `  profiles {
    profile dev {
      activation {
        platform = linux
      }
      properties {
        mode = debug
      }
      configuration {
        k = dev
      }
    }
    profile ci {
      properties {
        mode = release
      }
    }
  }
`
	t.Run("-P 激活与合并", func(t *testing.T) {
		res, codes := loadProject(t, child(`  profiles {
    profile ci {
      properties {
        mode = release
      }
    }
  }
`), Options{Profiles: []string{"ci"}})
		if len(codes) != 0 {
			t.Fatalf("不应有诊断：%v", codes)
		}
		if res.Properties["mode"] != "release" {
			t.Fatalf("profile 未合并：%v", res.Properties)
		}
		if strings.Join(res.ActiveProfiles, ",") != "ci" {
			t.Fatalf("激活集合错误：%v", res.ActiveProfiles)
		}
	})

	t.Run("platform 激活", func(t *testing.T) {
		res, codes := loadProject(t, child(withProfiles), Options{Platform: "linux"})
		if codes != nil && len(codes) != 0 {
			t.Fatalf("不应有诊断：%v", codes)
		}
		if res.Properties["mode"] != "debug" || res.Configuration["k"] != "dev" {
			t.Fatalf("platform 激活未生效：%v / %v", res.Properties, res.Configuration)
		}
	})

	t.Run("同键冲突失败", func(t *testing.T) {
		_, codes := loadProject(t, child(withProfiles), Options{Profiles: []string{"dev", "ci"}, Platform: "linux"})
		if !hasCode(codes, "XPD-309") {
			t.Fatalf("同键冲突应报 XPD-309：%v", codes)
		}
	})

	t.Run("未知 profile 失败", func(t *testing.T) {
		_, codes := loadProject(t, child(withProfiles), Options{Profiles: []string{"nope"}})
		if !hasCode(codes, "XPD-309") {
			t.Fatalf("未知 profile 应报 XPD-309：%v", codes)
		}
	})

	t.Run("不可覆盖段失败", func(t *testing.T) {
		_, codes := loadProject(t, child(`  profiles {
    profile bad {
      version = 9.9.9
    }
  }
`), Options{Profiles: []string{"bad"}})
		if !hasCode(codes, "XPD-309") {
			t.Fatalf("profile 改版本应报 XPD-309：%v", codes)
		}
	})
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var b []byte
	for n > 0 {
		b = append([]byte{byte('0' + n%10)}, b...)
		n /= 10
	}
	return string(b)
}

func hasCodes(ds []diag.Diagnostic, want string) bool {
	for _, d := range ds {
		if strings.HasPrefix(d.Code, want) {
			return true
		}
	}
	return false
}
