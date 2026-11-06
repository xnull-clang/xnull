package xpd

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const sample = `# 服务清单
project {
  groupId    = com.example
  artifactId = order-service
  version    = 1.4.0
  packaging  = app

  properties {
    xdk-version      = 1.0.0
    language-version = [3.3, 4.0)
  }

  dependencies {
    dependency com.example:common {
    }
    dependency com.example:xdk-web-starter {
      version  = 3.2.1
      scope    = compile
      optional = false
      exclusions {
        exclusion org.old:legacy
      }
    }
  }

  build {
    entryFile = src/main/x/main.x
    plugins {
      plugin com.example:codegen 1.2.0 {
        phase = validate
        goal  = check
      }
    }
  }

  configuration {
    db.pool.max-size = 8
    envOverrides     = [db.url, db.password]
  }
}
`

func TestParseSample(t *testing.T) {
	f, errs := Parse("xnull.project", sample)
	if len(errs) != 0 {
		t.Fatalf("不应有诊断：%v", errs)
	}
	proj := f.Find("project")
	if proj == nil {
		t.Fatal("缺少 project 块")
	}
	if len(proj.Children) != 8 {
		t.Fatalf("project 子项 = %d，期望 8", len(proj.Children))
	}

	deps := findBlock(proj, "dependencies")
	if deps == nil || len(deps.Children) != 2 {
		t.Fatalf("dependencies 应有 2 条")
	}
	dep := deps.Children[1].(*Block)
	if len(dep.Args) != 1 || dep.Args[0].Raw() != "com.example:xdk-web-starter" {
		t.Fatalf("依赖块头参数不符：%+v", dep.Args)
	}

	props := findBlock(proj, "properties")
	lv := findField(props, "language-version")
	if lv == nil || lv.Value.Kind != RangeValue {
		t.Fatalf("language-version 应为范围")
	}
	if !lv.Value.LoIncl || lv.Value.HiIncl {
		t.Fatalf("范围开闭不符：%+v", lv.Value)
	}
	if lv.Value.Raw() != "[3.3, 4.0)" {
		t.Fatalf("范围文本 = %q", lv.Value.Raw())
	}

	cfg := findBlock(proj, "configuration")
	eo := findField(cfg, "envOverrides")
	if eo == nil || eo.Value.Kind != ListValue || len(eo.Value.Elems) != 2 {
		t.Fatalf("envOverrides 应为两元素列表")
	}
}

func TestStringEscapesAndArgs(t *testing.T) {
	src := "lock {\n  entry a:b 1.0.0 {\n    sha256 = \"ab\\\"cd\"\n  }\n}\n"
	f, errs := Parse("xnull.lock", src)
	if len(errs) != 0 {
		t.Fatalf("不应有诊断：%v", errs)
	}
	lock := f.Find("lock")
	entry := lock.Children[0].(*Block)
	if len(entry.Args) != 2 {
		t.Fatalf("entry 应有两个参数，实际 %d", len(entry.Args))
	}
	v := findField(entry, "sha256")
	if v.Value.Text != `ab"cd` {
		t.Fatalf("转义结果 = %q", v.Value.Text)
	}
}

func TestErrors(t *testing.T) {
	cases := []struct {
		name string
		src  string
		code string
	}{
		{"缺值", "project {\n  name =\n}\n", codeNeedValue},
		{"缺等号", "project {\n  name nope = 1\n}\n", codeNeedEqOrBlk},
		{"块未闭合", "project {\n  name = x\n", codeUntermBlock},
		{"多余右括号", "}\n", codeUnexpected},
		{"字符串未闭合", "a = \"x\n", codeUntermString},
		{"非法转义", "a = \"x\\q\"\n", codeBadEscape},
		{"非法字符", "a = @\n", codeIllegalChar},
		{"BOM", "\ufeffa = 1\n", codeBOM},
		{"变量未闭合", "a = ${x\n", codeUntermVar},
		{"范围端点不足", "a = [1, 2, 3)\n", codeRangeArity},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			_, errs := Parse("t.project", c.src)
			if len(errs) == 0 {
				t.Fatalf("应报错")
			}
			for _, d := range errs {
				if d.Code == c.code {
					return
				}
			}
			t.Fatalf("期望诊断码 %s，实际 %+v", c.code, errs)
		})
	}
}

func TestMultipleErrorsReported(t *testing.T) {
	src := "project {\n  a =\n  b =\n}\n"
	_, errs := Parse("t.project", src)
	if len(errs) < 2 {
		t.Fatalf("应至少报 2 条错误（错误恢复），实际 %d", len(errs))
	}
}

// TestSpecExamples 要求规范里的每个 xpd 代码块都能被解析通过。
func TestSpecExamples(t *testing.T) {
	files, err := filepath.Glob("../../../XNull解决方案-第8部分-*.md")
	if err != nil || len(files) == 0 {
		t.Skip("未找到第 8 部分文档")
	}
	blocks := 0
	for _, path := range files {
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("读取 %s: %v", path, err)
		}
		for i, chunk := range extractBlocks(string(raw), "xpd") {
			blocks++
			if _, errs := Parse(path, chunk); len(errs) != 0 {
				t.Fatalf("%s 第 %d 个 xpd 块解析失败：\n%s\n诊断：%v", filepath.Base(path), i+1, chunk, errs)
			}
		}
	}
	if blocks < 10 {
		t.Fatalf("抽取到的 xpd 块仅 %d 个，疑似抽取逻辑失效", blocks)
	}
}

func extractBlocks(md, lang string) []string {
	var out []string
	lines := strings.Split(md, "\n")
	in, buf := false, []string{}
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if !in && trimmed == "```"+lang {
			in, buf = true, nil
			continue
		}
		if in && trimmed == "```" {
			out = append(out, strings.Join(buf, "\n"))
			in = false
			continue
		}
		if in {
			buf = append(buf, line)
		}
	}
	return out
}

func findBlock(parent *Block, name string) *Block {
	for _, c := range parent.Children {
		if b, ok := c.(*Block); ok && b.Name == name {
			return b
		}
	}
	return nil
}

func findField(parent *Block, name string) *Field {
	for _, c := range parent.Children {
		if f, ok := c.(*Field); ok && f.Name == name {
			return f
		}
	}
	return nil
}
