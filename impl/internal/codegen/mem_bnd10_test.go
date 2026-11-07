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
		"../../../impl/runtime/rt_policy.c", "../../../impl/runtime/rt_weak.c")
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
    String name = "helper"
    void deinit() { print("helper-deinit") }
}
class Node {
    Node next;
    Helper h;
    void deinit() { print("node-deinit " + self.h.name) }
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
	if n := strings.Count(got, "node-deinit helper"); n != 2 {
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
	if !strings.Contains(csrc, "rt_gc_new(&RT_TYPE_XN_Node)") {
		t.Fatalf("Node（引用环）应以 rt_gc_new 分配")
	}
	if !strings.Contains(csrc, "xn_Cls_Node_scan") {
		t.Fatalf("GC 类应生成 scan 钩子")
	}
	if !strings.Contains(csrc, "rt_arc_new(&RT_TYPE_XN_Plain)") {
		t.Fatalf("Plain（非环）应保持 rt_arc_new")
	}
	if strings.Contains(csrc, "rt_gc_new(&RT_TYPE_XN_Plain)") {
		t.Fatalf("非环类不得走 GC")
	}
}

// BND-10：值为空/纯值类保持 ARC（栈候选是许可，不是 GC）。
func TestBND10ValueOnlyStaysARC(t *testing.T) {
	src := `
class ValueOnly { Int x = 1; }
static Int main() {
    ValueOnly v = new ValueOnly()
    return v.x
}`
	csrc := emitWithPolicy(t, src)
	if !strings.Contains(csrc, "rt_arc_new(&RT_TYPE_XN_ValueOnly)") {
		t.Fatalf("纯值类应保持 ARC")
	}
	if strings.Contains(csrc, "rt_gc_new(&RT_TYPE_XN_ValueOnly)") {
		t.Fatalf("纯值类不得走 GC")
	}
}
