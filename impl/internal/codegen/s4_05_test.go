package codegen

import (
	"bytes"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/sema"
	"xnull.dev/xnull/internal/xfront"
)

// S4-05 / BOUND-01：进程级退出码——0 / 非零原样 / fatal 134（编译路径）。
func TestS4BOUND01ProcessExitCodes(t *testing.T) {
	cases := []struct {
		name string
		src  string
		out  string
		code int
	}{
		{"成功 0", "static Int main() { print(\"ok\")\n return 0 }", "ok\n", 0},
		{"非零原样", "static Int main() { return 42 }", "", 42},
		{"fatal 除零 134", "Int d = 0\nInt a = 10 / d\nstatic Int main() { print(\"MAIN-SHOULD-NOT-RUN\")\n return 0 }", "", 134},
		{"fatal throw 134", "static Int main() { print(\"before\")\n throw \"boom\"\n return 0 }", "before\n", 134},
		{"void main 0", "static void main() { print(\"v\") }", "v\n", 0},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, code := compileAndRunPolicy(t, c.src)
			if code != c.code {
				t.Fatalf("退出码 %d，期望 %d（stdout=%q）", code, c.code, got)
			}
			if got != c.out {
				t.Fatalf("stdout=%q，期望 %q", got, c.out)
			}
		})
	}
}

// S4-05 / BOUND-02：Result 不跨语言边界——FFI 合同拒绝（参数与返回两侧）。
func TestS4BOUND02ResultNoCrossBoundary(t *testing.T) {
	cases := []struct{ name, decl string }{
		{"参数位", "  Int32 f(Result r);"},
		{"返回位", "  Result g();"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			dir := t.TempDir()
			xfb := "ffi x {\n  @ffiEntry(cName = \"f\")\n  @lease(r = .borrow)\n  @blocking(.aware)\n" + c.decl + "\n}\n"
			writeFFIFile(t, filepath.Join(dir, "bindings", "a.xfb"), xfb)
			reg, diags, err := LoadFFI(dir)
			if err != nil {
				t.Fatalf("LoadFFI: %v", err)
			}
			if len(diags) == 0 {
				t.Fatalf("Result 跨边界未被拒绝（reg=%v）", reg)
			}
			found := false
			for _, d := range diags {
				if strings.Contains(d.Message, "Result 不跨语言边界") {
					found = true
				}
			}
			if !found {
				t.Fatalf("诊断未点名 Result 跨边界：%v", diags)
			}
		})
	}
}

