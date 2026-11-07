package sema

import (
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// S3-03pre：容器中介引用环 + 逃逸分类接口。
func TestS3ContainerCycleAndEscape(t *testing.T) {
	src := `
class N { List<N> xs = []; }
class H { List<Int> xs = []; }
class V { Int x = 1; }
class D { Int x = 1; void deinit() { } }
class G { Any a; }
static Int main() { return 0 }`
	u, pd := xfront.ParseUnit("p.x", src)
	if len(pd) != 0 {
		t.Fatalf("解析诊断：%v", pd)
	}
	res, sd := AnalyzeWith("p.x", u)
	if len(sd) != 0 {
		t.Fatalf("语义诊断：%v", sd)
	}
	got := map[string]Strategy{}
	for _, s := range res.Strategies(u) {
		got[s.Decl] = s
	}
	if n := got["N"]; n.Policy != "gc" || !n.RefCycle {
		t.Fatalf("容器中介环 N 应为 gc+RefCycle，实际 %+v", n)
	}
	if h := got["H"]; h.Policy != "gc" {
		t.Fatalf("List 字段应按 GC，实际 %+v", h)
	}
	if v := got["V"]; v.Escape != "none" || !v.StackEligible {
		t.Fatalf("V 应栈候选 none，实际 %+v", v)
	}
	if d := got["D"]; d.Escape != "return" {
		t.Fatalf("D 应 return/ARC，实际 %+v", d)
	}
	if g := got["G"]; g.Escape != "other" {
		t.Fatalf("G 应 other/GC，实际 %+v", g)
	}
}
