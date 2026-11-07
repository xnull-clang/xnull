// Package tests 承载《XNull 一致性用例台账》NEG-01 锚点的负例检查表。
//
// 依据：
//   - XNull 解决方案 第 1 部分 §0.6（明确不支持的语法，30 类）
//   - 第 1 部分 §1.3（保留名、预定义类型名、`Array` 内部名）
//   - 第 1 部分 §3.2（禁止通配符导入与包别名）
//   - 第 1 部分 §10.4（defer / errdefer 清理体禁止控制转移、try、throw）
//   - 第 1 部分 §2.11（单元素 / 零元组）
//   - 台账 NEG-01：每类禁止构造都有对应诊断；不支持项按 0.6 拒绝；不崩溃、不静默接受
//
// 判定口径（每条用例一致，不看具体文案）：
//  1. 拒绝：解析期或语义期至少产生 1 条诊断；
//  2. 诊断可机读：码形如 XX-000，且 file:line:col 位置有效；
//  3. 不崩溃：用例执行期间不得 panic；
//  4. 不静默接受：不得「零诊断且无错误」。
//
// 本文件只读调用 xfront 与 sema，不改生产代码、不写仓库外状态。
package tests

import (
	"fmt"
	"regexp"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/diag"
	"xnull.dev/xnull/internal/sema"
	"xnull.dev/xnull/internal/xfront"
)

// codePattern 是诊断码的法定形态（diag.Diagnostic.Code）。
var codePattern = regexp.MustCompile(`^[A-Z]{2,4}-[0-9]{3}$`)

// negCase 是检查表中的一条负例。
type negCase struct {
	id     string // 台账内用例号
	clause string // 规范条款
	src    string // 源程序
	want   string // 必须出现的诊断码；空串表示「任一合法诊断码」
}

// analyze 在单文件范围内走解析 + 语义，捕获 panic。
func analyze(src string) (diags []diag.Diagnostic, panicked any) {
	defer func() {
		if r := recover(); r != nil {
			panicked = r
		}
	}()
	u, pd := xfront.ParseUnit("neg.x", src)
	diags = append(diags, pd...)
	if len(pd) == 0 {
		diags = append(diags, sema.Analyze("neg.x", u)...)
	}
	return diags, nil
}

// TestDiagMatrixS1 逐条执行检查表。子测试名含用例号，便于按条计数。
func TestDiagMatrixS1(t *testing.T) {
	for _, c := range negCases {
		c := c
		t.Run(c.id, func(t *testing.T) {
			diags, panicked := analyze(c.src)
			if panicked != nil {
				t.Fatalf("%s 编译器崩溃（panic）：%v", c.clause, panicked)
			}
			if len(diags) == 0 {
				t.Fatalf("%s 被静默接受：0 条诊断（源码 %d 字节）", c.clause, len(c.src))
			}
			// 位置与码必须可机读。
			ok := false
			var dump strings.Builder
			for _, d := range diags {
				fmt.Fprintf(&dump, "  %s\n", d.String())
				if !codePattern.MatchString(d.Code) {
					t.Errorf("%s 诊断码非法：%q", c.clause, d.Code)
					continue
				}
				if d.Line < 1 || d.Col < 1 {
					t.Errorf("%s 诊断缺位置：%s（line=%d col=%d）", c.clause, d.Code, d.Line, d.Col)
					continue
				}
				if c.want == "" || d.Code == c.want {
					ok = true
				}
			}
			if !ok {
				t.Fatalf("%s 期望诊断码 %q，实际：\n%s", c.clause, c.want, dump.String())
			}
		})
	}
}

