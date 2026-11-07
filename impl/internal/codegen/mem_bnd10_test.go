package codegen

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/sema"
	"xnull.dev/xnull/internal/xfront"
)

// compileAndRunPolicy 与 compileAndRun 同，但把 sema 策略交给 codegen
// （BND-10：类分配种类由 §15.1 判定表决定）。
func compileAndRunPolicy(t *testing.T, src string) (string, int) {
	t.Helper()
	u, diags := xfront.ParseUnit("t.x", src)
	if len(diags) != 0 {
		t.Fatalf("解析诊断：%v", diags)
	}
	res, sd := sema.AnalyzeWith("t.x", u)
	if len(sd) != 0 {
		t.Fatalf("语义诊断：%v", sd)
	}
	csrc, err := EmitCWithStrategies(u, nil, res.Strategies(u))
	if err != nil {
		t.Fatalf("代码生成失败：%v", err)
	}
	dir := t.TempDir()
	cfile := filepath.Join(dir, "prog.c")
	if err := os.WriteFile(cfile, []byte(csrc), 0o644); err != nil {
		t.Fatal(err)
	}
	bin := filepath.Join(dir, "prog")
	cc := exec.Command("cc", "-std=c11", "-I", "../../../impl/runtime", "-O2", "-o", bin,
		cfile, "../../../impl/runtime/rt.c", "../../../impl/runtime/rt_gc.c",
		"../../../impl/runtime/rt_policy.c", "../../../impl/runtime/rt_weak.c",
		"../../../impl/runtime/rt_std_bytes.c", "../../../impl/runtime/rt_std_text.c",
		"../../../impl/runtime/xrt_abi.c")
	var ccerr bytes.Buffer
	cc.Stderr = &ccerr
	if err := cc.Run(); err != nil {
		t.Fatalf("cc 编译失败：%v\n%s", err, ccerr.String())
	}
	var out bytes.Buffer
	run := exec.Command(bin)
	run.Stdout = &out
	code := 0
	if err := run.Run(); err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			code = ee.ExitCode()
		} else {
			t.Fatal(err)
		}
	}
	return out.String(), code
}

func emitWithPolicy(t *testing.T, src string) string {
	t.Helper()
	u, diags := xfront.ParseUnit("t.x", src)
	if len(diags) != 0 {
		t.Fatalf("解析诊断：%v", diags)
	}
	res, sd := sema.AnalyzeWith("t.x", u)
	if len(sd) != 0 {
		t.Fatalf("语义诊断：%v", sd)
	}
	csrc, err := EmitCWithStrategies(u, nil, res.Strategies(u))
	if err != nil {
		t.Fatalf("代码生成失败：%v", err)
	}
	return csrc
}

// BND-10：引用环类按策略分配为 GC；程序退出时收集，环内对象 deinit 各执行一次。
func TestBND10GCCycleCollected(t *testing.T) {
	src := `
class Node {
    Node next;
    void deinit() { print("node-deinit") }
}
static Int main() {
    Node a = new Node()
    Node b = new Node()
    a.next = b
    b.next = a
    print("main")
    return 0
}`
	want := "main\nnode-deinit\nnode-deinit\n"
	got, code := compileAndRunPolicy(t, src)
	if got != want || code != 0 {
		t.Fatalf("输出 %q(code %d)，期望 %q（GC 环未被回收？）", got, code, want)
	}
}

// BND-10 / MEM-02：GC 对象持 ARC 引用——deinit 时字段仍有效，之后 sweep 释放一次。
func TestBND10GCMixedARCFieldValid(t *testing.T) {
	src := `
class Helper {
    Int id = 1;
    void deinit() { print("helper-deinit") }
}
class Node {
    Node next;
    Helper h;
    void deinit() { print("node-deinit " + str(self.h.id)) }
}
static Int main() {
    Node a = new Node()
    Node b = new Node()
    a.next = b
    b.next = a
    a.h = new Helper()
    b.h = new Helper()
    print("main")
    return 0
}`
	got, code := compileAndRunPolicy(t, src)
	if code != 0 {
		t.Fatalf("退出码 %d，stderr 见上", code)
	}
	if !strings.Contains(got, "main") {
		t.Fatalf("缺少 main 输出：%q", got)
	}
	if n := strings.Count(got, "node-deinit 1"); n != 2 {
		t.Fatalf("node deinit 时字段应仍有效（2 次），实际 %d 次：%q", n, got)
	}
	if n := strings.Count(got, "helper-deinit"); n != 2 {
		t.Fatalf("helper 应由 sweep 释放 2 次，实际 %d 次：%q", n, got)
	}
}