// S4-05 / CLEAN-01：errdefer 补偿（LIFO）/部分完成；Ok 路径不执行补偿；
// 原错误不被补偿覆盖。
func TestS4CLEAN01ErrdeferCompensation(t *testing.T) {
	src := `class Res {
    String name;
    Res(String n) { self.name = n }
    void close() { print("close:" + self.name) }
}
class State {
    Int n = 0;
    void inc() { self.n = self.n + 1 }
    void dec() { self.n = self.n - 1 }
}
static Result<Int, String> tx(State s) {
    s.inc()
    errdefer s.dec()
    s.inc()
    errdefer s.dec()
    return Err("fail")
}
static Result<Int, String> inner() {
    errdefer print("inner-e")
    return Err("x")
}
static Result<Int, String> outer() {
    errdefer print("outer-e")
    Int v = try inner()
    return Ok(v)
}
static Result<Int, String> work(Res a, Res b) {
    errdefer a.close()
    print("work")
    errdefer b.close()
    return Err("boom")
}
static Result<Int, String> ok(Res a) {
    errdefer a.close()
    return Ok(1)
}
static Int main() {
    Res a = new Res("a")
    Res b = new Res("b")
    Result<Int, String> r = work(a, b)
    if (r.isErr()) {
        print("err:" + r.error())
    }
    Result<Int, String> s = ok(a)
    print(s.unwrapOr(0))
    State st = new State()
    Result<Int, String> t = tx(st)
    print(st.n)
    print(t.error())
    Result<Int, String> o = outer()
    print(o.isErr())
    return 0
}`
	got, code := compileAndRunPolicy(t, src)
	// 补偿按注册逆序（b 后注册先执行），原错误 boom 保留；Ok 路径不补偿；
	// 部分完成回滚后状态归零；try 逐层传播触发 errdefer。
	want := "work\nclose:b\nclose:a\nerr:boom\n1\n0\nfail\ninner-e\nouter-e\ntrue\n"
	if code != 0 || got != want {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
}

// S4-05 / FFI 边界错误路径：非零错误码 → fatal 134，未知码归 Internal（绝不 Ok）。
func TestS4FFIBoundaryErrorPaths(t *testing.T) {
	cases := []struct {
		name     string
		errorMap string
		native   string
		kind     string
	}{
		{"已映射码", "  errorMap {\n    7 = NotFound\n  }\n", "7", "NotFound"},
		{"未知码", "", "9", "Internal"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			dir := t.TempDir()
			xfb := `ffi t {
` + c.errorMap + `  @ffiEntry(cName = "stub_fail")
  @lease(code = .borrow)
  @errorCode(codeParam = .code)
  @blocking(.aware)
  Int32 stubFail(Int32 code);
}
`
			writeFFIFile(t, filepath.Join(dir, "bindings", "t.xfb"), xfb)
			mainSrc := "static Int main() {\n    Int32 code = 0\n    stubFail(code)\n    print(\"MAIN-SHOULD-NOT-RUN\")\n    return 0\n}\n"
			mainPath := filepath.Join(dir, "main.x")
			writeFFIFile(t, mainPath, mainSrc)
			nativePath := filepath.Join(dir, "stub.c")
			writeFFIFile(t, nativePath, "#include <stdint.h>\nint32_t stub_fail(int32_t *code) { *code = "+c.native+"; return 0; }\n")

			reg, diags, err := LoadFFI(dir)
			if err != nil || len(diags) != 0 {
				t.Fatalf("LoadFFI: err=%v diags=%v", err, diags)
			}
			u, pdiags := xfront.ParseUnit(mainPath, mainSrc)
			if len(pdiags) != 0 {
				t.Fatalf("解析诊断：%v", pdiags)
			}
			if err := InjectFFI(u, reg); err != nil {
				t.Fatalf("InjectFFI: %v", err)
			}
			if sd := sema.Analyze(mainPath, u); len(sd) != 0 {
				t.Fatalf("语义诊断：%v", sd)
			}
			csrc, err := EmitCWithFFI(u, reg)
			if err != nil {
				t.Fatalf("EmitCWithFFI: %v", err)
			}
			rt := filepath.Join("..", "..", "runtime")
			cfile := filepath.Join(dir, "prog.c")
			writeFFIFile(t, cfile, csrc)
			bin := filepath.Join(dir, "prog")
			args := []string{"-std=c11", "-O2", "-I", rt, "-o", bin, cfile, nativePath}
			for _, s := range runtimeCSources {
				args = append(args, filepath.Join(rt, s))
			}
			var cerr bytes.Buffer
			cc := exec.Command("cc", args...)
			cc.Stderr = &cerr
			if err := cc.Run(); err != nil {
				t.Fatalf("cc 失败：%v\n%s\n---- C ----\n%s", err, cerr.String(), csrc)
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
			if code != 134 {
				t.Fatalf("退出码 %d，期望 134（stderr=%s）", code, errb.String())
			}
			if out.String() != "" {
				t.Fatalf("FFI 失败后入口仍继续执行：stdout=%q", out.String())
			}
			if !strings.Contains(errb.String(), c.kind) || !strings.Contains(errb.String(), "错误码") {
				t.Fatalf("stderr 未点名错误分类 %q：%s", c.kind, errb.String())
			}
		})
	}
}
