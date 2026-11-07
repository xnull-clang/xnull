package sema

import (
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// GEN-01 检查表补项：G10 类型参数不得重名（sema 防御性诊断）。
func TestGEN01SemaRejectG10DuplicateTypeParam(t *testing.T) {
	expectCode(t, `
static T f<T, T>(T v) { return v }
static Int main() { return 0 }`, ResRedecl)
}

// GEN-01 检查表补项：G12 泛型函数不能作为值（无实例化的函数引用必须拒绝）。
func TestGEN01G12GenericFuncAsValueRejected(t *testing.T) {
	src := `
static T id<T>(T v) { return v }
static Int main() {
    var f = id<Int>
    return 0
}`
	_, diags := xfront.ParseUnit("g12.x", src)
	if len(diags) == 0 {
		t.Fatalf("泛型函数作为值应被拒绝（当前语法/语义面）")
	}
}

// GEN-01 检查表补项：G17 类型约束（where/`:` 约束）必须拒绝。
// 语言层无约束语法，当前由 xfront 在声明层拒绝；此处锁定“不可静默接受”。
func TestGEN01G17ConstraintRejected(t *testing.T) {
	src := `
static T f<T: Comparable>(T v) { return v }
static Int main() { return 0 }`
	u, diags := xfront.ParseUnit("g17.x", src)
	if len(diags) == 0 {
		t.Fatalf("类型约束应被拒绝，实际无解析诊断；sema=%v", Analyze("g17.x", u))
	}
}