// BND-10：分配种类由策略决定——环类 rt_gc_new + scan；非环类 rt_arc_new。
func TestBND10PolicyAllocationKinds(t *testing.T) {
	src := `
class Node { Node next; }
class Plain { Int x = 1; }
static Int main() {
    Node n = new Node()
    Plain p = new Plain()
    n.next = n
    return p.x
}`
	csrc := emitWithPolicy(t, src)
	if !strings.Contains(csrc, "xn_gc_new(&RT_TYPE_XN_Node)") {
		t.Fatalf("Node（引用环）应以 rt_gc_new 分配")
	}
	if !strings.Contains(csrc, "xn_Cls_Node_gc_scan") {
		t.Fatalf("GC 类应生成 scan 钩子")
	}
	if strings.Contains(csrc, "xn_gc_new(&RT_TYPE_XN_Plain)") {
		t.Fatalf("非环纯值类不得走 GC")
	}
	// S3-03：Plain 为 Escape=none，局部构造点走栈分配（不再调用堆包装）。
	if strings.Contains(funcBody(csrc, "int64_t xn_main() {"), "xn_Cls_Plain_new()") {
		t.Fatalf("Plain（Escape=none）应栈分配：\n%s", csrc)
	}
}

// BND-10：纯值类不为 GC；S3-03 后栈候选在局部构造点栈分配。
func TestBND10ValueOnlyStackAllocated(t *testing.T) {
	src := `
class ValueOnly { Int x = 1; }
static Int main() {
    ValueOnly v = new ValueOnly()
    return v.x
}`
	csrc := emitWithPolicy(t, src)
	if strings.Contains(csrc, "xn_gc_new(&RT_TYPE_XN_ValueOnly)") {
		t.Fatalf("纯值类不得走 GC")
	}
	if strings.Contains(funcBody(csrc, "int64_t xn_main() {"), "xn_Cls_ValueOnly_new()") {
		t.Fatalf("纯值类（Escape=none）应栈分配：\n%s", csrc)
	}
}

// BND-10b：数据枚举项是 GC 全局根（GC 分配 + 根登记）。
func TestBND10bDataEnumGlobalRoot(t *testing.T) {
	src := `
enum Status {
    Ready(0);
    final Int code;
    Status(Int c) { self.code = c }
}
static Int main() { print(Status.Ready.code); return 0 }`
	csrc := emitWithPolicy(t, src)
	if !strings.Contains(csrc, "xn_gc_new(&RT_TYPE_XN_ENUM_Status)") {
		t.Fatalf("数据枚举未走 GC 分配：\n%s", csrc)
	}
	if !strings.Contains(csrc, "xn_root_hold(xn_enum_Status_Ready);") {
		t.Fatalf("数据枚举项未登记全局根：\n%s", csrc)
	}
	got, code := compileAndRunPolicy(t, src)
	if got != "0\n" || code != 0 {
		t.Fatalf("out=%q code=%d，期望 0", got, code)
	}
}

// BND-10b：单例实例固定 GC + 全局根（启动期初始化后常驻）。
func TestBND10bSingletonGlobalRoot(t *testing.T) {
	src := `
singleton AppInfo {
    Int count = 3;
}
static Int main() { print(AppInfo.instance.count); return 0 }`
	csrc := emitWithPolicy(t, src)
	if !strings.Contains(csrc, "xn_gc_new(&RT_TYPE_XN_SINGLE_AppInfo)") {
		t.Fatalf("单例未走 GC 分配：\n%s", csrc)
	}
	if !strings.Contains(csrc, "xn_root_hold(xn_single_AppInfo);") {
		t.Fatalf("单例实例未登记全局根：\n%s", csrc)
	}
	got, code := compileAndRunPolicy(t, src)
	if got != "3\n" || code != 0 {
		t.Fatalf("out=%q code=%d，期望 3", got, code)
	}
}

// BND-10b：@arc/stack 候选类在局部构造点栈分配（S3-03），身份不变。
func TestBND10bArcStackCandidate(t *testing.T) {
	src := `
class Plain { Int x = 1; }
static Int main() {
    Plain p = new Plain()
    print(p.x)
    return 0
}`
	csrc := emitWithPolicy(t, src)
	if strings.Contains(csrc, "xn_gc_new(&RT_TYPE_XN_Plain)") {
		t.Fatalf("stack 候选类不得走 GC：\n%s", csrc)
	}
	if strings.Contains(funcBody(csrc, "int64_t xn_main() {"), "xn_Cls_Plain_new()") {
		t.Fatalf("stack 候选类应栈分配：\n%s", csrc)
	}
	got, code := compileAndRunPolicy(t, src)
	if got != "1\n" || code != 0 {
		t.Fatalf("out=%q code=%d，期望 1", got, code)
	}
}