// matrixGroups 是《M1 整改台账》§三 要求的 32 项分组（S1 §0.6，行 82–113）。
// 一项可对应多条用例；用例号全部来自 negCases。
var matrixGroups = []struct {
	no    int
	name  string
	cases []string
}{
	{1, "调用形态（命名/默认/可变/展开实参）", []string{"neg-0.6-01", "neg-0.6-02", "neg-0.6-03", "neg-0.6-04"}},
	{2, "C 风格 for (init; cond; step)", []string{"neg-0.6-05"}},
	{3, "catch / finally、跨帧异常", []string{"neg-0.6-06", "neg-0.6-07"}},
	{4, "运算符重载、用户定义隐式转换", []string{"neg-0.6-08"}},
	{5, "地址符/指针/弱引用修饰符/内存策略注解", []string{"neg-0.6-09", "neg-0.6-10", "neg-0.6-11", "neg-0.6-12"}},
	{6, "自定义访问器属性", []string{"neg-0.6-13"}},
	{7, "用户定义索引器", []string{"neg-0.6-14"}},
	{8, "事件", nil},
	{9, "if / switch 表达式、块表达式", []string{"neg-0.6-15", "neg-0.6-16"}},
	{10, "独立 {} 语句块", []string{"neg-0.6-17"}},
	{11, "match / 模式匹配", []string{"neg-0.6-18"}},
	{12, "元组解构/标签/方法/单元素/零元组", []string{"neg-0.6-19", "neg-2.11-01", "neg-2.11-02"}},
	{13, "??=", []string{"neg-0.6-20"}},
	{14, "?.() / ?.[]", []string{"neg-0.6-21"}},
	{15, "函数类型箭头 (P) -> R", []string{"neg-0.6-22"}},
	{16, "async / await / 生成器 / yield", []string{"neg-0.6-23", "neg-0.6-24", "neg-0.6-25"}},
	{17, "unsafe 块 / 裸指针 / 内联汇编 / 宏", []string{"neg-0.6-26", "neg-0.6-27"}},
	{18, "条件编译、宏展开、运行时反射", nil},
	{19, "包重导出、显式 export 列表", []string{"neg-0.6-28"}},
	{20, "嵌套类型、局部类型", []string{"neg-0.6-29"}},
	{21, "静态初始化块、实例初始化块", []string{"neg-0.6-30"}},
	{22, "多继承、类型类 / trait、隐式实现", []string{"neg-0.6-31"}},
	{23, "类方法覆写、类层级动态派发", []string{"neg-0.6-32"}},
	{24, "抽象方法、类继承动态合同", []string{"neg-0.6-33"}},
	{25, "结构体/枚举/单例实现协议", []string{"neg-0.6-34"}},
	{26, "结构体实例引用字段、引用回退", []string{"neg-0.6-35"}},
	{27, "协议字段、协议方法体、协议默认实现", []string{"neg-0.6-36", "neg-0.6-37"}},
	{28, "泛型协议、关联类型、协议泛型方法", []string{"neg-0.6-38"}},
	{29, "泛型约束、where 子句、默认类型实参", []string{"neg-0.6-39"}},
	{30, "类型别名 / newtype", []string{"neg-0.6-41"}},
	{31, "包级私有 / internal 可见性", []string{"neg-0.6-40"}},
	{32, "隐式数值提升、Bool 与整数互转", []string{"neg-0.6-42", "neg-0.6-43"}},
}

// TestDiagMatrixDump 输出 diag-matrix.tsv 的行（tab 分隔），供证据采集：
//
//	go test ./Tests/ -run TestDiagMatrixDump -v | grep 'MATRIX' | cut -f2-
func TestDiagMatrixDump(t *testing.T) {
	t.Logf("MATRIX\titem\tgroup\tcases\tcode\tline\tcol\tstatus")
	for _, g := range matrixGroups {
		if len(g.cases) == 0 {
			t.Logf("MATRIX\t%d\t%s\t%s\t-\t-\t-\tN-A(规范无语法载体)", g.no, g.name, "-")
			continue
		}
		code, line, col, status := "-", 0, 0, "PASS"
		for i, id := range g.cases {
			c := caseByID(t, id)
			diags, _ := analyze(c.src)
			if len(diags) == 0 {
				status = "FAIL"
				if i == 0 {
					code = "NO-DIAG"
				}
				continue
			}
			if status == "PASS" && i == 0 {
				code, line, col = diags[0].Code, diags[0].Line, diags[0].Col
			}
		}
		t.Logf("MATRIX\t%d\t%s\t%s\t%s\t%d\t%d\t%s", g.no, g.name, strings.Join(g.cases, ","), code, line, col, status)
	}
}

func caseByID(t *testing.T, id string) negCase {
	t.Helper()
	for _, c := range negCases {
		if c.id == id {
			return c
		}
	}
	t.Fatalf("矩阵引用未知用例：%s", id)
	return negCase{}
}

