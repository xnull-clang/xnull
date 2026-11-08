package reactor

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/diag"
)

func mk(t *testing.T, root, rel, body string) {
	t.Helper()
	p := filepath.Join(root, rel)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

func aggRoot(modules, extra string) string {
	return `project {
  groupId = io.xnull
  artifactId = sdk-suite
  version = 3.1.0
  packaging = pom
  modules {
` + modules + `  }
  dependencyManagement {
    dependencies {
      dependency io.xnull:core {
        version = 3.1.0
      }
      dependency io.xnull:codec {
        version = 3.1.0
      }
      dependency io.xnull:http {
        version = 3.1.0
      }
    }
  }
` + extra + `}
`
}

func libModule(id string, deps string) string {
	return `project {
  groupId = io.xnull
  artifactId = ` + id + `
  version = 3.1.0
  packaging = library
  dependencies {
` + deps + `  }
}
`
}

func appModule(id string, deps string) string {
	return `project {
  groupId = io.xnull
  artifactId = ` + id + `
  version = 3.1.0
  packaging = app
  dependencies {
` + deps + `  }
  build {
    entryFile = src/main/x/main.x
  }
}
`
}

func writeAgg(t *testing.T) string {
	root := t.TempDir()
	mk(t, root, "xnull.project", aggRoot(`    module core
    module codec
    module http
    module cli
`, ""))
	mk(t, root, "core/xnull.project", libModule("core", ""))
	mk(t, root, "core/src/main/x/core.x", "static Int c() {\n    return 1\n}\n")
	mk(t, root, "codec/xnull.project", libModule("codec", "    dependency io.xnull:core {\n    }\n"))
	mk(t, root, "codec/src/main/x/codec.x", "static Int d() {\n    return 2\n}\n")
	mk(t, root, "http/xnull.project", libModule("http", "    dependency io.xnull:core {\n    }\n    dependency io.xnull:codec {\n    }\n"))
	mk(t, root, "http/src/main/x/http.x", "static Int h() {\n    return 3\n}\n")
	mk(t, root, "cli/xnull.project", appModule("cli", "    dependency io.xnull:http {\n    }\n"))
	mk(t, root, "cli/src/main/x/main.x", "static Int main() {\n    return 0\n}\n")
	return root
}

// S8-14：模块图与拓扑序（library → app）。
func TestPlanTopologicalOrder(t *testing.T) {
	root := writeAgg(t)
	plan, ds, err := Load(root, Options{ToolchainVersion: "0.1.0"})
	if err != nil {
		t.Fatal(err)
	}
	if len(ds) != 0 {
		t.Fatalf("不应有诊断：%v", ds)
	}
	pos := map[string]int{}
	for i, rel := range plan.Order {
		pos[rel] = i
	}
	if !(pos["core"] < pos["codec"] && pos["codec"] < pos["http"] && pos["http"] < pos["cli"]) {
		t.Fatalf("拓扑序不符：%v", plan.Order)
	}
	// 聚合根仲裁表注入版本（模块未写版本）
	for _, m := range plan.Modules {
		if m.Rel == "codec" && m.Deps["io.xnull:core"] != "3.1.0" {
			t.Fatalf("管理版本未注入：%+v", m)
		}
	}
}

// S8-14：重复 GAV / 环 / starter 规则。
func TestPlanValidation(t *testing.T) {
	t.Run("重复 GAV", func(t *testing.T) {
		root := t.TempDir()
		mk(t, root, "xnull.project", `project {
  groupId = io.xnull
  artifactId = root
  version = 1.0.0
  packaging = pom
  modules {
    module a
    module b
  }
}
`)
		same := `project {
  groupId = io.xnull
  artifactId = dup
  version = 1.0.0
  packaging = library
}
`
		mk(t, root, "a/xnull.project", same)
		mk(t, root, "b/xnull.project", same)
		_, ds, _ := Load(root, Options{})
		if !hasCode(ds, "XPD-302") {
			t.Fatalf("重复 GAV 应报 XPD-302：%v", ds)
		}
	})

	t.Run("环", func(t *testing.T) {
		root := t.TempDir()
		mk(t, root, "xnull.project", `project {
  groupId = io.xnull
  artifactId = root
  version = 1.0.0
  packaging = pom
  modules {
    module a
    module b
  }
}
`)
		mk(t, root, "a/xnull.project", libModule("a", "    dependency io.xnull:b {\n      version = 3.1.0\n    }\n"))
		mk(t, root, "b/xnull.project", libModule("b", "    dependency io.xnull:a {\n      version = 3.1.0\n    }\n"))
		_, ds, _ := Load(root, Options{})
		if !hasCode(ds, "XPD-409") {
			t.Fatalf("环应报 XPD-409：%v", ds)
		}
	})

	t.Run("starter 含 src 失败", func(t *testing.T) {
		root := t.TempDir()
		mk(t, root, "xnull.project", `project {
  groupId = io.xnull
  artifactId = root
  version = 1.0.0
  packaging = pom
  modules {
    module st
  }
}
`)
		mk(t, root, "st/xnull.project", `project {
  groupId = io.xnull
  artifactId = st
  version = 1.0.0
  packaging = starter
}
`)
		mk(t, root, "st/src/main/x/x.x", "static Int f() {\n    return 0\n}\n")
		_, ds, _ := Load(root, Options{})
		if len(ds) == 0 {
			t.Fatalf("starter 含 src 应失败")
		}
	})

	t.Run("starter 依赖传递给使用者", func(t *testing.T) {
		root := t.TempDir()
		mk(t, root, "xnull.project", `project {
  groupId = io.xnull
  artifactId = root
  version = 1.0.0
  packaging = pom
  modules {
    module st
    module app
  }
  dependencyManagement {
    dependencies {
      dependency io.xnull:dep {
        version = 1.0.0
      }
    }
  }
}
`)
		mk(t, root, "st/xnull.project", `project {
  groupId = io.xnull
  artifactId = st
  version = 1.0.0
  packaging = starter
  dependencies {
    dependency io.xnull:dep {
    }
  }
}
`)
		mk(t, root, "app/xnull.project", `project {
  groupId = io.xnull
  artifactId = app
  version = 1.0.0
  packaging = library
  dependencies {
    dependency io.xnull:st {
      version = 1.0.0
    }
  }
}
`)
		plan, ds, err := Load(root, Options{})
		if err != nil || len(ds) != 0 {
			t.Fatalf("不应有诊断：%v %v", err, ds)
		}
		var app *Module
		for i := range plan.Modules {
			if plan.Modules[i].Rel == "app" {
				app = &plan.Modules[i]
			}
		}
		if app == nil || app.Deps["io.xnull:dep"] != "1.0.0" {
			t.Fatalf("starter 传递依赖未展开：%+v", app)
		}
	})
}

// S8-14：失败即停（后续模块不构建）。
func TestBuildFailFast(t *testing.T) {
	root := writeAgg(t)
	plan, ds, err := Load(root, Options{})
	if err != nil || len(ds) != 0 {
		t.Fatalf("%v %v", err, ds)
	}
	var built []string
	_, bds := Build(plan, func(m Module) (string, error) {
		built = append(built, m.Rel)
		if m.Rel == "codec" {
			return "", os.ErrInvalid
		}
		return filepath.Join(root, m.Rel, "target", "a"), nil
	})
	if len(bds) == 0 {
		t.Fatal("失败应有诊断")
	}
	if strings.Join(built, ",") != "core,codec" {
		t.Fatalf("应失败即停，实际构建：%v", built)
	}
}

func hasCode(ds []diag.Diagnostic, want string) bool {
	for _, d := range ds {
		if strings.HasPrefix(d.Code, want) {
			return true
		}
	}
	return false
}
