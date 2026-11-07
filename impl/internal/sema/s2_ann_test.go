package sema

import (
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// ANN-01：注解声明/使用目标/重复/未知。
func TestS2ANN01(t *testing.T) {
	// 声明 + 使用通过。
	expectNone(t, `
@annotation Marker {
    final String name = "";
}
@Marker
class Device { Int x = 0; }
static Int main() { return 0 }`)

	// 未知注解。
	expectCode(t, `
@Nope
class C { Int x = 0; }
static Int main() { return 0 }`, TyAnnotation)

	// 同一目标重复注解。
	expectCode(t, `
@annotation Marker { final Int v = 0; }
@Marker
@Marker
class C { Int x = 0; }
static Int main() { return 0 }`, TyAnnotation)

	// @Override 只能用于方法。
	expectCode(t, `
@annotation Marker { final Int v = 0; }
class C {
    @Override
    Int x = 0;
}
static Int main() { return 0 }`, TyAnnotation)

	// @ReadOnly 只能用于字段。
	expectCode(t, `
class C {
    @ReadOnly
    Int f() { return 1 }
}
static Int main() { return 0 }`, TyAnnotation)

	// 注解字段必须 final（解析层）。
	if _, ds := xfront.ParseUnit("a.x", `
@annotation Bad {
    Int v;
}
static Int main() { return 0 }`); len(ds) == 0 {
		t.Fatalf("注解非 final 字段应被拒绝")
	}

	// @Override 对应协议方法仍通过（不误伤）。
	expectNone(t, `
protocol P { Bool go(); }
class C implements P {
    @Override
    Bool go() { return true }
}
static Int main() { return 0 }`)
}
