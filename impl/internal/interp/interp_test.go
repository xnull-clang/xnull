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

// ---------- M1 台账补充用例（待办-02 任务 1） ----------

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

// ---------- ENTRY-01（M1）：入口签名与缺失/重复入口 ----------

// runSrcCodeArgs 解析并执行，带程序参数。
func runSrcCodeArgs(t *testing.T, src string, args []string) (string, int, error) {
	t.Helper()
	u, diags := xfront.ParseUnit("t.x", src)
	if len(diags) != 0 {
		t.Fatalf("不应有解析诊断：%v", diags)
	}
	var out strings.Builder
	code, err := Run(u, &out, args)
	return out.String(), code, err
}

// §11.2：void 与 Int 两种 main 签名均接收 String[] 参数并可运行。
func TestEntryTwoSignatures(t *testing.T) {
	cases := []struct {
		name string
		src  string
		want string
		code int
	}{
		{"void+args", "static void main(final String[] args) {\n    print(\"void\")\n}", "void\n", 0},
		{"Int+args", "static Int main(final String[] args) {\n    print(\"int\")\n    return 3\n}", "int\n", 3},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			out, code, err := runSrcCodeArgs(t, c.src, []string{"x"})
			if err != nil {
				t.Fatalf("运行失败：%v", err)
			}
			if out != c.want || code != c.code {
				t.Fatalf("out=%q code=%d，期望 out=%q code=%d", out, code, c.want, c.code)
			}
		})
	}
}

// §11.4：缺失入口是编译错误。
func TestEntryMissingRejected(t *testing.T) {
	_, code, err := runSrcCode(t, "static Int helper() { return 1 }")
	if err == nil {
		t.Fatal("缺失入口应报错")
	}
	if code != 1 {
		t.Fatalf("缺失入口退出码 %d，期望 1", code)
	}
	if !strings.Contains(err.Error(), "入口") {
		t.Fatalf("诊断应点名入口：%v", err)
	}
}

// §11.4：重复入口是编译错误。
func TestEntryDuplicateRejected(t *testing.T) {
	_, code, err := runSrcCode(t, "static Int main() { return 0 }\nstatic Int main() { return 1 }")
	if err == nil {
		t.Fatal("重复入口应报错")
	}
	if code != 1 {
		t.Fatalf("重复入口退出码 %d，期望 1", code)
	}
	if !strings.Contains(err.Error(), "重复入口") {
		t.Fatalf("诊断应点名重复入口：%v", err)
	}
}

