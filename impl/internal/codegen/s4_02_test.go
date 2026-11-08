package codegen

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/sema"
	"xnull.dev/xnull/internal/xfront"
)

// compileAndRunPolicyFull 与 compileAndRunPolicy 相同，但分别返回 stdout/stderr。
func compileAndRunPolicyFull(t *testing.T, src string) (string, string, int) {
	t.Helper()
	u, diags := xfront.ParseUnit("t.x", src)
	if len(diags) != 0 {
		t.Fatalf("解析诊断：%v", diags)
	}
	res, sd := sema.AnalyzeWith("t.x", u)
	if len(sd) != 0 {
		t.Fatalf("语义诊断：%v", sd)
	}
	csrc, err := EmitCWithStrategies(u, nil, res.Strategies(u))
	if err != nil {
		t.Fatalf("代码生成失败：%v", err)
	}
	dir := t.TempDir()
	cfile := filepath.Join(dir, "prog.c")
	if err := os.WriteFile(cfile, []byte(csrc), 0o644); err != nil {
		t.Fatal(err)
	}
	bin := filepath.Join(dir, "prog")
	rt := filepath.Join("..", "..", "runtime")
	args := []string{"-std=c11", "-O2", "-I", rt, "-o", bin, cfile}
	for _, s := range runtimeCSources {
		args = append(args, filepath.Join(rt, s))
	}
	args = append(args, writeEmptyResourceTable(t, t.TempDir()))
	var ccerr bytes.Buffer
	cc := exec.Command("cc", args...)
	cc.Stderr = &ccerr
	if err := cc.Run(); err != nil {
		t.Fatalf("cc 编译失败：%v\n%s\n---- C ----\n%s", err, ccerr.String(), csrc)
	}
	var out, errb bytes.Buffer
	run := exec.Command(bin)
	run.Stdout = &out
	run.Stderr = &errb
	code := 0
	if err := run.Run(); err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			code = ee.ExitCode()
		} else {
			t.Fatal(err)
		}
	}
	return out.String(), errb.String(), code
}

// S4-02：wrap/mapErr/report 发射与 Result 观测成员（任意 E，类错误）。
func TestS4_02WrapMapErrReport(t *testing.T) {
	src := `import xdk.errors
class E1 implements Error {
    ErrorKind kind() { return ErrorKind.Io }
    String describe() { return "io-err" }
}
class E2 implements Error {
    ErrorKind kind() { return ErrorKind.NotFound }
    String describe() { return "missing" }
}
static E1 conv(E1 e) { return new E1() }
static Int main() {
    Result<Int, E1> bad = Err(new E1())
    Result<Int, E1> mapped = mapErr(bad, conv)
    report(mapped)
    Result<Int, E1> wrapped = wrap(mapped, new E1())
    print(wrapped.isErr())
    E1 e = bad.error()
    print(e.describe())
    Result<Int, E1> good = Ok(5)
    Result<Int, E1> m2 = mapErr(good, conv)
    print(m2.unwrapOr(0))
    report(m2)
    return 0
}`
	stdout, stderr, code := compileAndRunPolicyFull(t, src)
	wantOut := "true\nio-err\n5\n"
	if code != 0 || stdout != wantOut {
		t.Fatalf("stdout=%q code=%d，期望 %q", stdout, code, wantOut)
	}
	if got, want := strings.TrimSuffix(stderr, "\n"), "[Io] io-err"; got != want {
		t.Fatalf("stderr=%q，期望单行 %q", stderr, want)
	}
	if strings.Count(strings.TrimSuffix(stderr, "\n"), "\n") != 0 {
		t.Fatalf("report 不是单行：%q", stderr)
	}
}

// S4-02：report 失败单行、成功零输出；诊断通道无堆分配（write + 栈缓冲）。
func TestS4_02ReportContract(t *testing.T) {
	src := `import xdk.errors
class E implements Error {
    ErrorKind kind() { return ErrorKind.PermissionDenied }
    String describe() { return "denied\nsecond-line" }
}
static Int main() {
    Result<Int, E> ok = Ok(1)
    report(ok)
    Result<Int, E> bad = Err(new E())
    report(bad)
    print(bad.isErr())
    return 0
}`
	csrc := emitWithPolicy(t, src)
	for _, want := range []string{"xn_report_line(", "write(STDERR_FILENO", "xrt_error_kind_name("} {
		if !strings.Contains(csrc, want) {
			t.Fatalf("缺少 S4-02 诊断发射产物 %q：\n%s", want, csrc)
		}
	}
	// report 链式返回原 Result（XDK 定案 3-a-1）。
	if !strings.Contains(csrc, "xn_Result_Int_E xn_t") && !strings.Contains(csrc, "= xn_t") {
		t.Fatalf("report 未返回原 Result：\n%s", csrc)
	}
	stdout, stderr, code := compileAndRunPolicyFull(t, src)
	if code != 0 || stdout != "true\n" {
		t.Fatalf("stdout=%q code=%d，期望 true", stdout, code)
	}
	trimmed := strings.TrimSuffix(stderr, "\n")
	if trimmed != "[PermissionDenied] denied second-line" {
		t.Fatalf("stderr=%q，期望折叠为单行", stderr)
	}
	if strings.Count(trimmed, "\n") != 0 {
		t.Fatalf("report 输出含额外行：%q", stderr)
	}
}

// S4-02：结构体错误 + ErrorKind 内建枚举（值/名称对齐 S4 §3.1）。
func TestS4_02StructErrorAndErrorKind(t *testing.T) {
	src := `import xdk.errors
struct Err2 {
    Int code;
    Err2(Int c) { self.code = c }
    ErrorKind kind() { return ErrorKind.Timeout }
    String describe() { return "timed out" }
}
static Int main() {
    Result<Int, Err2> r = Err(new Err2(7))
    report(r)
    ErrorKind k = ErrorKind.Timeout
    print(k)
    print(ErrorKind.Io)
    return 0
}`
	stdout, stderr, code := compileAndRunPolicyFull(t, src)
	if code != 0 {
		t.Fatalf("code=%d stdout=%q stderr=%q", code, stdout, stderr)
	}
	if want := "Timeout\nIo\n"; stdout != want {
		t.Fatalf("stdout=%q，期望 %q", stdout, want)
	}
	if want := "[Timeout] timed out"; strings.TrimSuffix(stderr, "\n") != want {
		t.Fatalf("stderr=%q，期望 %q", stderr, want)
	}
}
