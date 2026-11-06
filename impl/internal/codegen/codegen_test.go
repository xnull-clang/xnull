package codegen

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/interp"
	"xnull.dev/xnull/internal/sema"
	"xnull.dev/xnull/internal/xfront"
)

// compileAndRun 生成 C → cc 编译 → 运行，返回 stdout 与退出码。
func compileAndRun(t *testing.T, src string) (string, int) {
	t.Helper()
	u, diags := xfront.ParseUnit("t.xn", src)
	if len(diags) != 0 {
		t.Fatalf("解析诊断：%v", diags)
	}
	if sd := sema.Analyze("t.xn", u); len(sd) != 0 {
		t.Fatalf("语义诊断：%v", sd)
	}
	csrc, err := EmitC(u)
	if err != nil {
		t.Fatalf("代码生成失败：%v", err)
	}
	dir := t.TempDir()
	cfile := filepath.Join(dir, "prog.c")
	if err := os.WriteFile(cfile, []byte(csrc), 0o644); err != nil {
		t.Fatal(err)
	}
	bin := filepath.Join(dir, "prog")
	cc := exec.Command("cc", "-std=c11", "-I", "../../../impl/runtime", "-O2", "-o", bin,
		cfile, "../../../impl/runtime/rt.c", "../../../impl/runtime/rt_gc.c",
		"../../../impl/runtime/rt_policy.c", "../../../impl/runtime/rt_weak.c")
	var ccerr bytes.Buffer
	cc.Stderr = &ccerr
	if err := cc.Run(); err != nil {
		t.Fatalf("cc 编译失败：%v\n%s", err, ccerr.String())
	}
	var out bytes.Buffer
	run := exec.Command(bin)
	run.Stdout = &out
	code := 0
	if err := run.Run(); err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			code = ee.ExitCode()
		} else {
			t.Fatal(err)
		}
	}
	return out.String(), code
}

// interpRun 解释执行，返回 stdout 与退出码。
func interpRun(t *testing.T, src string) (string, int) {
	t.Helper()
	u, diags := xfront.ParseUnit("t.xn", src)
	if len(diags) != 0 {
		t.Fatalf("解析诊断：%v", diags)
	}
	var out strings.Builder
	code, err := interp.Run(u, &out, nil)
	if err != nil {
		t.Fatalf("解释执行失败：%v", err)
	}
	return out.String(), code
}

// TestExamplesCompileMatchesInterp M4 完成定义：编译路径输出与解释器逐字节一致。
func TestExamplesCompileMatchesInterp(t *testing.T) {
	examples, err := filepath.Glob("../../../examples/*.xn")
	if err != nil || len(examples) == 0 {
		t.Fatalf("找不到示例：%v", err)
	}
	for _, ex := range examples {
		ex := ex
		t.Run(filepath.Base(ex), func(t *testing.T) {
			src, err := os.ReadFile(ex)
			if err != nil {
				t.Fatal(err)
			}
			want, wantCode := interpRun(t, string(src))
			got, gotCode := compileAndRun(t, string(src))
			if got != want {
				t.Fatalf("输出不一致（%s）：\n--- 编译 ---\n%s\n--- 解释 ---\n%s", ex, got, want)
			}
			if gotCode != wantCode {
				t.Fatalf("退出码不一致（%s）：编译 %d != 解释 %d", ex, gotCode, wantCode)
			}
		})
	}
}

// TestCompileDeferSemantics defer/errdefer 硬语义在编译路径保持（§10.3）。
func TestCompileDeferSemantics(t *testing.T) {
	src := `
static Int work() {
    print("A")
    defer print("c1")
    defer print("c2")
    if true {
        print("B")
        defer print("inner")
        print("C")
    }
    print("D")
    return 0
}

static Int main() {
    work()
    return 0
}`
	got, code := compileAndRun(t, src)
	want := "A\nB\nC\ninner\nD\nc2\nc1\n"
	if got != want || code != 0 {
		t.Fatalf("defer 语义不符：got %q code %d", got, code)
	}
}
