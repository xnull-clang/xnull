package cli

import (
	"bytes"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/exitcode"
)

func run(args ...string) (int, string, string) {
	var out, errb bytes.Buffer
	code := Run(Env{Stdout: &out, Stderr: &errb, Args: args})
	return code, out.String(), errb.String()
}

func TestRun(t *testing.T) {
	cases := []struct {
		name    string
		args    []string
		want    int
		wantOut string
		wantErr string
	}{
		{name: "无参数打印用法", args: nil, want: exitcode.Success, wantOut: "用法：xnull"},
		{name: "版本", args: []string{"--version"}, want: exitcode.Success, wantOut: "xnull " + Version},
		{name: "帮助", args: []string{"help"}, want: exitcode.Success, wantOut: "退出码：0 成功"},
		{name: "未知命令", args: []string{"biuld"}, want: exitcode.Usage, wantErr: "CLI-001"},
		{name: "未知参数", args: []string{"--nope"}, want: exitcode.Usage, wantErr: "CLI-002"},
		{name: "未知标志", args: []string{"build", "--force"}, want: exitcode.Usage, wantErr: "CLI-002"},
		{name: "缺清单", args: []string{"build"}, want: exitcode.Usage, wantErr: "CLI-003"},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			code, out, errOut := run(c.args...)
			if code != c.want {
				t.Fatalf("exit = %d, want %d (stderr: %s)", code, c.want, errOut)
			}
			if c.wantOut != "" && !strings.Contains(out, c.wantOut) {
				t.Fatalf("stdout 缺少 %q：%s", c.wantOut, out)
			}
			if c.wantErr != "" && !strings.Contains(errOut, c.wantErr) {
				t.Fatalf("stderr 缺少 %q：%s", c.wantErr, errOut)
			}
		})
	}
}

func TestUnknownCommandIsUsageError(t *testing.T) {
	code, _, errOut := run("deploy")
	if code != exitcode.Usage {
		t.Fatalf("deploy 应被拒绝并返回 2，实际 %d", code)
	}
	if !strings.Contains(errOut, "xnull:1:1") {
		t.Fatalf("诊断缺少位置前缀：%s", errOut)
	}
}
