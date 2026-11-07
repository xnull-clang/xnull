package codegen

import (
	"strings"
	"testing"

	"xnull.dev/xnull/internal/sema"
	"xnull.dev/xnull/internal/xfront"
)

// S2 MEM-01：deinit 顺序（S2 §6.4）——用户体先执行，字段释放后执行；
// 继承链由父类 deinit 钩子承接（当前 sema 拒绝子类自定义 deinit，见 MEM-01 回执）。
func TestS2MEM01DeinitOrderBaseChain(t *testing.T) {
	src := `
class Base {
    String name = "base"
    void deinit() { print("base-deinit") }
}
class Derived : Base {
    Int y = 2
}
static Int main() {
    Derived d = new Derived()
    print("main")
    return 0
}`
	want := "main\nbase-deinit\n"
	got, code := compileAndRun(t, src)
	if got != want || code != 0 {
		t.Fatalf("输出 %q(code %d)，期望 %q", got, code, want)
	}
}

// S2 MEM-01：栈提升只影响分配（§2.7 许可，不改变语义）——
// 纯值类被判定为 stack-eligible，但当前 codegen 仍按 ARC 分配；
// 有 deinit / 捕获 self 的类不得栈候选。判定来自 sema 策略表。
func TestS2MEM01StackPolicyClassification(t *testing.T) {
	src := `
class ValueOnly { Int x = 1; }
class NeedsArc {
    Int x = 0;
    void deinit() { x = 1 }
}
static Int main() { return 0 }`
	u, diags := xfront.ParseUnit("t.x", src)
	if len(diags) != 0 {
		t.Fatalf("解析诊断：%v", diags)
	}
	res, sd := sema.AnalyzeWith("t.x", u)
	if len(sd) != 0 {
		t.Fatalf("语义诊断：%v", sd)
	}
	seen := map[string]sema.Strategy{}
	for _, s := range res.Strategies(u) {
		seen[s.Decl] = s
	}
	vo, ok := seen["ValueOnly"]
	if !ok || !vo.StackEligible || vo.Policy != "arc" {
		t.Fatalf("ValueOnly 策略=%+v，期望 stackEligible=true policy=arc", vo)
	}
	na, ok := seen["NeedsArc"]
	if !ok || na.StackEligible || !na.Deinit {
		t.Fatalf("NeedsArc 策略=%+v，期望 stackEligible=false deinit=true", na)
	}
}

// S2 MEM-01：struct 不进入 ARC/GC——sema 拒绝引用字段；codegen 不分配 struct
// （显式报错而非静默生成一个堆对象）。
func TestS2MEM01StructNotInARCGC(t *testing.T) {
	refSrc := `
class C { Int x = 1; }
struct S { C c; }
static Int main() { return 0 }`
	u, diags := xfront.ParseUnit("t.x", refSrc)
	if len(diags) != 0 {
		t.Fatalf("解析诊断：%v", diags)
	}
	if sd := sema.Analyze("t.x", u); len(sd) == 0 {
		t.Fatalf("struct 引用字段应被 sema 拒绝（S2 §3.2）")
	}

	valSrc := `
struct P { Int x = 1; }
static Int main() {
    P p = P()
    return p.x
}`
	u2, diags2 := xfront.ParseUnit("t.x", valSrc)
	if len(diags2) != 0 {
		t.Fatalf("解析诊断：%v", diags2)
	}
	if _, err := EmitC(u2); err == nil || !strings.Contains(err.Error(), "StructDecl 未支持") {
		t.Fatalf("codegen 应显式拒绝 struct（不得分配），err=%v", err)
	}
}

// S2 MEM-02：全 ARC 环的规避前提——引用环类被策略判定为 GC（§15.1 行 6），
// 非环类保持 ARC。这是「环由 GC 回收」的静态判定面。
func TestS2MEM02CycleClassIsGCByPolicy(t *testing.T) {
	src := `
class Node { Node next; }
class Plain { Int x = 1; }
static Int main() { return 0 }`
	u, diags := xfront.ParseUnit("t.x", src)
	if len(diags) != 0 {
		t.Fatalf("解析诊断：%v", diags)
	}
	res, sd := sema.AnalyzeWith("t.x", u)
	if len(sd) != 0 {
		t.Fatalf("语义诊断：%v", sd)
	}
	seen := map[string]sema.Strategy{}
	for _, s := range res.Strategies(u) {
		seen[s.Decl] = s
	}
	n, ok := seen["Node"]
	if !ok || n.Policy != "gc" || !n.RefCycle {
		t.Fatalf("Node 策略=%+v，期望 policy=gc refCycle=true", n)
	}
	p, ok := seen["Plain"]
	if !ok || p.Policy != "arc" {
		t.Fatalf("Plain 策略=%+v，期望 policy=arc", p)
	}
}
