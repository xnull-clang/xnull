package cli

import (
	"bytes"
	"io"
	"os"
	"path/filepath"
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

// 验收命令锁定：xnull run examples/hello.x 一条命令出结果。
func TestRunSingleFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "hello.x")
	os.WriteFile(path, []byte("static Int main() {\n    print(\"hello, XNull\")\n    return 0\n}"), 0o644)
	var out, errBuf bytes.Buffer
	code := Run(Env{Stdout: &out, Stderr: &errBuf, Args: []string{"run", path}})
	if code != exitcode.Success {
		t.Fatalf("退出码 %d，stderr=%s", code, errBuf.String())
	}
	if out.String() != "hello, XNull\n" {
		t.Fatalf("输出不符：%q", out.String())
	}
}

func TestRunSingleFileDeterministic(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "d.x")
	os.WriteFile(path, []byte("static Int main() {\n    for i in 0..<3 { print(i) }\n    return 0\n}"), 0o644)
	var out1, out2 bytes.Buffer
	Run(Env{Stdout: &out1, Stderr: io.Discard, Args: []string{"run", path}})
	Run(Env{Stdout: &out2, Stderr: io.Discard, Args: []string{"run", path}})
	if out1.String() != out2.String() {
		t.Fatalf("两次运行输出不一致：%q vs %q", out1.String(), out2.String())
	}
}

// ---------- ENTRY-01：入口诊断 / 两种 main 签名 / 初始化顺序 ----------

func writeTempX(t *testing.T, name, src string) string {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

// 缺失入口必须是明确诊断，不能落到 C 编译错误或静默执行。
func TestEntryMissingMainDiagnostic(t *testing.T) {
	path := writeTempX(t, "missing.x", "static Int notMain() { return 0 }\n")
	code, _, errOut := run("run", path)
	if code != exitcode.BuildFail {
		t.Fatalf("缺入口退出码 = %d，want %d（stderr：%s）", code, exitcode.BuildFail, errOut)
	}
	for _, want := range []string{"ENTRY-001", "找不到入口 main"} {
		if !strings.Contains(errOut, want) {
			t.Fatalf("stderr 缺少 %q：%s", want, errOut)
		}
	}
}

// 重复入口必须被拒绝，不能静默取第一个或让 C 侧撞名。
func TestEntryDuplicateMainDiagnostic(t *testing.T) {
	path := writeTempX(t, "dup.x", "static Int main() { return 0 }\nstatic Int main() { return 1 }\n")
	code, _, errOut := run("run", path)
	if code != exitcode.BuildFail {
		t.Fatalf("重复入口退出码 = %d，want %d（stderr：%s）", code, exitcode.BuildFail, errOut)
	}
	for _, want := range []string{"ENTRY-002", "重复入口 main"} {
		if !strings.Contains(errOut, want) {
			t.Fatalf("stderr 缺少 %q：%s", want, errOut)
		}
	}
}

// 非法签名必须在 CLI 入口前置诊断，不能交给 cc 报 C 语法错。
func TestEntrySignatureDiagnostic(t *testing.T) {
	cases := []struct {
		name string
		src  string
	}{
		{"带非 String[] 参数", "static Int main(Int x) { return 0 }\n"},
		{"返回 Bool", "static Bool main() { return true }\n"},
		{"参数个数超限", "static Int main(String[] a, String[] b) { return 0 }\n"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			path := writeTempX(t, "sig.x", c.src)
			code, _, errOut := run("run", path)
			if code != exitcode.BuildFail {
				t.Fatalf("非法入口退出码 = %d，want %d（stderr：%s）", code, exitcode.BuildFail, errOut)
			}
			if !strings.Contains(errOut, "ENTRY-003") {
				t.Fatalf("stderr 缺少 ENTRY-003：%s", errOut)
			}
			if strings.Contains(errOut, "C 编译失败") {
				t.Fatalf("非法入口不应落到 C 编译错误：%s", errOut)
			}
		})
	}
}

// 两种 main 签名的退出码：无参 / String[] args。
func TestRunMainNoArgsExitCodeInterp(t *testing.T) {
	path := writeTempX(t, "noargs.x", "static Int main() { return 7 }\n")
	code, _, errOut := run("run", "--interp", path)
	if code != 7 {
		t.Fatalf("main() 退出码 = %d，want 7（stderr：%s）", code, errOut)
	}
}

func TestRunMainNoArgsExitCodeCompiled(t *testing.T) {
	path := writeTempX(t, "noargs-compiled.x", "static Int main() { return 7 }\n")
	code, _, errOut := run("run", path)
	if code != 7 {
		t.Fatalf("编译路径 main() 退出码 = %d，want 7（stderr：%s）", code, errOut)
	}
}

func TestRunMainWithArgsInterp(t *testing.T) {
	path := writeTempX(t, "withargs.x", `static Int main(String[] args) {
    print(args.length())
    print(args[0])
    return 3
}
`)
	code, out, errOut := run("run", "--interp", path, "alpha", "beta")
	if code != 3 {
		t.Fatalf("main(String[]) 退出码 = %d，want 3（stderr：%s）", code, errOut)
	}
	if out != "2\nalpha\n" {
		t.Fatalf("main(String[]) 输出 = %q，want %q", out, "2\nalpha\n")
	}
}

// `--` 之后的参数原样作为程序参数，不能被 CLI 当成未知 flag 拒绝。
func TestRunMainWithArgsAfterSeparator(t *testing.T) {
	path := writeTempX(t, "args-sep.x", `static Int main(String[] args) {
    print(args.length())
    print(args[0])
    return 0
}
`)
	code, out, errOut := run("run", "--interp", path, "--", "--verbose", "x")
	if code != 0 {
		t.Fatalf("退出码 = %d，want 0（stderr：%s）", code, errOut)
	}
	if out != "2\n--verbose\n" {
		t.Fatalf("程序参数输出 = %q，want %q", out, "2\n--verbose\n")
	}
}

// 初始化顺序：顶层字段按声明顺序初始化，完成后才进入 main（CLI 可断言）。
func TestInitOrderViaCLI(t *testing.T) {
	path := writeTempX(t, "init-order.x", `static Int mark(String s) {
    print(s)
    return 0
}
Int a = mark("a")
Int b = mark("b")
static Int main() {
    print("main")
    return 0
}
`)
	code, out, errOut := run("run", "--interp", path)
	if code != exitcode.Success {
		t.Fatalf("退出码 = %d，want 0（stderr：%s）", code, errOut)
	}
	if out != "a\nb\nmain\n" {
		t.Fatalf("初始化顺序输出 = %q，want %q", out, "a\nb\nmain\n")
	}
}
