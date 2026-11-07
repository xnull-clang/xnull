package sema

import (
	"strings"
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// ---------- M1 / GEN-01：泛型函数 sema 半边（S1 §8） ----------
// 红证据：wt/c1-rd3/evidence/M1-GEN-01/before（TestGEN01 24 FAIL，卡在 sema）。
// 本文件新增用例，不修改既有期望；codegen 侧单态化由 c1-rd3 交付，本包只负责
// 类型参数作用域、显式实参、推断/冲突/未绑定、重载、写回 Call.TypeArgs。

func expectGenCode(t *testing.T, src, code, contains string) {
	t.Helper()
	for _, c := range codes(t, src) {
		if strings.HasPrefix(c, code) && strings.Contains(c, contains) {
			return
		}
	}
	t.Fatalf("期望 %s 且包含 %q，实际：%v", code, contains, codes(t, src))
}

func TestGEN01SemaAccept(t *testing.T) {
	cases := []struct{ name, src string }{
		{"G1a 显式实参", `
static T identity<T>(T v) { return v }
static Int main() { print(identity<Int>(7)); return 0 }`},
		{"G2a 直接推断", `
static T identity<T>(T v) { return v }
static Int main() { print(identity(7)); return 0 }`},
		{"G2b 嵌套 List<T> 推断", `
static T head<T>(List<T> xs) { return xs.get(0) }
static Int main() {
    List<Int> xs = [4, 5]
    print(head(xs))
    return 0
}`},
		{"G2c 字面量绑定 Int", `
static T pick<T>(T a, T b) { return b }
static Int main() { print(pick(1, 2)); return 0 }`},
		{"G2c 字面量适配已绑定 T", `
static T pick<T>(T a, T b) { return b }
static Int main() { print(pick(1L, 2)); return 0 }`},
		{"G5a 普通同名函数优先", `
static Int pick(Int v) { return v + 1 }
static T pick<T>(T v) { return v }
static Int main() { print(pick(3)); return 0 }`},
		{"G5a 普通候选不适用时回落泛型", `
static Int pick(Int v) { return v + 1 }
static T pick<T>(T v) { return v }
static Int main() { print(pick("s")); return 0 }`},
		{"G6a 两个实例类型实参", `
static T identity<T>(T v) { return v }
static Int main() {
    print(identity<Int>(1))
    print(identity<String>("s"))
    return 0
}`},
		{"G6b 实例内 List<T> 操作", `
static Int count<T>(List<T> xs) { return xs.length() }
static Int main() {
    List<Int> a = [1, 2, 3]
    List<String> b = ["x"]
    print(count(a))
    print(count(b))
    return 0
}`},
		{"G8 Result 实参实例化", `
static T unwrapOr<T>(Result<T, String> r, T d) { return r.unwrapOr(d) }
static Int main() {
    Result<Int, String> r = Ok(5)
    print(unwrapOr(r, 0))
    return 0
}`},
		{"G11 类型参数用于局部与嵌套", `
static T keep<T>(T v) {
    T local = v
    List<T> box = [v]
    return local
}
static Int main() { print(keep(9)); return 0 }`},
		{"G14 泛型内 is 具体类型", `
static Bool isInt<T>(T v) { return v is Int }
static Int main() { print(isInt<Int>(1)); return 0 }`},
		{"G18 泛型与普通同名共存", `
static Int plain(Int v) { return v }
static T gen<T>(T v) { return v }
static Int main() { print(plain(2)); print(gen(3)); return 0 }`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) { expectNone(t, c.src) })
	}
}

func TestGEN01SemaReject(t *testing.T) {
	cases := []struct{ name, src, code, contains string }{
		{"G1b 显式实参数量", `
static T identity<T>(T v) { return v }
static Int main() { print(identity<Int, Int>(7)); return 0 }`,
			GenTypeArgs, "类型实参"},
		{"G2d 返回类型不参与推断", `
static T make<T>() { T z = 0; return z }
static Int main() { Int x = make(); print(x); return 0 }`,
			GenInfer, "未绑定"},
		{"G3 冲突绑定", `
static T pick<T>(T a, T b) { return a }
static Int main() { print(pick(1, "s")); return 0 }`,
			GenInfer, "冲突"},
		{"G4 未绑定类型参数（单参数可解析形态）", `
static T empty<T>() { T z = 0; return z }
static Int main() { empty(); return 0 }`,
			GenInfer, "未绑定"},
		{"G5c 零候选", `
static T pick<T>(T a) { return a }
static Int main() { print(pick(true, false)); return 0 }`,
			GenOverload, "实参"},
		{"G9 类型参数越界", `
static T leak<T>(T v) { return v }
static T useTop() { T z = 0; return z }
static Int main() { return 0 }`,
			ResUndefined, "未定义"},
		{"G13 类型实参不能 void", `
static T nothing<T>() { T z = 0; return z }
static Int main() { nothing<void>(); return 0 }`,
			GenTypeArgs, "void"},
		{"G15 泛型内 new T()", `
class Box { Int n = 0; }
static T build<T>() { T z = new T(); return z }
static Int main() { build<Box>(); return 0 }`,
			GenScope, "new"},
		{"G19 null 不能定 T", `
static T id<T>(T v) { return v }
static Int main() { print(id(null)); return 0 }`,
			GenInfer, "null"},
		{"G7 无限展开", `
static T loop<T>(T v) { return loop<T>(v) }
static Int main() { print(loop<Int>(1)); return 0 }`,
			GenScope, "展开"},
		{"重载歧义", `
static T pick<T>(T a) { return a }
static T pick<T>(List<T> a) { return a }
static Int main() {
    List<Int> xs = [1]
    print(pick(xs))
    return 0
}`,
			GenOverload, "歧义"},
		{"显式实参与形参不符（不得退回泛型未实现）", `
static T identity<T>(T v) { return v }
static Int main() { print(identity<Int>("s")); return 0 }`,
			TyAssignability, "形参 Int"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) { expectGenCode(t, c.src, c.code, c.contains) })
	}
}

// 推断成功后必须把最终类型实参写回 Call.TypeArgs（codegen 单态化输入契约）。
func TestGEN01WritesBackTypeArgs(t *testing.T) {
	u, pd := xfront.ParseUnit("g.x", `
static T identity<T>(T v) { return v }
static Int main() { print(identity(7)); return 0 }`)
	if len(pd) != 0 {
		t.Fatalf("解析诊断：%v", pd)
	}
	if sd := Analyze("g.x", u); len(sd) != 0 {
		t.Fatalf("不应有语义诊断：%v", sd)
	}
	var mainFn *xfront.TopFunc
	for _, d := range u.Decls {
		if f, ok := d.(*xfront.TopFunc); ok && f.Name == "main" {
			mainFn = f
		}
	}
	if mainFn == nil || mainFn.Body == nil || len(mainFn.Body.Stmts) == 0 {
		t.Fatalf("未找到 main 体")
	}
	pr, ok := mainFn.Body.Stmts[0].(*xfront.ExprStmt)
	if !ok {
		t.Fatalf("main 首语句不是表达式语句")
	}
	printCall, ok := pr.X.(*xfront.Call)
	if !ok || len(printCall.Args) != 1 {
		t.Fatalf("main 首语句不是 print(identity(7))")
	}
	call, ok := printCall.Args[0].(*xfront.Call)
	if !ok {
		t.Fatalf("print 实参不是调用")
	}
	if len(call.TypeArgs) != 1 || typeKey(call.TypeArgs[0]) != "Int" {
		t.Fatalf("推断结果未写回 Call.TypeArgs：%+v", call.TypeArgs)
	}
}
