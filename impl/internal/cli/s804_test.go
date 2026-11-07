package cli

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/exitcode"
)

// S8-04：清单模式生命周期、build 字段、入口解析、.xmeta、退出码。

func writeManifestProject(t *testing.T, manifest, mainSrc string) string {
	t.Helper()
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "xnull.project"), []byte(manifest), 0o644); err != nil {
		t.Fatal(err)
	}
	if mainSrc != "" {
		p := filepath.Join(root, "src", "main", "x")
		if err := os.MkdirAll(p, 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(p, "main.x"), []byte(mainSrc), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

const s804Manifest = `project {
  groupId    = com.example
  artifactId = app
  version    = 1.2.3
  packaging  = app

  properties {
    xdk-version      = 1.1.0
    language-version = [3.3, 4.0)
  }

  build {
    mode     = release
    warnings = strict
    entryFile = src/main/x/main.x
    entryPackage = com.example.app
  }
}
`

const s804Main = `package com.example.app

static Int main() {
    return 0
}
`

func runIn(t *testing.T, dir string, args ...string) (int, string, string) {
	t.Helper()
	var out, errb bytes.Buffer
	code := Run(Env{Stdout: &out, Stderr: &errb, Args: args, Dir: dir})
	return code, out.String(), errb.String()
}

func TestS804ManifestBuildLifecycle(t *testing.T) {
	root := writeManifestProject(t, s804Manifest, s804Main)
	code, out, errOut := runIn(t, root, "build")
	if code != exitcode.Success {
		t.Fatalf("exit=%d stderr=%s", code, errOut)
	}
	artifact := filepath.Join(root, "target", "app-1.2.3")
	if !strings.Contains(out, artifact) {
		t.Fatalf("stdout 未报告产物：%q", out)
	}
	if st, err := os.Stat(artifact); err != nil || st.IsDir() {
		t.Fatalf("产物不存在：%v", err)
	}
	metaPath := filepath.Join(root, "target", "app-1.2.3.xmeta")
	meta, err := os.ReadFile(metaPath)
	if err != nil {
		t.Fatalf("缺 .xmeta：%v", err)
	}
	s := string(meta)
	for _, want := range []string{
		"xmeta {", "groupId          = com.example", "artifactId       = app",
		"version          = 1.2.3", "packaging        = app",
		"xdkVersion       = 1.1.0", "languageVersion  = [3.3, 4.0)",
		"toolchainVersion = " + Version, "profiles         = []",
		"lockSha256       = ", "inputs           = ",
	} {
		if !strings.Contains(s, want) {
			t.Fatalf(".xmeta 缺少 %q：\n%s", want, s)
		}
	}

	// 可复现：两次构建 .xmeta 字节一致（S8 §5.3 / PROJ-09）。
	first := s
	if code, _, errOut := runIn(t, root, "build"); code != 0 {
		t.Fatalf("第二次构建失败：%s", errOut)
	}
	again, _ := os.ReadFile(metaPath)
	if string(again) != first {
		t.Fatalf(".xmeta 两次构建不一致")
	}
}

func TestS804SkipTestStage(t *testing.T) {
	root := writeManifestProject(t, s804Manifest, s804Main)
	testDir := filepath.Join(root, "src", "test", "x")
	if err := os.MkdirAll(testDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(testDir, "main.x"), []byte("static Int main() { return 3 }"), 0o644); err != nil {
		t.Fatal(err)
	}
	if code, _, _ := runIn(t, root, "build"); code != exitcode.BuildFail {
		t.Fatalf("测试入口失败应返回 1，实际 %d", code)
	}
	if code, _, errOut := runIn(t, root, "build", "--skip", "test"); code != exitcode.Success {
		t.Fatalf("--skip test 应成功：%d %s", code, errOut)
	}
}

func TestS804ManifestFieldValidation(t *testing.T) {
	cases := []struct {
		name string
		body string
		want string
	}{
		{"mode 非法", strings.Replace(s804Manifest, "mode     = release", "mode = fast", 1), "build.mode"},
		{"warnings 非法", strings.Replace(s804Manifest, "warnings = strict", "warnings = loud", 1), "build.warnings"},
		{"sourceRoot 含 target", strings.Replace(s804Manifest, "entryFile = src/main/x/main.x", "sourceRoot = target/x", 1), "target/"},
		{"非 app 声明入口", strings.Replace(strings.Replace(s804Manifest, "packaging  = app", "packaging  = library", 1), "packaging  = app", "packaging  = library", 1), "非 app"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			root := writeManifestProject(t, tc.body, s804Main)
			code, _, errOut := runIn(t, root, "build")
			if code != exitcode.Usage {
				t.Fatalf("应返回 2（清单错误），实际 %d：%s", code, errOut)
			}
			if !strings.Contains(errOut, tc.want) {
				t.Fatalf("诊断未指明 %q：%s", tc.want, errOut)
			}
		})
	}
}

func TestS804EntryResolution(t *testing.T) {
	t.Run("entryPackage 不匹配", func(t *testing.T) {
		root := writeManifestProject(t, s804Manifest, s804Main)
		code, _, errOut := runIn(t, root, "build")
		if code != 0 {
			t.Fatalf("匹配入口应成功：%d %s", code, errOut)
		}
		// 改 package 后应失败。
		p := filepath.Join(root, "src", "main", "x", "main.x")
		os.WriteFile(p, []byte("package other\n\nstatic Int main() { return 0 }\n"), 0o644)
		code, _, errOut = runIn(t, root, "build")
		if code != exitcode.Usage || !strings.Contains(errOut, "entryPackage") {
			t.Fatalf("entryPackage 不匹配应返回 2：%d %s", code, errOut)
		}
	})

	t.Run("入口缺失", func(t *testing.T) {
		root := writeManifestProject(t, s804Manifest, "")
		code, _, errOut := runIn(t, root, "build")
		if code != exitcode.Usage || !strings.Contains(errOut, "入口文件不存在") {
			t.Fatalf("缺入口应返回 2：%d %s", code, errOut)
		}
	})

	t.Run("自定义 entryFile", func(t *testing.T) {
		root := writeManifestProject(t, strings.Replace(s804Manifest,
			"entryFile = src/main/x/main.x", "entryFile = src/main/x/custom.x", 1), "")
		p := filepath.Join(root, "src", "main", "x")
		os.MkdirAll(p, 0o755)
		os.WriteFile(filepath.Join(p, "custom.x"), []byte(s804Main), 0o644)
		if code, _, errOut := runIn(t, root, "build"); code != 0 {
			t.Fatalf("自定义入口应成功：%d %s", code, errOut)
		}
	})
}

func TestS804ExitCodes(t *testing.T) {
	t.Run("清单文法错误 → 2", func(t *testing.T) {
		root := writeManifestProject(t, "project {\n  groupId = x\n", s804Main)
		code, _, errOut := runIn(t, root, "build")
		if code != exitcode.Usage {
			t.Fatalf("文法错误应返回 2，实际 %d：%s", code, errOut)
		}
	})
	t.Run("编译失败 → 1", func(t *testing.T) {
		root := writeManifestProject(t, s804Manifest, "static Int main() { return }\n")
		code, _, _ := runIn(t, root, "build")
		if code != exitcode.BuildFail {
			t.Fatalf("编译失败应返回 1，实际 %d", code)
		}
	})
}

func TestS804RunManifest(t *testing.T) {
	root := writeManifestProject(t, s804Manifest, `package com.example.app

static Int main() {
    print("manifest-run")
    return 0
}
`)
	code, out, errOut := runIn(t, root, "run")
	if code != 0 {
		t.Fatalf("run 失败：%d %s", code, errOut)
	}
	if !strings.Contains(out, "manifest-run") {
		t.Fatalf("run 输出不符：%q", out)
	}
}
