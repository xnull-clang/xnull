package cli

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/exitcode"
)

// S8-16：fmt 支持 .x 源码（--check 只检查）。
func TestFmtSource(t *testing.T) {
	dir := t.TempDir()
	src := "static Int main(){\nreturn 0\n}\n"
	p := filepath.Join(dir, "a.x")
	if err := os.WriteFile(p, []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
	// --check 未格式化 → 1，且不写文件
	code, _, errOut := run("fmt", "--check", p)
	if code != exitcode.BuildFail {
		t.Fatalf("--check 未格式化应退出 1，实际 %d（%s）", code, errOut)
	}
	if data, _ := os.ReadFile(p); string(data) != src {
		t.Fatalf("--check 不得写文件")
	}
	// 写回
	code, _, errOut = run("fmt", p)
	if code != exitcode.Success {
		t.Fatalf("fmt 应成功，实际 %d（%s）", code, errOut)
	}
	got, _ := os.ReadFile(p)
	want := "static Int main() {\n    return 0\n}\n"
	if string(got) != want {
		t.Fatalf("格式化结果不符：%q", got)
	}
	// 已格式化 --check → 0
	if code, _, _ := run("fmt", "--check", p); code != exitcode.Success {
		t.Fatalf("已格式化 --check 应退出 0，实际 %d", code)
	}
}

// S8-16：clean 清理 target；--all 连本地仓库缓存。
func TestClean(t *testing.T) {
	dir := t.TempDir()
	repo := t.TempDir()
	t.Setenv("XNULL_REPO", repo)
	if err := os.MkdirAll(filepath.Join(dir, "target", ".cache"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "target", "x.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(repo, "r.txt"), []byte("r"), 0o644); err != nil {
		t.Fatal(err)
	}
	code, out, errOut := run("clean", dir)
	if code != exitcode.Success {
		t.Fatalf("clean 应成功，实际 %d（%s%s）", code, out, errOut)
	}
	if _, err := os.Stat(filepath.Join(dir, "target")); !os.IsNotExist(err) {
		t.Fatalf("target 未清理")
	}
	if _, err := os.Stat(filepath.Join(repo, "r.txt")); err != nil {
		t.Fatalf("不带 --all 不应清仓库：%v", err)
	}
	os.MkdirAll(filepath.Join(dir, "target"), 0o755)
	if code, _, errOut := run("clean", "--all", dir); code != exitcode.Success {
		t.Fatalf("clean --all 应成功：%s", errOut)
	}
	if _, err := os.Stat(filepath.Join(repo, "r.txt")); !os.IsNotExist(err) {
		t.Fatalf("--all 应清理本地仓库缓存")
	}
}

// S8-16：version/--version 输出完整版本信息。
func TestVersionOutput(t *testing.T) {
	for _, args := range [][]string{{"version"}, {"--version"}} {
		code, out, errOut := run(args...)
		if code != exitcode.Success {
			t.Fatalf("%v 应成功：%s", args, errOut)
		}
		for _, want := range []string{Version, "commit:", "build date:", "specs:", "abi:"} {
			if !strings.Contains(out, want) {
				t.Fatalf("%v 输出缺少 %q：\n%s", args, want, out)
			}
		}
	}
}

// S8-16：doctor 环境自检（cc/runtime/repo/manifest/lock）。
func TestDoctor(t *testing.T) {
	dir := t.TempDir()
	repo := t.TempDir()
	t.Setenv("XNULL_REPO", repo)
	t.Setenv("XNULL_RUNTIME", "../../runtime")
	if err := os.WriteFile(filepath.Join(dir, "xnull.project"), []byte(`project {
  groupId = g
  artifactId = a
  version = 1.0.0
  packaging = app
}
`), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "xnull.lock"), []byte("lock {\n  version = 1\n}\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	code, out, errOut := run("doctor", dir)
	if code != exitcode.Success {
		t.Fatalf("doctor 应通过：%s", errOut)
	}
	for _, want := range []string{"cc", "runtime", "repo", "manifest", "lock"} {
		if !strings.Contains(out, want) {
			t.Fatalf("doctor 输出缺少 %q：\n%s", want, out)
		}
	}
}
