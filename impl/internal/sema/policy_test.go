package sema

import (
	"reflect"
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// ---------- M2.5.2：内存策略判定（S2 §15.1） ----------

// strategiesOf 解析+分析后返回判定结果。
func strategiesOf(t *testing.T, src string) []Strategy {
	t.Helper()
	u, pdiags := xfront.ParseUnit("t.x", src)
	if len(pdiags) != 0 {
		t.Fatalf("解析不应有诊断：%v", pdiags)
	}
	res, sd := AnalyzeWith("t.x", u)
	if len(sd) != 0 {
		t.Fatalf("不应有语义诊断：%v", sd)
	}
	return res.Strategies(u)
}

// TestPolicyTable 按 §15.1 判定表逐行验证。
func TestPolicyTable(t *testing.T) {
	got := strategiesOf(t, `
class Pure {
    Int x = 0;
    Bool ok = true;
}

class WithAny {
    Any payload;
}

class WithProto {
    Runnable r;
}

protocol Runnable {
    void run();
}

class WithResult {
    Result<Int, String> state;
}

class Node {
    Node? next;
}

class WithDeinit {
    Int x = 0;

    void deinit() {
    }
}

class WithCapture {
    Int x = 0;

    Int delayed() {
        var f = () -> { return self.x; };
        return f();
    }
}

struct Val {
    Int v = 0;
}

enum Color { Red, Green }

enum Status {
    Ready(0);

    final Int code;

    Status(Int code) {
        self.code = code;
    }
}

static Int main() { return 0 }`)
	want := []Strategy{
		{Decl: "Color", Kind: "enum", Policy: "value", Escape: "n/a", Rule: 3},
		{Decl: "Node", Kind: "class", Policy: "gc", RefCycle: true, Escape: "n/a", Rule: 6},
		{Decl: "Pure", Kind: "class", Policy: "arc", StackEligible: true, Escape: "n/a", Rule: 8},
		{Decl: "Runnable", Kind: "protocol", Policy: "na-gc", Escape: "n/a", Rule: 2},
		{Decl: "Status", Kind: "enum", DataEnum: true, Policy: "gc", Escape: "n/a", Rule: 4},
		{Decl: "Val", Kind: "struct", Policy: "value", Escape: "n/a"},
		{Decl: "WithAny", Kind: "class", Policy: "gc", Escape: "n/a", Rule: 5},
		{Decl: "WithCapture", Kind: "class", Policy: "arc", SelfCaptured: true, Escape: "n/a", Rule: 7},
		{Decl: "WithDeinit", Kind: "class", Policy: "arc", Deinit: true, Escape: "n/a", Rule: 7},
		{Decl: "WithProto", Kind: "class", Policy: "gc", Escape: "n/a", Rule: 5},
		{Decl: "WithResult", Kind: "class", Policy: "gc", Escape: "n/a", Rule: 5},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("判定不符：\n got  %+v\n want %+v", got, want)
	}
}

// TestPolicyDeterministic 同一 AST 两次判定逐字段相等（DET-01 输入面）。
func TestPolicyDeterministic(t *testing.T) {
	src := `
class A {
    Int x = 0;
}

class B : A {
    String name;
}

class C {
    B b;
}

static Int main() { return 0 }`
	s1 := strategiesOf(t, src)
	s2 := strategiesOf(t, src)
	if !reflect.DeepEqual(s1, s2) {
		t.Fatalf("两次判定不一致（DET-01）：\n%+v\n%+v", s1, s2)
	}
	// C 持有 B（B 无引用字段）→ 无环 → 行 9 ARC
	for _, s := range s1 {
		if s.Decl == "C" && (s.Policy != "arc" || s.Rule != 9) {
			t.Fatalf("C 应为行 9 ARC：%+v", s)
		}
	}
}

// TestPolicySelfCaptureScan 捕获扫描：非闭包位置的 self 不计捕获。
func TestPolicySelfCaptureScan(t *testing.T) {
	got := strategiesOf(t, `
class Plain {
    Int x = 0;

    Int get() {
        return self.x;
    }
}

static Int main() { return 0 }`)
	for _, s := range got {
		if s.Decl == "Plain" && (s.SelfCaptured || s.Rule != 8) {
			t.Fatalf("Plain 未捕获 self，应行 8：%+v", s)
		}
	}
}

// TestPolicyStructSelfCapture 结构体闭包捕获 self 被拒绝（§3.1）。
func TestPolicyStructSelfCapture(t *testing.T) {
	u, pdiags := xfront.ParseUnit("t.x", `
struct S {
    Int v = 0;

    Int delayed() {
        var f = () -> { return self.v; };
        return f();
    }
}

static Int main() { return 0 }`)
	if len(pdiags) != 0 {
		t.Fatalf("解析不应有诊断：%v", pdiags)
	}
	sd := Analyze("t.x", u)
	found := false
	for _, d := range sd {
		if d.Code == TyStructVal {
			found = true
		}
	}
	if !found {
		t.Fatalf("应报 TY-204（结构体捕获 self）：%v", sd)
	}
}

// TestPolicyInternalAnnos 源码使用 @arc/@gc 被拒绝（§15.1.2 / MEM-01）。
func TestPolicyInternalAnnos(t *testing.T) {
	expectCode(t, "@arc\nclass A {\n}\n\nstatic Int main() { return 0 }", TyModifier)
	expectCode(t, "@gc\nclass A {\n}\n\nstatic Int main() { return 0 }", TyModifier)
}
