package sema

import (
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// S3-02 sema 可见性：GC 根来源可在策略判定中看到。
func TestS3GCRootVisibility(t *testing.T) {
	src := `
singleton AppInfo { String name = "x"; }
enum Color { Red, Green }
enum Status { Ready(0); final Int c; Status(Int x) { self.c = x } }
class WithString { String s = ""; }
class WithSB { StringBuilder b = StringBuilder(); }
class Node { List<Node> kids = []; }
static Int main() { return 0 }`
	u, pd := xfront.ParseUnit("r.x", src)
	if len(pd) != 0 {
		t.Fatalf("解析诊断：%v", pd)
	}
	res, sd := AnalyzeWith("r.x", u)
	if len(sd) != 0 {
		t.Fatalf("语义诊断：%v", sd)
	}
	got := map[string]Strategy{}
	for _, s := range res.Strategies(u) {
		got[s.Decl] = s
	}
	if s := got["AppInfo"]; s.Kind != "singleton" || s.Policy != "gc" {
		t.Fatalf("singleton 应为 GC 根，实际 %+v", s)
	}
	if s := got["Status"]; s.Kind != "enum" || !s.DataEnum || s.Policy != "gc" {
		t.Fatalf("数据枚举应为 GC，实际 %+v", s)
	}
	if s := got["Color"]; s.Policy != "value" {
		t.Fatalf("简单枚举应为 value，实际 %+v", s)
	}
	if s := got["WithString"]; s.Policy != "gc" || s.Rule != 5 {
		t.Fatalf("String 字段应按 GC，实际 %+v", s)
	}
	if s := got["WithSB"]; s.Policy != "gc" {
		t.Fatalf("StringBuilder 字段应按 GC，实际 %+v", s)
	}
	if s := got["Node"]; s.Policy != "gc" || !s.RefCycle {
		t.Fatalf("容器中介环应 gc+cycle，实际 %+v", s)
	}
}
