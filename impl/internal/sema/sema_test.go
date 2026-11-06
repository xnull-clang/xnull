package sema

import (
	"strings"
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// run 用例辅助：解析 + 分析，返回语义诊断码集合。
func codes(t *testing.T, src string) []string {
	t.Helper()
	u, diags := xfront.ParseUnit("t.xn", src)
	if len(diags) != 0 {
		t.Fatalf("解析不应有诊断：%v", diags)
	}
	sd := Analyze("t.xn", u)
	out := make([]string, 0, len(sd))
	for _, d := range sd {
		out = append(out, d.Code+"@"+strings.TrimSpace(d.Message))
	}
	return out
}

func expectNone(t *testing.T, src string) {
	t.Helper()
	if got := codes(t, src); len(got) != 0 {
		t.Fatalf("不应有语义诊断：%v", got)
	}
}

func expectCode(t *testing.T, src, code string) {
	t.Helper()
	for _, c := range codes(t, src) {
		if strings.HasPrefix(c, code) {
			return
		}
	}
	t.Fatalf("期望诊断 %s，实际：%v", code, codes(t, src))
}

// ---------- §3.3 四级顺序：第 1 级局部、第 2 级顶层 ----------

func TestLocalShadowsTop(t *testing.T) {
	// 局部变量遮蔽同名顶层字段/函数（§3.3：局部优先）
	expectNone(t, `
Int x = 1

static Int f() { return 9 }

static Int main() {
    Int x = 2
    Int f = 3
    print(str(x) + str(f))
    return 0
}`)
}

func TestTopForwardReference(t *testing.T) {
	// §3.4：函数可前向引用（g 在定义前被 f 调用）
	expectNone(t, `
static Int f(Int n) { return g(n) }

static Int g(Int n) { return n }

static Int main() { return 0 }`)
}

func TestParamsInScope(t *testing.T) {
	expectNone(t, `
static Int add(Int a, Int b) {
    Int s = a + b
    return s
}

static Int main() { return 0 }`)
}

func TestBlockShadowing(t *testing.T) {
	// 内层块重声明外层名 = 遮蔽，合法（§5.2）
	expectNone(t, `
static Int main() {
    Int x = 1
    if true {
        Int x = 2
        print(str(x))
    }
    print(str(x))
    return 0
}`)
}

// ---------- RES-101：未定义名称 ----------

func TestUndefinedName(t *testing.T) {
	expectCode(t, "static Int main() { print(nope)\n    return 0 }", ResUndefined)
	expectCode(t, "static Int main() { Int a = missing + 1\n    return 0 }", ResUndefined)
	// 赋值目标未声明（§6.4）
	expectCode(t, "static Int main() { target = 5\n    return 0 }", ResUndefined)
	// 自增目标未声明
	expectCode(t, "static Int main() { cnt++\n    return 0 }", ResUndefined)
}

func TestUndefinedDiagPosition(t *testing.T) {
	u, _ := xfront.ParseUnit("t.xn", "static Int main() {\n    print(nope)\n    return 0\n}")
	sd := Analyze("t.xn", u)
	if len(sd) != 1 {
		t.Fatalf("应恰好一条诊断：%v", sd)
	}
	if sd[0].Code != ResUndefined || sd[0].Line != 2 || sd[0].Col != 11 {
		t.Fatalf("位置不符：%d:%d %s", sd[0].Line, sd[0].Col, sd[0].Code)
	}
}

// ---------- RES-102：同一作用域重复声明 ----------

func TestRedeclaration(t *testing.T) {
	expectCode(t, `
static Int main() {
    Int x = 1
    Int x = 2
    return 0
}`, ResRedecl)
	// 参数与局部同层
	expectCode(t, `
static Int f(Int a) {
    Int a = 1
    return a
}

static Int main() { return 0 }`, ResRedecl)
}

// ---------- 循环变量与 case 作用域 ----------

func TestLoopAndCaseScopes(t *testing.T) {
	expectNone(t, `
static Int main() {
    for i in 0..<3 {
        print(str(i))
    }
    switch 1 {
        case 1:
            Int v = 1
            print(str(v))
        default:
            print("d")
    }
    return 0
}`)
}

// ---------- defer 体作用域 ----------

func TestDeferScope(t *testing.T) {
	expectNone(t, `
static Int main() {
    Int cleanup = 1
    defer print(str(cleanup))
    return 0
}`)
}

// ---------- 含 import 的文件：本轮跳过未定义检查（占位行为） ----------

func TestImportFileDefers(t *testing.T) {
	// 导入符号表未接入；含 import 的文件不做未定义诊断，避免误报
	expectNone(t, "import xdk.text\n\nstatic Int main() { return 0 }")
}
