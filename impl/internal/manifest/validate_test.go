package manifest

import (
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/diag"
)

func validateBody(t *testing.T, body string) []diag.Diagnostic {
	t.Helper()
	dir := t.TempDir()
	p := write(t, dir, "xnull.project", body)
	_, ds, err := Load(p, Options{})
	if err != nil {
		t.Fatalf("IO 错误：%v", err)
	}
	return ds
}

func TestSchemaValidation(t *testing.T) {
	base := `project {
  groupId = g
  artifactId = a
  version = 1.0.0
  packaging = app
`
	cases := []struct {
		name string
		body string
		code string
	}{
		{"未知段落", base + "  unknownSection {\n  }\n}\n", "XPD-201"},
		{"未知字段", base + "  unknownField = 1\n}\n", "XPD-201"},
		{"未知顶层块", "other {\n}\n", "XPD-201"},
		{"段落重复", base + "  build {\n  }\n  build {\n  }\n}\n", "XPD-202"},
		{"字段重复", base + "  version = 2.0.0\n}\n", "XPD-202"},
		{"project 重复", base + "}\nproject {\n  groupId = g\n  artifactId = b\n  version = 1.0.0\n  packaging = app\n}\n", "XPD-202"},
		{"容器非法条目", base + "  dependencies {\n    random = 1\n  }\n}\n", "XPD-203"},
		{"容器含非法块", base + "  repositories {\n    dependency g:x {\n    }\n  }\n}\n", "XPD-203"},
		{"依赖坐标重复", base + "  dependencies {\n    dependency g:lib {\n      version = 1.0.0\n    }\n    dependency g:lib {\n      version = 2.0.0\n    }\n  }\n}\n", "XPD-302"},
		{"缺坐标", "project {\n  groupId = g\n  artifactId = a\n  packaging = app\n}\n", "XPD-301"},
		{"packaging 非法值", base + "}\n", ""}, // 占位：合法基础清单应无诊断
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			ds := validateBody(t, c.body)
			if c.code == "" {
				if len(ds) != 0 {
					t.Fatalf("不应有诊断：%v", ds)
				}
				return
			}
			if !hasDiag(ds, c.code) {
				t.Fatalf("应报 %s，实际 %v", c.code, ds)
			}
			for _, d := range ds {
				if d.Line == 0 || d.Col == 0 {
					t.Fatalf("诊断缺少位置：%+v", d)
				}
			}
		})
	}
}

func TestSchemaPositions(t *testing.T) {
	body := `project {
  groupId = g
  artifactId = a
  version = 1.0.0
  packaging = app
  unknownField = 1
}
`
	dir := t.TempDir()
	p := write(t, dir, "xnull.project", body)
	_, ds, _ := Load(p, Options{})
	if len(ds) == 0 {
		t.Fatal("应有诊断")
	}
	if !strings.HasSuffix(ds[0].File, "xnull.project") || ds[0].Line != 6 {
		t.Fatalf("位置不符：%s:%d", ds[0].File, ds[0].Line)
	}
	_ = filepath.Base
}

// S8-05：build.plugins 声明解析（供插件合同校验）。
func TestPluginsParsed(t *testing.T) {
	body := `project {
  groupId = g
  artifactId = a
  version = 1.0.0
  packaging = app
  build {
    plugins {
      plugin com.example:codegen 1.2.0 {
        phase = validate
        goal  = check
        configuration {
          output = target/gen
        }
      }
    }
  }
}
`
	dir := t.TempDir()
	p := write(t, dir, "xnull.project", body)
	res, ds, err := Load(p, Options{})
	if err != nil || len(ds) != 0 {
		t.Fatalf("不应有诊断：%v %v", err, ds)
	}
	if len(res.Plugins) != 1 {
		t.Fatalf("插件声明未解析：%+v", res.Plugins)
	}
	pl := res.Plugins[0]
	if pl.Coordinate != "com.example:codegen" || pl.Version != "1.2.0" || pl.Phase != "validate" ||
		pl.Goal != "check" || pl.Config["output"] != "target/gen" {
		t.Fatalf("插件字段错误：%+v", pl)
	}
}

// S8-08：build.resources.resource 解析（dir + includes/excludes）。
func TestResourceRootsParsed(t *testing.T) {
	body := `project {
  groupId = g
  artifactId = a
  version = 1.0.0
  packaging = app
  build {
    resources {
      resource src/main/resources {
      }
      resource assets {
        includes = [images/**, fonts/**]
        excludes = [**/*.psd]
      }
    }
  }
}
`
	dir := t.TempDir()
	p := write(t, dir, "xnull.project", body)
	res, ds, err := Load(p, Options{})
	if err != nil || len(ds) != 0 {
		t.Fatalf("不应有诊断：%v %v", err, ds)
	}
	if len(res.ResourceRoots) != 2 {
		t.Fatalf("资源根数量不符：%+v", res.ResourceRoots)
	}
	if res.ResourceRoots[1].Dir != "assets" || len(res.ResourceRoots[1].Includes) != 2 ||
		len(res.ResourceRoots[1].Excludes) != 1 {
		t.Fatalf("资源根字段错误：%+v", res.ResourceRoots[1])
	}
}
