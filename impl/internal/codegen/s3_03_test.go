package codegen

import (
	"strings"
	"testing"
)

// funcBody 截取生成 C 中某个顶层函数的函数体（用于区分调用点与未使用的包装函数）。
func funcBody(csrc, sig string) string {
	i := strings.Index(csrc, sig)
	if i < 0 {
		return ""
	}
	rest := csrc[i+len(sig):]
	j := strings.Index(rest, "\n}")
	if j < 0 {
		return rest
	}
	return rest[:j]
}

// S3-03：Escape=none 的纯值类对象栈分配（无分配器调用、无 ARC/GC 记账）。
func TestS3_03StackAllocation(t *testing.T) {
	src := `class V {
    Int x = 1;
    Int get() { return self.x }
}
class P {
    Int x;
    P(Int a) { self.x = a }
}
static Int main() {
    V v = new V()
    print(v.x)
    v.x = 41
    print(v.get())
    V w = new V()
    w.x = 2
    print(w.x)
    print(v === w)
    P p = new P(5)
    print(p.x)
    return 0
}`
	csrc := emitWithPolicy(t, src)
	main := funcBody(csrc, "int64_t xn_main() {")
	if strings.Contains(main, "xn_Cls_V_new()") || strings.Contains(main, "xn_Cls_P_new(") {
		t.Fatalf("Escape=none 的类在调用点不应走堆分配：\n%s", main)
	}
	if !strings.Contains(main, "memset((char *)&") || !strings.Contains(main, "sizeof(xn_Cls_V))") {
		t.Fatalf("缺少栈对象初始化：\n%s", main)
	}
	if !strings.Contains(main, "xn_Cls_P_new_init") {
		t.Fatalf("带参构造的栈对象应调用 init 函数：\n%s", main)
	}
	got, code := compileAndRunPolicy(t, src)
	want := "1\n41\n2\nfalse\n5\n"
	if got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
}

// S3-03：栈对象身份与生命周期——循环内每次构造是独立对象。
func TestS3_03StackLoopIdentity(t *testing.T) {
	src := `class V { Int x = 0; }
static Int main() {
    Int i = 0
    while (i < 2) {
        V v = new V()
        v.x = i
        print(v.x)
        i = i + 1
    }
    return 0
}`
	csrc := emitWithPolicy(t, src)
	main := funcBody(csrc, "int64_t xn_main() {")
	if strings.Contains(main, "xn_Cls_V_new()") {
		t.Fatalf("循环内栈候选类不应走堆分配：\n%s", main)
	}
	got, code := compileAndRunPolicy(t, src)
	if got != "0\n1\n" || code != 0 {
		t.Fatalf("out=%q code=%d，期望 0/1", got, code)
	}
}

// S3-03：局部被发布（实参/返回/别名）时退回 ARC 堆分配，保证语义不变。
func TestS3_03EscapingLocalStaysHeap(t *testing.T) {
	src := `class V { Int x = 1; }
static Int take(V v) { return v.x }
static V make() {
    V v = new V()
    return v
}
static Int main() {
    V v = new V()
    print(take(v))
    V m = make()
    print(m.x)
    V w = v
    print(w.x)
    return 0
}`
	csrc := emitWithPolicy(t, src)
	if !strings.Contains(funcBody(csrc, "int64_t xn_main() {"), "xn_Cls_V_new()") {
		t.Fatalf("被发布的局部应退回 ARC 堆分配：\n%s", csrc)
	}
	if !strings.Contains(funcBody(csrc, "xn_make() {"), "rt_retain") {
		t.Fatalf("返回局部应保留 ARC 语义：\n%s", csrc)
	}
	got, code := compileAndRunPolicy(t, src)
	if got != "1\n1\n1\n" || code != 0 {
		t.Fatalf("out=%q code=%d，期望 1/1/1", got, code)
	}
}

// S3-03：Escape=return（有 deinit）→ ARC；Escape=other（引用环）→ GC。
func TestS3_03EscapeReturnAndOther(t *testing.T) {
	src := `class D {
    Int x = 1;
    void deinit() { print("d-deinit") }
}
class Node {
    Node next;
    void deinit() { print("n-deinit") }
}
static Int main() {
    D d = new D()
    print(d.x)
    Node n = new Node()
    n.next = n
    return 0
}`
	csrc := emitWithPolicy(t, src)
	if !strings.Contains(csrc, "rt_arc_new(&RT_TYPE_XN_D)") {
		t.Fatalf("Escape=return 的类应为 ARC 堆分配：\n%s", csrc)
	}
	if !strings.Contains(csrc, "rt_gc_new(&RT_TYPE_XN_Node)") {
		t.Fatalf("Escape=other 的类应为 GC 堆分配：\n%s", csrc)
	}
	got, code := compileAndRunPolicy(t, src)
	if want := "1\nd-deinit\nn-deinit\n"; got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q", got, code, want)
	}
}
