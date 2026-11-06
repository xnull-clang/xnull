package interp

import (
	"strings"
	"testing"
)

// ---------- M3.4：§10.3–10.4 硬语义（ERR-01 收敛面） ----------

// §10.4：throw 不展开栈，不执行 defer/errdefer，终止进程（exit 134）。
func TestThrowSkipsDefer(t *testing.T) {
	out, code, err := runSrcCode(t, `
static Int main() {
    defer print("cleanup")
    errdefer print("errcleanup")
    print("before")
    throw "boom"
    return 0
}`)
	if !strings.Contains(out, "before") {
		t.Fatalf("throw 前的输出应保留：%q", out)
	}
	if strings.Contains(out, "cleanup") || strings.Contains(out, "errcleanup") {
		t.Fatalf("throw 不得执行 defer/errdefer（§10.4）：%q", out)
	}
	if code != 134 {
		t.Fatalf("throw fatal 应以 134 终止：got %d", code)
	}
	_ = err
}

// §10.3：错误返回时 defer 与 errdefer 都执行，按注册逆序（单一 LIFO）。
func TestErrReturnRunsDeferAndErrdeferLIFO(t *testing.T) {
	out, _, err := runSrcCode(t, `
static Result<Int, String> work() {
    defer print("d1")
    errdefer print("e1")
    defer print("d2")
    return Err("bad")
}

static Int main() {
    final Result<Int, String> r = work();
    if r.isErr() {
        print(r.error())
    }
    return 0
}`)
	if err != nil {
		t.Fatalf("运行失败：%v（%s）", err, out)
	}
	want := "d2\ne1\nd1\nbad\n"
	if out != want {
		t.Fatalf("LIFO 顺序不符：\n got  %q\n want %q", out, want)
	}
}

// §10.3：正常返回 Ok 只执行 defer，不执行 errdefer。
func TestOkReturnSkipsErrdefer(t *testing.T) {
	out, _, err := runSrcCode(t, `
static Result<Int, String> work() {
    defer print("d1")
    errdefer print("e1")
    return Ok(7)
}

static Int main() {
    final Result<Int, String> r = work();
    if r.isOk() {
        print(r.value())
    }
    return 0
}`)
	if err != nil {
		t.Fatalf("运行失败：%v（%s）", err, out)
	}
	if out != "d1\n7\n" {
		t.Fatalf("Ok 返回不应执行 errdefer：%q", out)
	}
}

// §10.3：try 传播携带 Err 穿过作用域，逐层执行 defer+errdefer。
func TestTryPropagationRunsErrdefer(t *testing.T) {
	out, _, err := runSrcCode(t, `
static Result<Int, String> inner() {
    return Err("inner-fail")
}

static Result<Int, String> outer() {
    errdefer print("outer-errdefer")
    final Int v = try inner();
    return Ok(v)
}

static Int main() {
    final Result<Int, String> r = outer();
    print(r.error())
    return 0
}`)
	if err != nil {
		t.Fatalf("运行失败：%v（%s）", err, out)
	}
	if out != "outer-errdefer\ninner-fail\n" {
		t.Fatalf("try 传播应触发 errdefer：%q", out)
	}
}

// §10.3：defer 在作用域退出（含块退出）时按逆序执行；读取变量当前值。
func TestDeferBlockExitLIFO(t *testing.T) {
	out, _, err := runSrcCode(t, `
static Int main() {
    Int x = 1;
    if true {
        defer print("inner-" + str(x))
        x = 2;
        print("body")
    }
    print("after-" + str(x))
    return 0
}`)
	if err != nil {
		t.Fatalf("运行失败：%v（%s）", err, out)
	}
	if out != "body\ninner-2\nafter-2\n" {
		t.Fatalf("defer 应读取变量当前值并逆序执行：%q", out)
	}
}
