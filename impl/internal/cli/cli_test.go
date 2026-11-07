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

// ---------- ENTRY-01（M1）：入口与启动 ----------

// writeSrc 在临时目录写出单文件源码，返回路径。
func writeSrc(t *testing.T, src string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "entry.x")
	if err := os.WriteFile(path, []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

// §11.2：void/Int × 无参/String[] 参数，四种入口形态在编译路径均可运行。
func TestRunEntryTwoSignatures(t *testing.T) {
	cases := []struct {
		name string
		src  string
		want string
		code int
	}{
		{"void 无参", "static void main() { print(\"v\") }", "v\n", exitcode.Success},
		{"Int 无参", "static Int main() { print(\"i\"); return 4 }", "i\n", 4},
		{"void args", "static void main(final String[] args) { print(\"va\") }", "va\n", exitcode.Success},
		{"Int args", "static Int main(final String[] args) { print(\"ia\"); return 5 }", "ia\n", 5},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			code, out, errOut := run("run", writeSrc(t, c.src))
			if code != c.code {
				t.Fatalf("退出码 %d，期望 %d（stderr=%s）", code, c.code, errOut)
			}
			if out != c.want {
				t.Fatalf("stdout=%q，期望 %q", out, c.want)
			}
		})
	}
}

// §11.2：args 是运行时创建的新数组，元素为进程参数（不含程序名）。
func TestRunEntryArgsArray(t *testing.T) {
	path := writeSrc(t, "static Int main(final String[] args) {\n    print(str(args.length()))\n    return 0\n}")
	code, out, errOut := run("run", path, "alpha", "beta")
	if code != exitcode.Success {
		t.Fatalf("退出码 %d（stderr=%s）", code, errOut)
	}
	if out != "2\n" {
		t.Fatalf("stdout=%q，期望 2 个参数", out)
	}
	// 解释路径参数语义一致（不含程序名、不含标志）
	code, out, _ = run("run", path, "--interp", "alpha", "beta")
	if code != exitcode.Success || out != "2\n" {
		t.Fatalf("解释路径 code=%d stdout=%q，期望 2 个参数", code, out)
	}
}

// §11.3：顶层字段先于入口、按声明顺序初始化；解释/编译双路径一致。
func TestRunEntryInitOrder(t *testing.T) {
	src := `static Int mark(Int v) {
    print("init " + str(v))
    return v
}
Int a = mark(1)
Int b = mark(a + 1)
static Int main() {
    print("main " + str(b))
    return 0
}`
	path := writeSrc(t, src)
	want := "init 1\ninit 2\nmain 2\n"
	code, out, errOut := run("run", path)
	if code != exitcode.Success || out != want {
		t.Fatalf("编译路径 code=%d out=%q err=%s", code, out, errOut)
	}
	code, out, _ = run("run", path, "--interp")
	if code != exitcode.Success || out != want {
		t.Fatalf("解释路径 code=%d out=%q", code, out)
	}
}

// §11.4：缺失入口是编译错误，不得落到 cc。
func TestRunEntryMissingRejected(t *testing.T) {
	code, _, errOut := run("run", writeSrc(t, "static Int helper() { return 1 }"))
	if code != exitcode.BuildFail {
		t.Fatalf("退出码 %d，期望 1", code)
	}
	if !strings.Contains(errOut, "入口") {
		t.Fatalf("诊断应点名入口：%s", errOut)
	}
}

// §11.4：重复入口是编译错误。
func TestRunEntryDuplicateRejected(t *testing.T) {
	src := "static Int main() { return 0 }\nstatic Int main() { return 1 }"
	code, _, errOut := run("run", writeSrc(t, src))
	if code != exitcode.BuildFail {
		t.Fatalf("退出码 %d，期望 1", code)
	}
	if !strings.Contains(errOut, "重复入口") {
		t.Fatalf("诊断应点名重复入口：%s", errOut)
	}
}
