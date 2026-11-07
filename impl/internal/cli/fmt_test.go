package cli

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/exitcode"
)

func runFmtCmd(t *testing.T, args ...string) (int, string, string) {
	t.Helper()
	var out, errb bytes.Buffer
	code := Run(Env{Stdout: &out, Stderr: &errb, Args: args})
	return code, out.String(), errb.String()
}

func TestS810FmtManifestCheckAndWrite(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "xnull.project")
	src := "project com.example:demo 1.0.0 {\ngroupId = com.example\n  artifactId = demo\n}\n"
	if err := os.WriteFile(path, []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}

	code, _, errOut := runFmtCmd(t, "fmt", "--check", path)
	if code != exitcode.BuildFail {
		t.Fatalf("未格式化文件 --check 应失败：exit=%d stderr=%s", code, errOut)
	}

	code, _, errOut = runFmtCmd(t, "fmt", "--write", path)
	if code != exitcode.Success {
		t.Fatalf("--write 失败：exit=%d stderr=%s", code, errOut)
	}
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	want := "project com.example:demo 1.0.0 {\n  groupId = com.example\n  artifactId = demo\n}\n"
	if string(got) != want {
		t.Fatalf("格式化结果不符：\n got=%q\nwant=%q", got, want)
	}

	if code, _, errOut := runFmtCmd(t, "fmt", "--check", path); code != exitcode.Success {
		t.Fatalf("格式化后 --check 应通过：exit=%d stderr=%s", code, errOut)
	}
}

func TestS810FmtLockAndMeta(t *testing.T) {
	dir := t.TempDir()
	lock := filepath.Join(dir, "xnull.lock")
	if err := os.WriteFile(lock, []byte("lock {\nversion = 1\nentry com.example:common 1.4.0 {\nkind = dependency\n}\n}\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	meta := filepath.Join(dir, "demo.xmeta")
	if err := os.WriteFile(meta, []byte("plugin com.example:demo 1.0.0 {\ngroupId = com.example\n}\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	for _, p := range []string{lock, meta} {
		if code, _, errOut := runFmtCmd(t, "fmt", "--write", p); code != exitcode.Success {
			t.Fatalf("格式化 %s 失败：exit=%d stderr=%s", p, code, errOut)
		}
		if code, _, errOut := runFmtCmd(t, "fmt", "--check", p); code != exitcode.Success {
			t.Fatalf("%s 格式化后 --check 失败：exit=%d stderr=%s", p, code, errOut)
		}
	}
}

func TestS810FmtSyntaxError(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "xnull.project")
	if err := os.WriteFile(path, []byte("project {\n  a =\n}\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	code, _, errOut := runFmtCmd(t, "fmt", "--check", path)
	if code != exitcode.BuildFail {
		t.Fatalf("语法错误应失败：exit=%d stderr=%s", code, errOut)
	}
	if !strings.Contains(errOut, "XPD-") {
		t.Fatalf("缺少 XPD 诊断：%s", errOut)
	}
}
