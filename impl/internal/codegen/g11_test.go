package codegen

import "testing"

// G11：列表字面量以函数形参为元素时，容器局部的 defer free 会先于
// return 表达式执行，导致 get/at 读到已释放容器（fatal: 容器下标越界）。
// 修复：return 的标量表达式先落到临时变量，再执行清理。
func TestG11ListParamElementGet(t *testing.T) {
	src := `static Int f(Int v) {
    List<Int> box = [v]
    return box.get(0)
}
static Int main() {
    print(f(4))
    return 0
}
`
	out, code := compileAndRun(t, src)
	if code != 0 || out != "4\n" {
		t.Fatalf("List<Int> 形参元素 get：out=%q code=%d，期望 \"4\\n\" / 0", out, code)
	}
}

func TestG11ListParamElementAtAndLength(t *testing.T) {
	src := `static Int f(Int v) {
    List<Int> box = [v]
    return box.get(0)
}
static Int g(Int v) {
    List<Int> box = [v]
    return box.length()
}
static String h(String v) {
    List<String> box = [v]
    return box.get(0)
}
static Int main() {
    print(f(7))
    print(g(3))
    print(h("hi"))
    return 0
}
`
	out, code := compileAndRun(t, src)
	if code != 0 || out != "7\n1\nhi\n" {
		t.Fatalf("List 形参元素 get/length：out=%q code=%d，期望 \"7\\n1\\nhi\\n\" / 0", out, code)
	}
}
