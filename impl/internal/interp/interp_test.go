package interp

import (
	"strings"
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// runSrc 解析并执行，返回 stdout 内容与错误。
func runSrc(t *testing.T, src string) (string, error) {
	t.Helper()
	u, diags := xfront.ParseUnit("t.xn", src)
	if len(diags) != 0 {
		t.Fatalf("不应有解析诊断：%v", diags)
	}
	var out strings.Builder
	err := Run(u, &out)
	return out.String(), err
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
