package codegen

import "testing"

// M4.4a：非空 ArrayLit 的元素类型推断——实参、嵌套、返回容器。
func TestM44aArrayLitInfer(t *testing.T) {
	src := `
import xdk.collections;
static Int sum(List<Int> xs) {
    Int s = 0;
    for v in xs { s = s + v; }
    return s;
}
static Int countStr(List<String> xs) { return xs.length(); }
static List<Int> makeList() {
    List<Int> xs = [1, 2, 3];
    return xs;
}
static List<List<Int>> makeNested() {
    List<List<Int>> xs = [[1, 2], [3]];
    return xs;
}
static Int sumNested(List<List<Int>> xs) {
    Int s = 0;
    for inner in xs { for v in inner { s = s + v; } }
    return s;
}
static Int main() {
    print(sum([1, 2]));
    print(countStr(["a", "b"]));
    print(sum(makeList()));
    List<Int> ys = makeList();
    print(ys.length());
    print(sumNested([[1, 2], [3]]));
    List<List<Int>> ns = makeNested();
    print(ns.length());
    print(sumNested(ns));
    return 0;
}`
	got, code := compileAndRun(t, src)
	if want := "3\n2\n6\n3\n6\n2\n6\n"; got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
}
