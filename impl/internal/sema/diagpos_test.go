package sema

import (
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// ERR-01 B2：清理体单条局部声明必须指向声明类型，不得 0:0。
func TestERR205CleanupLocalDeclPosition(t *testing.T) {
	u, pdiags := xfront.ParseUnit("qa.x", "static Int main() {\n    defer Int x = 1\n    return 0\n}")
	if len(pdiags) != 0 {
		t.Fatalf("解析诊断：%v", pdiags)
	}
	for _, d := range Analyze("qa.x", u) {
		if d.Code != ErCleanupBody {
			continue
		}
		if d.Line != 2 || d.Col != 11 {
			t.Fatalf("ERR-205 位置 = %d:%d，期望 2:11（指向 `Int`）", d.Line, d.Col)
		}
		return
	}
	t.Fatalf("未触发 %s", ErCleanupBody)
}

// ERR-01 B2：所有语义诊断必须带非零行列（DG-02 / S8 附录 C.4）。
// 逐码触发；任何诊断 Line/Col <= 0 即失败。
func TestAllDiagPositionsNonZero(t *testing.T) {
	cases := []struct {
		code string
		src  string
	}{
		{ResUndefined, `static Int main() { print(nope); return 0 }`},
		{ResRedecl, `static Int main() { Int x = 1; Int x = 2; return 0 }`},
		{ResAliasConflict, `import xdk.text.Regex as P
import xdk.tasks.Context as P

static Int main() { return 0 }`},
		{ResXdkNotImport, `static Int main() { diagnose("x"); return 0 }`},
		{ResNotFound, `import xdk.nonexist

static Int main() { return 0 }`},
		{ResNeedlessAlias, `import xdk.text.Regex as Pattern

static Int main() { return 0 }`},
		{TyXdkUnsupported, `import xdk.collections

static Int main() { sort(1); return 0 }`},

		{DaMaybeUnassigned, `static Int main() { Int x; print(str(x)); return 0 }`},
		{DaReassign, `static Int main() {
    final Int x = 1
    x = 2
    return 0
}`},
		{DaMissingReturn, `static Int f() {
    print("x")
}

static Int main() { return 0 }`},

		{TyAssignability, `static Int main() { Int i = 1.5; return 0 }`},
		{TyNullToValue, `static Int main() { Result<Int, String> r = null; return 0 }`},
		{TyCondNotBool, `static Int main() { if 1 { return 0 }; return 0 }`},
		{TyBadOperand, `static Int main() { Int i = 1 + 2.0; return 0 }`},
		{TyTuple, `static Int main() { (Int, Int) p = (1, 2); print(p.2); return 0 }`},
		{TyMapKey, `static Int main() { Map<Bool, Int> m = [:]; return 0 }`},
		{TyModifier, `abstract struct S { Int x = 0; }

static Int main() { return 0 }`},
		{TyInherit, `class A : B { }
class B : A { }

static Int main() { return 0 }`},
		{TyOverride, `class B { Int id = 0; }
class D : B { Int id = 1; }

static Int main() { return 0 }`},
		{TyStructVal, `struct S { String name; }

static Int main() { return 0 }`},
		{TyProtoForm, `protocol P { private void go(); }

static Int main() { return 0 }`},
		{TyEnumRule, `enum E { A, A }

static Int main() { return 0 }`},
		{TyPrivField, `class C { private Int _x; }

static Int main() { return 0 }`},

		{GenTypeArgs, `static T id<T>(T v) { return v }
static Int main() { print(id<Int, Int>(1)); return 0 }`},
		{GenInfer, `static T pick<T>(T a, T b) { return a }
static Int main() { print(pick(1, "s")); return 0 }`},
		{GenOverload, `static T pick<T>(T a) { return a }
static Int main() { print(pick(true, false)); return 0 }`},
		{GenScope, `class Box { Int n = 0; }
static T build<T>() { T z = new T(); return z }
static Int main() { build<Box>(); return 0 }`},

		{ErResultMustUse, `static Result<Int, String> g() { return Ok(1) }
static Int main() { g(); return 0 }`},
		{ErResultCtor, `static Int main() { Result<Int> r; return 0 }`},
		{ErResultMember, `static Int main() { Result<Int, String> r = Ok(1); print(r.value(1)); return 0 }`},
		{ErTryContext, `static Int main() {
    Int v = try 1
    return v
}`},
		{ErCleanupBody, `static Int main() {
    defer Int x = 1
    return 0
}`},
		{ErErrdeferContext, `static Int main() {
    errdefer print("x")
    return 0
}`},
	}
	seen := map[string]bool{}
	for _, c := range cases {
		u, pdiags := xfront.ParseUnit("pos.x", c.src)
		if len(pdiags) != 0 {
			t.Fatalf("%s 源码不应有解析诊断：%v", c.code, pdiags)
		}
		ds := Analyze("pos.x", u)
		hit := false
		for _, d := range ds {
			if d.Line <= 0 || d.Col <= 0 {
				t.Errorf("%s 诊断位置非法：%s", c.code, d.String())
			}
			if d.Code == c.code {
				hit = true
				seen[c.code] = true
			}
		}
		if !hit {
			t.Errorf("未触发诊断码 %s：%v", c.code, ds)
		}
	}
	if len(seen) != len(cases) {
		t.Errorf("覆盖诊断码 %d/%d：%v", len(seen), len(cases), seen)
	}
}
