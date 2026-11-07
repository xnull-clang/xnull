package codegen

import (
	"strings"
	"testing"
)

// S3-02：GC 引用局部/参数/全局字段登记为根；分配点与循环回边发射安全点。
func TestS3_02RootEmission(t *testing.T) {
	src := `class N { N? next; Int x = 0; }
N g = new N()
static Int use(N n) { return n.x }
static Int main() {
    N n = new N()
    print(use(n))
    return 0
}`
	csrc := emitWithPolicy(t, src)
	main := funcBody(csrc, "int64_t xn_main() {")
	if !strings.Contains(main, "size_t xn_t") || !strings.Contains(main, "= xn_root_mark();") {
		t.Fatalf("缺少栈根帧标记：\n%s", main)
	}
	if !strings.Contains(main, "xn_root_add(n);") {
		t.Fatalf("GC 局部未登记栈根：\n%s", main)
	}
	if !strings.Contains(main, "xn_root_restore(") {
		t.Fatalf("缺少根帧恢复：\n%s", main)
	}
	if !strings.Contains(main, "xn_gc_safepoint();") {
		t.Fatalf("分配点未发射安全点：\n%s", main)
	}
	use := funcBody(csrc, "xn_use(xn_Cls_N * xn_p_n) {")
	if !strings.Contains(use, "xn_root_add(xn_p_n);") {
		t.Fatalf("GC 参数未登记根：\n%s", use)
	}
	if !strings.Contains(funcBody(csrc, "static void xn_init_globals(void) {"), "xn_root_hold(xn_g_g);") {
		t.Fatalf("GC 顶层字段未登记全局根：\n%s", csrc)
	}
}

// S3-02：循环回边安全点——中途收集时栈局部根保护（keep 存活到退出收集）。
func TestS3_02MidCollectionKeepsLocalRoot(t *testing.T) {
	src := `class N {
    N? next;
    Int x = 0;
    void deinit() { if (self.x == 7) { print("keep-deinit") } }
}
static Int main() {
    N keep = new N()
    keep.x = 7
    Int i = 0
    while (i < 3000) {
        N tmp = new N()
        tmp.x = 1
        i = i + 1
    }
    print("main-done")
    print(keep.x)
    return 0
}`
	csrc := emitWithPolicy(t, src)
	if strings.Count(csrc, "xn_gc_safepoint();") < 2 {
		t.Fatalf("循环回边/分配点安全点缺失：\n%s", csrc)
	}
	got, code := compileAndRunPolicy(t, src)
	want := "main-done\n7\nkeep-deinit\n"
	if got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q（keep 被中途收集？）", got, code, want)
	}
}

// S3-02：参数根保护——实参对象在调用方帧的循环中不被途收。
func TestS3_02ParamRootAcrossCollection(t *testing.T) {
	src := `class N {
    N? next;
    Int x = 0;
    void deinit() { if (self.x == 9) { print("param-deinit") } }
}
static N mk(Int v) { N n = new N(); n.x = v; return n }
static Int use(N n) {
    Int i = 0
    while (i < 3000) {
        N tmp = new N()
        tmp.x = 1
        i = i + 1
    }
    print("use-done")
    return n.x
}
static Int main() {
    print(use(mk(9)))
    return 0
}`
	got, code := compileAndRunPolicy(t, src)
	want := "use-done\n9\nparam-deinit\n"
	if got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q（参数未被根保护？）", got, code, want)
	}
}

// S3-02：顶层字段全局根——中途收集不误收全局对象。
func TestS3_02GlobalRootAcrossCollection(t *testing.T) {
	src := `class N {
    N? next;
    Int x = 5;
    void deinit() { if (self.x == 5) { print("global-deinit") } }
}
N g = new N()
static Int main() {
    Int i = 0
    while (i < 2000) {
        N tmp = new N()
        tmp.x = 1
        i = i + 1
    }
    print("main-done")
    print(g.x)
    return 0
}`
	// 全局根常驻：中途收集不回收 g；进程退出前也不撤销全局根（无 deinit）。
	got, code := compileAndRunPolicy(t, src)
	want := "main-done\n5\n"
	if got != want || code != 0 {
		t.Fatalf("out=%q code=%d，期望 %q（全局根缺失？）", got, code, want)
	}
}