// TestDiagMatrixS1Alternatives 验证 §0.6「替代方案」可用（N5：反向探针）。
// 每条必须是合法程序（0 诊断）：支持了被禁构造却忘了替代方案，同样是漏洞。
func TestDiagMatrixS1Alternatives(t *testing.T) {
	cases := []struct {
		id   string
		name string
		src  string
	}{
		{"alt-01", "while 替代 C 风格 for", `static Int main() {
    Int i = 0
    while (i < 3) {
        print(i)
        i += 1
    }
    return 0
}
`},
		{"alt-02", "命名方法替代运算符重载", `class A {
    Int v = 1

    A plus(A o) {
        A r = new A()
        r.v = self.v + o.v
        return r
    }
}

static Int main() {
    A a = new A()
    A b = new A()
    return a.plus(b).v
}
`},
		{"alt-03", "公有字段直接访问替代访问器", `class A {
    Int v = 1
}

static Int main() {
    A a = new A()
    a.v = 5
    return a.v
}
`},
		{"alt-04", "get/set 替代用户定义索引器", `static Int main() {
    List<Int> xs = [1, 2, 3]
    xs.set(0, 9)
    return xs.get(0)
}
`},
		{"alt-05", "if 语句替代 if 表达式", `static Int main() {
    Int x = 0
    if true {
        x = 1
    } else {
        x = 2
    }
    return x
}
`},
		{"alt-06", "协议 + 类替代类型类 / trait", `protocol P {
    Int f()
}

class A implements P {
    public Int f() {
        return 1
    }
}

static Int main() {
    return 0
}
`},
		{"alt-07", "class 包装替代结构体引用字段", `class S {
    String s = "x"
}

static Int main() {
    S v = new S()
    return 0
}
`},
		{"alt-08", "if 判断替代 ??=", `static Int main() {
    String a = "x"
    String? s = null
    if s == null {
        s = a
    }
    return 0
}
`},
		{"alt-09", "if 判断替代 ?.()", `static Int foo() {
    return 1
}

static Int main() {
    Int x = 0
    if x == 0 {
        foo()
    }
    return 0
}
`},
	}
	for _, c := range cases {
		c := c
		t.Run(c.id, func(t *testing.T) {
			diags, panicked := analyze(c.src)
			if panicked != nil {
				t.Fatalf("%s 编译器崩溃（panic）：%v", c.name, panicked)
			}
			if len(diags) != 0 {
				var dump strings.Builder
				for _, d := range diags {
					fmt.Fprintf(&dump, "  %s\n", d.String())
				}
				t.Fatalf("%s 的替代方案不可用（%d 条诊断）：\n%s", c.name, len(diags), dump.String())
			}
		})
	}
}