// §11.2：非法入口签名（返回类型非 void/Int、额外参数、非 static）被拒绝。
func TestEntryInvalidSignatureRejected(t *testing.T) {
	cases := []struct{ name, src string }{
		{"返回 String", "static String main() { return \"\" }"},
		{"额外参数", "static Int main(Int n) { return n }"},
		{"非 static", "Int main() { return 0 }"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			_, _, err := runSrcCode(t, c.src)
			if err == nil {
				t.Fatal("非法入口签名应报错")
			}
			if !strings.Contains(err.Error(), "签名") {
				t.Fatalf("诊断应点名入口签名：%v", err)
			}
		})
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

// TUPLE-01：元组 == / != 逐元素（§2.11、§2.8）。
func TestTupleEquality(t *testing.T) {
	out, err := runSrc(t, `
static Int main() {
    (Int, String) a = (1, "one")
    (Int, String) b = (1, "one")
    (Int, String) c = (1, "two")
    if a == b { print("eq") }
    if a != c { print("ne") }
    if !(a == c) { print("not") }
    (Int, (Int, Bool)) n1 = (1, (2, true))
    (Int, (Int, Bool)) n2 = (1, (2, true))
    (Int, (Int, Bool)) n3 = (1, (2, false))
    if n1 == n2 { print("nested-eq") }
    if n1 != n3 { print("nested-ne") }
    return 0
}`)
	want := "eq\nne\nnot\nnested-eq\nnested-ne\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}

// TUPLE-01：元组 === / !== 逐元素同一性（§2.11、§2.8）。
func TestTupleIdentity(t *testing.T) {
	out, err := runSrc(t, `
static Int main() {
    (Int, String) a = (1, "one")
    (Int, String) b = (1, "one")
    if a === b { print("id") }
    if a !== (1, "two") { print("nid") }
    (Int, (Int, Bool)) n1 = (1, (2, true))
    (Int, (Int, Bool)) n2 = (1, (2, true))
    if n1 === n2 { print("nested-id") }
    return 0
}`)
	want := "id\nnid\nnested-id\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}

// TUPLE-01：元组插值格式 `(a, b)`，元素递归格式化（§1.4.4、§2.11）。
func TestTupleInterpolation(t *testing.T) {
	out, err := runSrc(t, `
static Int main() {
    (Int, String) p = (1, "one")
    print($"p={p}")
    ((Int, Int), Bool) n = ((1, 2), true)
    print($"n={n}")
    return 0
}`)
	want := "p=(1, one)\nn=((1, 2), true)\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}

// TUPLE-01：越界选择器是 fatal（§2.11：越界是编译错误，解释器兜底）。
func TestTupleMemberOutOfRange(t *testing.T) {
	_, code, err := runSrcCode(t, `
static Int main() {
    (Int, String) p = (1, "one")
    print(p.2)
    return 0
}`)
	if err == nil || code != 134 {
		t.Fatalf("越界选择器应为 fatal（134）：code=%d err=%v", code, err)
	}
}

// GEN-01（解释器半边）：泛型 accept 用例必须在 interp 路径产出台账期望输出。
// 用例源与 c1-rd3 的 gen01_red_test.go 保持一致（不依赖 sema；sema 缺口另域负责）。
func TestGEN01InterpAccept(t *testing.T) {
	cases := []struct {
		id   string
		src  string
		want string
	}{
		{"G1a", `
static T identity<T>(T value) { return value }
static Int main() { print(identity<Int>(7)); return 0 }`, "7\n"},
		{"G2a", `
static T identity<T>(T value) { return value }
static Int main() { print(identity(7)); return 0 }`, "7\n"},
		{"G2b", `
static T head<T>(List<T> xs) { return xs.get(0) }
static Int main() {
    List<Int> xs = [4, 5]
    print(head(xs))
    return 0
}`, "4\n"},
		{"G2c", `
static T pick<T>(T a, T b) { return b }
static Int main() { print(pick(1, 2)); return 0 }`, "2\n"},
		{"G5a", `
static Int pick(Int v) { return v + 1 }
static T pick<T>(T v) { return v }
static Int main() { print(pick(3)); return 0 }`, "4\n"},
		{"G6a", `
static T identity<T>(T value) { return value }
static Int main() {
    print(identity<Int>(1))
    print(identity<String>("s"))
    return 0
}`, "1\ns\n"},
		{"G6b", `
static Int count<T>(List<T> xs) { return xs.length() }
static Int main() {
    List<Int> a = [1, 2, 3]
    List<String> b = ["x"]
    print(count(a))
    print(count(b))
    return 0
}`, "3\n1\n"},
		{"G8", `
static T unwrapOr<T>(Result<T, String> r, T d) { return r.unwrapOr(d) }
static Int main() {
    Result<Int, String> r = Ok(5)
    print(unwrapOr(r, 0))
    return 0
}`, "5\n"},
		{"G11", `
static T keep<T>(T v) {
    T local = v
    List<T> box = [v]
    return local
}
static Int main() { print(keep(9)); return 0 }`, "9\n"},
		{"G14", `
static Bool isInt<T>(T v) { return v is Int }
static Int main() { print(isInt<Int>(1)); return 0 }`, "true\n"},
		{"G18", `
static Int plain(Int v) { return v }
static T gen<T>(T v) { return v }
static Int main() { print(plain(2)); print(gen(3)); return 0 }`, "2\n3\n"},
	}
	for _, c := range cases {
		c := c
		t.Run(c.id, func(t *testing.T) {
			out, err := runSrc(t, c.src)
			if err != nil || out != c.want {
				t.Fatalf("out=%q want=%q err=%v", out, c.want, err)
			}
		})
	}
}

// GEN-01（解释器半边）：重载选择必须尊重显式类型实参与非泛型优先级（§8.2）。
// 红证据：当前 interp 只按参数个数取首个候选，泛型/普通同名会选错。
func TestGEN01InterpOverloadSelection(t *testing.T) {
	t.Run("ExplicitTypeArgPicksGeneric", func(t *testing.T) {
		out, err := runSrc(t, `
static Int pick(Int v) { return v + 1 }
static T pick<T>(T v) { return v }
static Int main() { print(pick<Int>(10)); return 0 }`)
		if err != nil || out != "10\n" {
			t.Fatalf("out=%q want=%q err=%v", out, "10\n", err)
		}
	})
	t.Run("NonGenericPreferred", func(t *testing.T) {
		out, err := runSrc(t, `
static T pick<T>(T v) { return v }
static Int pick(Int v) { return v + 1 }
static Int main() { print(pick(3)); return 0 }`)
		if err != nil || out != "4\n" {
			t.Fatalf("out=%q want=%q err=%v", out, "4\n", err)
		}
	})
	t.Run("TypeArgCountMismatchRejected", func(t *testing.T) {
		_, code, err := runSrcCode(t, `
static T identity<T>(T v) { return v }
static Int main() { print(identity<Int, Int>(7)); return 0 }`)
		if err == nil || code != 1 {
			t.Fatalf("类型实参数量不符应显式失败：code=%d err=%v", code, err)
		}
	})
}

// M6-B0-05：容器成员规范边界（§9.4 List / §9.5 Map）。
func TestContainerMemberSpecEdges(t *testing.T) {
	t.Run("MapGetMissingReturnsNull", func(t *testing.T) {
		out, err := runSrc(t, `
static Int main() {
    Map<String, Int> m = ["a": 1]
    Int? v = m.get("z")
    print(v)
    return 0
}`)
		if err != nil || out != "null\n" {
			t.Fatalf("Map.get 缺键应返回 null：out=%q err=%v", out, err)
		}
	})
	t.Run("ListRemoveReturnsElement", func(t *testing.T) {
		out, err := runSrc(t, `
static Int main() {
    List<Int> l = [1, 2]
    Int x = l.remove(0)
    print(x)
    print(l.length())
    print(l.get(0))
    return 0
}`)
		want := "1\n1\n2\n"
		if err != nil || out != want {
			t.Fatalf("List.remove 应返回被删元素：out=%q want=%q err=%v", out, want, err)
		}
	})
	t.Run("ListInsertOutOfRangePanics", func(t *testing.T) {
		_, code, err := runSrcCode(t, `
static Int main() {
    List<Int> l = [1]
    l.insert(5, 9)
    print(l.length())
    return 0
}`)
		if err == nil || code != 134 {
			t.Fatalf("List.insert 越界应 panic（134）：code=%d err=%v", code, err)
		}
	})
}

// ERR-01 B1：闭包内 try 失败必须从闭包返回 Err，不穿透外层函数（S1 §10.2）。
func TestClosureTryReturnsFromClosure(t *testing.T) {
	t.Run("NoPenetration", func(t *testing.T) {
		out, err := runSrc(t, `
static Result<Int, String> g(Int x) {
    if x < 0 { return Err("bad") }
    return Ok(x)
}
static Result<Int, String> f() {
    Result<Int, String>(Int) h = (Int x) -> {
        Int v = try g(x)
        return Ok(v)
    }
    Result<Int, String> r = h(-1)
    if r.isErr() { print("closure-err:" + r.error()) }
    print("after-call")
    return Ok(1)
}
static Int main() {
    Result<Int, String> r = f()
    if r.isOk() { print("outer-ok") } else { print("outer-err:" + r.error()) }
    return 0
}`)
		want := "closure-err:bad\nafter-call\nouter-ok\n"
		if err != nil || out != want {
			t.Fatalf("out=%q want=%q err=%v", out, want, err)
		}
	})
	t.Run("OuterErrdeferNotTriggered", func(t *testing.T) {
		out, err := runSrc(t, `
static Result<Int, String> g() { return Err("bad") }
static Result<Int, String> f() {
    errdefer print("outer-e")
    defer print("outer-d")
    Result<Int, String>(Int) h = (Int x) -> {
        errdefer print("closure-e")
        defer print("closure-d")
        Int v = try g()
        return Ok(v)
    }
    Result<Int, String> r = h(0)
    if r.isErr() { print("handled") }
    print("after-call")
    return Ok(1)
}
static Int main() {
    Result<Int, String> r = f()
    if r.isOk() { print("outer-ok") } else { print("outer-err:" + r.error()) }
    return 0
}`)
		want := "closure-d\nclosure-e\nhandled\nafter-call\nouter-d\nouter-ok\n" // LIFO；f 的 defer 在其返回时执行，早于 main 打印 outer-ok
		if err != nil || out != want {
			t.Fatalf("out=%q want=%q err=%v", out, want, err)
		}
	})
}

// §4.3：顶层字段先置零值，初始化式按声明顺序求值；前向引用读零值。
func TestTopFieldForwardReference(t *testing.T) {
	t.Run("Direct", func(t *testing.T) {
		out, err := runSrc(t, `
Int a = b + 1
Int b = 2
static Int main() {
    print(a)
    print(b)
    return 0
}`)
		want := "1\n2\n"
		if err != nil || out != want {
			t.Fatalf("out=%q want=%q err=%v", out, want, err)
		}
	})
	t.Run("ChainReadsZeroNotEventual", func(t *testing.T) {
		out, err := runSrc(t, `
Int a = b + 1
Int b = c + 1
Int c = 2
static Int main() {
    print(a)
    print(b)
    print(c)
    return 0
}`)
		want := "1\n1\n2\n"
		if err != nil || out != want {
			t.Fatalf("out=%q want=%q err=%v", out, want, err)
		}
	})
	t.Run("ForwardFunction", func(t *testing.T) {
		out, err := runSrc(t, `
Int v = twice(3)
static Int twice(Int x) { return x * 2 }
static Int main() {
    print(v)
    return 0
}`)
		if err != nil || out != "6\n" {
			t.Fatalf("out=%q want=%q err=%v", out, "6\n", err)
		}
	})
}

// NEG（interp 项）：Result 成员误用必须是运行期 fatal（§10.1）。
// 对应 ERR-01 回执「interp 负向单测未入库」的缺口。
func TestResultMemberMisusePanics(t *testing.T) {
	t.Run("ErrValue", func(t *testing.T) {
		_, code, err := runSrcCode(t, `
static Int main() {
    Result<Int, String> r = Err("bad")
    print(r.value())
    return 0
}`)
		if err == nil || code != 134 {
			t.Fatalf("Err.value() 应 fatal（134）：code=%d err=%v", code, err)
		}
	})
	t.Run("OkError", func(t *testing.T) {
		_, code, err := runSrcCode(t, `
static Int main() {
    Result<Int, String> r = Ok(1)
    print(r.error())
    return 0
}`)
		if err == nil || code != 134 {
			t.Fatalf("Ok.error() 应 fatal（134）：code=%d err=%v", code, err)
		}
	})
}
