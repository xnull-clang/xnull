package cli

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/exitcode"
)

func TestDevUsage(t *testing.T) {
	cases := []struct {
		name    string
		args    []string
		want    int
		wantErr string
	}{
		{name: "无子命令", args: []string{"dev"}, want: exitcode.Usage, wantErr: "xnull dev <check|ledger|res>"},
		{name: "未知子命令", args: []string{"dev", "nope"}, want: exitcode.Usage, wantErr: "未知 dev 子命令"},
		{name: "res 缺参数", args: []string{"dev", "res", "only-one"}, want: exitcode.Usage, wantErr: "gen_resources: 用法"},
		{name: "res 目录不存在", args: []string{"dev", "res", "/nonexistent-res-dir", "/tmp/x.c"}, want: exitcode.Usage, wantErr: "gen_resources: 资源目录不存在"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			code, _, errOut := run(c.args...)
			if code != c.want {
				t.Fatalf("exit = %d, want %d（stderr: %s）", code, c.want, errOut)
			}
			if !strings.Contains(errOut, c.wantErr) {
				t.Fatalf("stderr 缺少 %q：%s", c.wantErr, errOut)
			}
		})
	}
}

func TestDevResGenerates(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "a.txt"), []byte("hello"), 0o644); err != nil {
		t.Fatal(err)
	}
	out := filepath.Join(t.TempDir(), "res.c")
	code, _, errOut := run("dev", "res", dir, out)
	if code != exitcode.Success {
		t.Fatalf("exit = %d, want 0（stderr: %s）", code, errOut)
	}
	data, err := os.ReadFile(out)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), `"a.txt"`) {
		t.Fatalf("生成内容缺少资源：\n%s", data)
	}
}
