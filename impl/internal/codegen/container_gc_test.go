package codegen

import (
	"strings"
	"testing"
)

// S3-01（ADR-007）：T[]/List/Map/Set 是 GC 对象（分配头 + 长度 + 元素区）。
func TestS3_01ContainerGCAllocation(t *testing.T) {
	src := `
import xdk.collections
static Int main() {
    List<Int> xs = [1, 2]
    Set<Int> s = []
    Map<String, Int> m = []
    return xs.length() + s.length() + m.length()
}`
	csrc := emitWithPolicy(t, src)
	for _, sym := range []string{
		"xn_gc_new(&RT_TYPE_xn_arr_i)",
		"xn_gc_new(&RT_TYPE_xn_set_i)",
		"xn_gc_new(&RT_TYPE_xn_map_s_i)",
		", NULL };", // 纯值元素容器：无 scan
	} {
		if !strings.Contains(csrc, sym) {
			t.Fatalf("容器未按 GC 对象生成，缺少 %q", sym)
		}
	}
	if strings.Contains(csrc, "xn_arr_i xs =") {
		t.Fatalf("容器局部仍是值结构（应为指针）")
	}
}

// S3-01：GC 元素进容器——元素区登记扫描；不可达时元素随 GC 回收。
func TestS3_01GCContainerElements(t *testing.T) {
	src := `
class Node {
    Node next;
    void deinit() { print("node-deinit") }
}
static Int main() {
    List<Node> xs = []
    Node a = new Node()
    Node b = new Node()
    xs.push(a)
    xs.push(b)
    print(xs.length())
    return 0
}`
	got, code := compileAndRunPolicy(t, src)
	if code != 0 {
		t.Fatalf("退出码 %d", code)
	}
	if !strings.HasPrefix(got, "2\n") {
		t.Fatalf("输出 %q，期望以 2 开头", got)
	}
	if n := strings.Count(got, "node-deinit"); n != 2 {
		t.Fatalf("GC 元素应由收集回收（2 次 deinit），实际 %d 次：%q", n, got)
	}
}

// S3-01：容器字段（S3 §10 容器是 GC 引用）——可持有、可 push/get，类 scan 访问该字段。
func TestS3_01ContainerField(t *testing.T) {
	src := `
import xdk.collections
class Box {
    List<Int> xs = []
}
static Int main() {
    Box b = new Box()
    b.xs.push(7)
    b.xs.push(8)
    print(b.xs.length())
    print(b.xs.get(1))
    return 0
}`
	got, code := compileAndRunPolicy(t, src)
	if code != 0 || got != "2\n8\n" {
		t.Fatalf("输出 %q(code %d)，期望 \"2\\n8\\n\"", got, code)
	}
	csrc := emitWithPolicy(t, src)
	if !strings.Contains(csrc, "if (o->xs) { visit(o->xs); }") {
		t.Fatalf("类 scan 未访问容器字段")
	}
}

// S3-01：clear/remove 对被移除的 ARC 元素立即 release。
func TestS3_01ClearReleasesARCElements(t *testing.T) {
	src := `
import xdk.collections
class A {
    void deinit() { print("A-deinit") }
}
static Int main() {
    List<A> xs = [new A(), new A()]
    xs.clear()
    print("after-clear")
    return 0
}`
	got, code := compileAndRunPolicy(t, src)
	if code != 0 {
		t.Fatalf("退出码 %d", code)
	}
	if got != "A-deinit\nA-deinit\nafter-clear\n" {
		t.Fatalf("clear 未立即释放 ARC 元素：%q", got)
	}
}
