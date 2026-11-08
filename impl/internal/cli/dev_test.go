package cli

import (
	"bytes"
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
		{name: "无子命令", args: []string{"dev"}, want: exitcode.Usage, wantErr: "xnull dev <check|ledger|res|board>"},
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

// S8-21：开发期 --fast 与分片；合并锁互斥。
func devTest(args ...string) (int, string, string) {
	var out, errb bytes.Buffer
	code := runDevTest(Env{Stdout: &out, Stderr: &errb}, args)
	return code, out.String(), errb.String()
}

func TestDevTestFastAndShard(t *testing.T) {
	if code, out, errOut := devTest("--fast", "devtool"); code != exitcode.Success {
		t.Fatalf("--fast devtool 应通过：%s%s", out, errOut)
	}
	if code, out, errOut := devTest("--fast", "--shard", "1/2", "manifest"); code != exitcode.Success {
		t.Fatalf("--shard 1/2 manifest 应通过：%s%s", out, errOut)
	}
	if code, _, _ := devTest("--fast", "--shard", "3/2", "manifest"); code != exitcode.Usage {
		t.Fatalf("非法分片应退出 2，实际 %d", code)
	}
	if code, out, errOut := devTest("--fast", "--parallel", "2", "devtool"); code != exitcode.Success {
		t.Fatalf("--parallel 2 devtool 应通过：%s%s", out, errOut)
	}
}

func TestMergeLockExclusive(t *testing.T) {
	root := t.TempDir()
	release, err := acquireMergeLock(root)
	if err != nil {
		t.Fatalf("首次加锁应成功：%v", err)
	}
	if _, err := acquireMergeLock(root); err == nil {
		t.Fatalf("重复加锁应失败")
	}
	release()
	if _, err := acquireMergeLock(root); err != nil {
		t.Fatalf("释放后应可再次加锁：%v", err)
	}
}
