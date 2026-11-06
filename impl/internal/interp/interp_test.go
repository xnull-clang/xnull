package interp

import (
	"strings"
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// runSrc 解析并执行，返回 stdout 内容与错误（退出码忽略）。
func runSrc(t *testing.T, src string) (string, error) {
	out, _, err := runSrcCode(t, src)
	return out, err
}

// runSrcCode 解析并执行，返回 stdout、退出码与错误。
func runSrcCode(t *testing.T, src string) (string, int, error) {
	t.Helper()
	u, diags := xfront.ParseUnit("t.x", src)
	if len(diags) != 0 {
		t.Fatalf("不应有解析诊断：%v", diags)
	}
	var out strings.Builder
	code, err := Run(u, &out, nil)
	return out.String(), code, err
}

func TestHello(t *testing.T) {
	out, err := runSrc(t, "static Int main() {\n    print(\"hello, XNull\")\n    return 0\n}")
	if err != nil || out != "hello, XNull\n" {
		t.Fatalf("out=%q err=%v", out, err)
	}
}

func TestArithmeticAndControl(t *testing.T) {
	src := `
static Int main() {
    Int total = 0
    for i in 0..<5 {
        total += i
    }
    print(total)          // 10
    print(7 / 2)          // 3（整数除法）
    print(-7 % 3)         // -1
    print(1 << 10)        // 1024
    print(2 > 1 && 1 < 2) // true
    print(null ?? "d")    // d
    Int x = 5
    print(x > 3 ? "big" : "small")
    switch x {
        case 1: print("one")
        case 5: print("five")
        default: print("other")
    }
    return 0
}`
	out, err := runSrc(t, src)
	want := "10\n3\n-1\n1024\ntrue\nd\nbig\nfive\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}

func TestResultTry(t *testing.T) {
	src := `
static Result<Int, String> parse(Int n) {
    if n < 0 {
        return Err("negative: " + str(n))
    }
    return Ok(n * 2)
}

static Result<Int, String> run(Int n) {
    Int v = try parse(n)
    print("got " + str(v))
    return Ok(v)
}

static Int main() {
    Result<Int, String> a = run(21)
    print(a.isOk())
    Result<Int, String> b = run(-1)
    print(b.isErr())
    print(b.error())
    print(b.unwrapOr(0))
    return 0
}`
	out, err := runSrc(t, src)
	// run(-1)：try 传播到达函数边界以 Err 返回（§10.2），"got" 行不执行。
	want := "got 42\ntrue\ntrue\nnegative: -1\n0\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}

func TestDeferLIFO(t *testing.T) {
	src := `
static Int work() {
    print("A")
    defer print("cleanup 1")
    defer print("cleanup 2")
    if true {
        print("B")
        defer print("inner cleanup")
        print("C")
    }
    print("D")
    return 0
}

static Int main() {
    work()
    return 0
}`
	out, err := runSrc(t, src)
	want := "A\nB\nC\ninner cleanup\nD\ncleanup 2\ncleanup 1\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}

func TestErrdeferOnlyOnErrorPath(t *testing.T) {
	src := `
static Result<Int, String> maybe(Int n) {
    if n < 0 {
        return Err("neg")
    }
    return Ok(n)
}

static Result<Int, String> run(Int n) {
    defer print("defer: exits")
    errdefer print("errdefer: error")
    Int v = try maybe(n)
    return Ok(v)
}

static Int main() {
    Result<Int, String> a = run(5)
    Result<Int, String> b = run(-7)
    print(b.isErr())
    return 0
}`
	out, err := runSrc(t, src)
	// 第二轮：errdefer 注册在后 → LIFO 先执行（§10.3）。
	want := "defer: exits\nerrdefer: error\ndefer: exits\ntrue\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}

func TestFatalNoDefers(t *testing.T) {
	// §10.4：throw 不执行 defer。
	src := `
static Int main() {
    defer print("never")
    throw "boom"
}`
	_, err := runSrc(t, src)
	if err == nil || !strings.Contains(err.Error(), "boom") {
		t.Fatalf("throw 应以 fatal 终止：%v", err)
	}
}

func TestDeterminismByteIdentical(t *testing.T) {
	// 确定性（DET-01）：多次运行输出逐字节一致。
	src := `
static Result<Int, String> step(Int n) {
    if n % 2 == 0 {
        return Ok(n + 1)
    }
    return Err("odd " + str(n))
}

static Int main() {
    for i in 0...10 {
        Result<Int, String> r = step(i)
        print(str(i) + " -> " + str(r.isOk()) + " " + (r.isOk() ? str(r.value()) : r.error()))
    }
    return 0
}`
	first, err := runSrc(t, src)
	if err != nil {
		t.Fatalf("首次运行失败：%v", err)
	}
	for round := 2; round <= 5; round++ {
		again, _ := runSrc(t, src)
		if again != first {
			t.Fatalf("第 %d 轮输出与首轮不一致：\n--- 首轮 ---\n%s\n--- 本轮 ---\n%s", round, first, again)
		}
	}
}

func TestMissingMain(t *testing.T) {
	_, err := runSrc(t, "static Int helper() { return 1 }")
	if err == nil || !strings.Contains(err.Error(), "main") {
		t.Fatalf("缺 main 应报错：%v", err)
	}
}

// ---------- M1 台账补充用例 ----------

// EXPR-01：求值顺序——&&/|| 短路、?? 惰性、try 传播顺序。
func TestShortCircuitEvalOrder(t *testing.T) {
	src := `
static Int mark(String s) {
    print(s)
    return 1
}

static Int main() {
    Bool a = false && mark("no-a")   // 右侧不求值
    Bool b = true || mark("no-b")    // 右侧不求值
    String c = "x" ?? mark("no-c")   // 左侧非 null，右侧不求值
    Bool d = true && mark("yes-d") > 0
    print(str(a) + str(b) + c + str(d))
    return 0
}`
	out, err := runSrc(t, src)
	want := "yes-d\nfalsetruextrue\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}

// EXPR-01：try 传播顺序——内层 defer 先于外层错误接收点执行。
func TestTryPropagationOrder(t *testing.T) {
	src := `
static Result<Int, String> inner() {
    defer print("inner defer")
    return Err("boom")
}

static Result<Int, String> outer() {
    defer print("outer defer")
    Int v = try inner()
    return Ok(v)
}

static Int main() {
    Result<Int, String> r = outer()
    print("caught: " + r.error())
    return 0
}`
	out, err := runSrc(t, src)
	// 顺序：inner 的 defer（传播前执行）→ outer 的 defer（错误路径到达函数边界）→ main 接收
	want := "inner defer\nouter defer\ncaught: boom\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}

// CTRL-01：break/continue 标签作用域与 switch break。
func TestLabeledBreakContinue(t *testing.T) {
	src := `
static Int main() {
    Int hits = 0
    outer: for i in 0..<3 {
        for j in 0..<3 {
            if j == 1 {
                continue outer
            }
            if i == 2 {
                break outer
            }
            hits += 1
        }
    }
    print(hits)   // i=0,j=0 与 i=1,j=0 各自增一次；i=2,j=0 在自增前 break → 2
    switch 1 {
        case 1: print("case1"); break
        default: print("no")
    }
    return 0
}`
	out, err := runSrc(t, src)
	want := "2\ncase1\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}

// ENTRY-01：退出码映射（S4 §7.2）与顶层字段初始化顺序（§4.3）。
func TestExitCodeMapping(t *testing.T) {
	// Int main 返回值原样作为退出码
	_, code, err := runSrcCode(t, "static Int main() { return 7 }")
	if err != nil || code != 7 {
		t.Fatalf("code=%d err=%v", code, err)
	}
	// void main → 0
	_, code, err = runSrcCode(t, "static void main() { print(\"x\") }")
	if err != nil || code != 0 {
		t.Fatalf("code=%d err=%v", code, err)
	}
	// 运行期 fatal → 134
	_, code, err = runSrcCode(t, "static Int main() { throw \"boom\" }")
	if err == nil || code != 134 {
		t.Fatalf("fatal 应得 134：code=%d err=%v", code, err)
	}
	// 初始化期 fatal → 134
	_, code, err = runSrcCode(t, "static Int bad() { throw \"init\" }\nInt g = bad()\nstatic Int main() { return 0 }")
	if err == nil || code != 134 {
		t.Fatalf("初始化 fatal 应得 134：code=%d err=%v", code, err)
	}
}

// ENTRY-01：顶层字段按声明顺序初始化（§4.3）。
func TestTopFieldInitOrder(t *testing.T) {
	src := `
Int a = 1
Int b = a + 1
Int c = b + 1

static Int main() {
    print(str(a) + str(b) + str(c))
    return 0
}`
	out, err := runSrc(t, src)
	if err != nil || out != "123\n" {
		t.Fatalf("out=%q err=%v", out, err)
	}
}

// TUPLE-01（语法可判定部分）：单元素/零元元组被拒绝；`(e)` 是括号表达式。
func TestTupleSyntaxRejections(t *testing.T) {
	// 零元元组拒绝
	if _, diags := xfront.ParseUnit("t.x", "static Int main() { Tuple t = ()\n    return 0 }"); len(diags) == 0 {
		t.Fatalf("() 应被拒绝")
	}
	// 单元素元组形态拒绝（带尾逗号）
	if _, diags := xfront.ParseUnit("t.x", "static Int main() { Int x = (1,)\n    return 0 }"); len(diags) == 0 {
		t.Fatalf("(1,) 应被拒绝")
	}
	// (e) 是括号表达式不是元组
	u, diags := xfront.ParseUnit("t.x", "static Int main() { print((5))\n    return 0 }")
	if len(diags) != 0 {
		t.Fatalf("(5) 应为括号表达式：%v", diags)
	}
	var out strings.Builder
	if _, err := Run(u, &out, nil); err != nil || out.String() != "5\n" {
		t.Fatalf("out=%q err=%v", out.String(), err)
	}
}
