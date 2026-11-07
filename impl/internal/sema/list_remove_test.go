package sema

import "testing"

// M6-B0-05：List.remove 返回被删元素类型 V（与 E3 解释器、E4 codegen 同批）。
// 正例：返回值可赋给 V；负例：赋给其他类型报 TY-101。
func TestListRemoveReturnsElement(t *testing.T) {
	expectNone(t, `
static Int main() {
    List<Int> xs = [1, 2, 3]
    Int removed = xs.remove(0)
    return removed
}`)
	expectNone(t, `
static Int main() {
    List<String> xs = ["a", "b"]
    String removed = xs.remove(1)
    print(removed)
    return 0
}`)
	// 语句位置仍合法（返回值可丢弃）。
	expectNone(t, `
static Int main() {
    List<Int> xs = [1, 2]
    xs.remove(0)
    return 0
}`)
	// 负例：List<Int>.remove 返回 Int，不能赋给 String。
	expectCode(t, `
static Int main() {
    List<Int> xs = [1, 2]
    String removed = xs.remove(0)
    return 0
}`, TyAssignability)
}