// negCases 是检查表本体：条款 → 用例 → 期望码。
// want 为空表示规范未指定码，只要求「有码 + 有位置 + 被拒绝」。
var negCases = []negCase{
	// ---------- §0.6 命名实参 / 默认 / 可变 / 展开实参 ----------
	{"neg-0.6-01", "§0.6 命名实参", `static Int f(Int a) {
    return a
}

static Int main() {
    return f(a: 1)
}
`, ""},
	{"neg-0.6-02", "§0.6 默认参数", `static Int f(Int a = 1) {
    return a
}

static Int main() {
    return f()
}
`, ""},
	{"neg-0.6-03", "§0.6 可变参数", `static Int f(Int... xs) {
    return 0
}

static Int main() {
    return f(1)
}
`, ""},
	{"neg-0.6-04", "§0.6 展开实参", `static Int f(Int a) {
    return a
}

static Int main() {
    Int[] xs = [1]
    return f(xs...)
}
`, ""},

	// ---------- §0.6 控制流 ----------
	{"neg-0.6-05", "§0.6 C 风格 for", `static Int main() {
    for (Int i = 0; i < 3; i += 1) {
        print(i)
    }
    return 0
}
`, ""},
	{"neg-0.6-06", "§0.6 catch", `static Int main() {
    try {
        print(1)
    } catch (e) {
        print(2)
    }
    return 0
}
`, ""},
	{"neg-0.6-07", "§0.6 finally", `static Int main() {
    try {
        print(1)
    } finally {
        print(3)
    }
    return 0
}
`, ""},

	// ---------- §0.6 类型行为 ----------
	{"neg-0.6-08", "§0.6 运算符重载", `class A {
    static A operator +(A o) {
        return o
    }
}

static Int main() {
    return 0
}
`, ""},
	{"neg-0.6-09", "§0.6 指针类型 T*", `static Int main() {
    Int a = 1
    Int* p = null
    return a
}
`, ""},
	{"neg-0.6-10", "§0.6 地址符 &", `static Int main() {
    Int a = 1
    Object p = &a
    return a
}
`, ""},
	{"neg-0.6-11", "§0.6 @arc 策略注解", `@arc
class A {
    Int v = 1
}

static Int main() {
    return 0
}
`, ""},
	{"neg-0.6-12", "§0.6 @gc 策略注解", `@gc
class A {
    Int v = 1
}

static Int main() {
    return 0
}
`, ""},
	{"neg-0.6-13", "§0.6 自定义访问器", `class A {
    Int v {
        get {
            return 1
        }
    }
}

static Int main() {
    return 0
}
`, ""},
	{"neg-0.6-14", "§0.6 用户定义索引器", `class A {
    public Int at[Int i] {
        return 0
    }
}

static Int main() {
    return 0
}
`, ""},

	// ---------- §0.6 表达式与块 ----------
	{"neg-0.6-15", "§0.6 if 表达式", `static Int main() {
    Int x = if true {
        1
    } else {
        2
    }
    return x
}
`, ""},
	{"neg-0.6-16", "§0.6 块表达式", `static Int main() {
    Int x = {
        1
    }
    return x
}
`, ""},
	{"neg-0.6-17", "§0.6 独立 {} 语句块", `static Int main() {
    {
        print(1)
    }
    return 0
}
`, ""},
	{"neg-0.6-18", "§0.6 match", `static Int main() {
    match 1 {
        case 1 {
            print(1)
        }
    }
    return 0
}
`, ""},
	{"neg-0.6-19", "§0.6 元组解构", `static Int main() {
    (Int, Int) t = (1, 2)
    (Int a, Int b) = t
    return 0
}
`, ""},
	{"neg-0.6-20", "§0.6 ??=", `static Int main() {
    String? s = null
    s ??= "x"
    return 0
}
`, ""},
	{"neg-0.6-21", "§0.6 ?.() 可空调用", `static Int foo() {
    return 1
}

static Int main() {
    Int? f = null
    f?()
    return 0
}
`, ""},
	{"neg-0.6-22", "§0.6 函数类型箭头", `static Int main() {
    R(P) g = null
    return 0
}
`, ""},

	// ---------- §0.6 并发与元编程 ----------
	{"neg-0.6-23", "§0.6 async 函数", `async static Int main() {
    return 0
}
`, ""},
	{"neg-0.6-24", "§0.6 await", `static Int foo() {
    return 1
}

static Int main() {
    Int x = await foo()
    return x
}
`, ""},
	{"neg-0.6-25", "§0.6 yield", `static Int main() {
    yield 1
    return 0
}
`, ""},
	{"neg-0.6-26", "§0.6 unsafe 块", `static Int main() {
    unsafe {
        print(1)
    }
    return 0
}
`, ""},
	{"neg-0.6-27", "§0.6 macro", `macro FOO 1

static Int main() {
    return 0
}
`, ""},

	// ---------- §0.6 包与类型声明 ----------
	{"neg-0.6-28", "§0.6 显式 export 列表", `export { A }

class A {
    Int v = 1
}
`, ""},
	{"neg-0.6-29", "§0.6 嵌套类型", `class Outer {
    class Inner {
        Int v = 1
    }
}

static Int main() {
    return 0
}
`, ""},
	{"neg-0.6-30", "§0.6 静态初始化块", `class A {
    static {
    }
}

static Int main() {
    return 0
}
`, ""},
	{"neg-0.6-31", "§0.6 多继承", `class A {
    Int a = 1
}

class B {
    Int b = 2
}

class C : A, B {
}

static Int main() {
    return 0
}
`, ""},
	{"neg-0.6-32", "§0.6 类方法覆写", `class A {
    Int f() {
        return 1
    }
}

class B : A {
    public Int f() {
        return 2
    }
}

static Int main() {
    return 0
}
`, "TY-203"},
	{"neg-0.6-33", "§0.6 抽象方法", `abstract class A {
    Int f()
}

static Int main() {
    return 0
}
`, ""},
	{"neg-0.6-34", "§0.6 单例实现协议", `protocol P {
    Int f()
}

singleton S implements P {
    Int f() {
        return 1
    }
}

static Int main() {
    return 0
}
`, "SYN-110"},
	{"neg-0.6-35", "§0.6 结构体实例引用字段", `struct S {
    String s = "x"
}

static Int main() {
    return 0
}
`, "TY-204"},
	{"neg-0.6-36", "§0.6 协议字段", `protocol P {
    Int v
}

static Int main() {
    return 0
}
`, ""},
	{"neg-0.6-37", "§0.6 协议方法体", `protocol P {
    Int f() {
        return 1
    }
}

static Int main() {
    return 0
}
`, ""},
	{"neg-0.6-38", "§0.6 泛型协议", `protocol P<T> {
    Int f(T x)
}

static Int main() {
    return 0
}
`, ""},
	{"neg-0.6-39", "§0.6 泛型约束 where", `static T id<T>(T x) where T : Object {
    return x
}

static Int main() {
    return 0
}
`, ""},
	{"neg-0.6-40", "§0.6 包级私有 internal", `internal class A {
    Int v = 1
}

static Int main() {
    return 0
}
`, ""},

	// ---------- §0.6 已知红线：当前实现静默接受 ----------
	{"neg-0.6-41", "§0.6 类型别名", `type Foo = Int

static Int main() {
    return 0
}
`, ""},
	{"neg-0.6-42", "§0.6 隐式数值提升", `static Int main() {
    Int i = 1
    Long l = i
    return 0
}
`, ""},
	{"neg-0.6-43", "§0.6 Bool 与整数互转", `static Int main() {
    Bool b = true
    Int i = b
    return i
}
`, ""},

	// ---------- §1.3 标识符与类型名 ----------
	{"neg-1.3-01", "§1.3 保留名 async", `static Int main() {
    Int async = 1
    return async
}
`, ""},
	{"neg-1.3-02", "§1.3 保留名 await", `static Int main() {
    Int await = 1
    return await
}
`, ""},
	{"neg-1.3-03", "§1.3 保留名 yield", `static Int main() {
    Int yield = 1
    return yield
}
`, ""},
	{"neg-1.3-04", "§1.3 保留名 unsafe", `static Int main() {
    Int unsafe = 1
    return unsafe
}
`, ""},
	{"neg-1.3-05", "§1.3 保留名 extern", `static Int main() {
    Int extern = 1
    return extern
}
`, ""},
	{"neg-1.3-06", "§1.3 保留名 macro", `static Int main() {
    Int macro = 1
    return macro
}
`, ""},
	{"neg-1.3-07", "§1.3 预定义类型名遮蔽", `class String {
    Int v = 1
}

static Int main() {
    return 0
}
`, "RES-102"},
	{"neg-1.3-08", "§1.3 Array 作类型名", `static Int main() {
    Array xs
    return 0
}
`, ""},
	{"neg-1.3-09", "§1.3 字面量名作声明名", `static Int main() {
    Int true = 1
    return 0
}
`, ""},

	// ---------- §3.2 导入 ----------
	{"neg-3.2-01", "§3.2 通配符导入", `import lib.*

static Int main() {
    return 0
}
`, ""},
	{"neg-3.2-02", "§3.2 包别名", `import lib as l

static Int main() {
    return 0
}
`, ""},

	// ---------- §10.4 defer 清理体限制 ----------
	{"neg-10.4-01", "§10.4 defer 内 return", `static Int main() {
    defer {
        return 1
    }
    return 0
}
`, ""},
	{"neg-10.4-02", "§10.4 defer 内 try", `static Int f() {
    return 1
}

static Int main() {
    defer {
        try f()
    }
    return 0
}
`, ""},
	{"neg-10.4-03", "§10.4 defer 内 throw", `static Int main() {
    defer {
        throw 1
    }
    return 0
}
`, ""},

	// ---------- §2.11 元组形态 ----------
	{"neg-2.11-01", "§2.11 单元素元组", `static Int main() {
    (Int,) t = (1,)
    return 0
}
`, ""},
	{"neg-2.11-02", "§2.11 零元元组", `static Int main() {
    () t = ()
    return 0
}
`, ""},

	// ---------- §6 自增只作语句 ----------
	{"neg-6-01", "§6.1 i++ 作表达式", `static Int main() {
    Int i = 0
    Int a = i++
    return a
}
`, ""},
}
