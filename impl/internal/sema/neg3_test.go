package sema

import (
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// NEG-1.3 余项：类型别名、Array 类型名、字面量声明名必须被拒绝。
func TestNEG3Rejections(t *testing.T) {
	// type Foo = Int：语言不支持类型别名（当前在 sema 以未定义类型拒绝）。
	if ds := Analyze("n.x", mustUnit(t, "type Foo = Int\nstatic Int main() { return 0 }")); len(ds) == 0 {
		t.Fatalf("类型别名应被拒绝")
	}
	// Array 不是语言类型。
	if ds := Analyze("n.x", mustUnit(t, "static Int main() { Array xs; return 0 }")); len(ds) == 0 {
		t.Fatalf("Array 类型名应被拒绝")
	}
	// true 不能作声明名（解析层）。
	if _, ds := xfront.ParseUnit("n.x", "static Int main() { Int true = 1; return 0 }"); len(ds) == 0 {
		t.Fatalf("true 声明名应被拒绝")
	}
}

func mustUnit(t *testing.T, src string) *xfront.CompilationUnit {
	t.Helper()
	u, ds := xfront.ParseUnit("n.x", src)
	if len(ds) != 0 {
		t.Fatalf("解析诊断：%v", ds)
	}
	return u
}
