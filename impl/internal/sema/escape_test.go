package sema

import (
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

func escapeOf(t *testing.T, src string) map[string]string {
	t.Helper()
	u, pd := xfront.ParseUnit("e.x", src)
	if len(pd) != 0 {
		t.Fatalf("解析诊断：%v", pd)
	}
	res, sd := AnalyzeWith("e.x", u)
	if len(sd) != 0 {
		t.Fatalf("语义诊断：%v", sd)
	}
	out := map[string]string{}
	for _, e := range res.Escapes(u) {
		out[e.Func] = e.Escape
	}
	return out
}

// S3-03：none/return/other 场景。
func TestS3EscapeClassification(t *testing.T) {
	src := `
class V { Int x = 1; }
class D { Int x = 1; void deinit() { } }

static V make() { return new V() }
static Int take(V v) { return 0 }
static Int main() {
    V local = new V()
    V other = new V()
    take(new V())
    var f = () -> new V()
    D d = new D()
    return local.x
}`
	got := escapeOf(t, src)
	if got["make"] != "return" {
		t.Fatalf("make 应 return，实际 %v", got)
	}
	if got["main"] != "other" { // main 内 take(new V()) 覆盖为 other
		t.Fatalf("main 应 other（含参数传递），实际 %v", got)
	}
}

func TestS3EscapeLocalAndField(t *testing.T) {
	src := `
class V { Int x = 1; }
class H { V v; H() { self.v = new V() } }
static Int local() {
    V v = new V()
    return v.x
}`
	got := escapeOf(t, src)
	if got["local"] != "none" {
		t.Fatalf("local 应 none，实际 %v", got)
	}
	if got["H.<ctor>"] != "other" {
		t.Fatalf("字段赋值应 other，实际 %v", got)
	}
}

func TestS3EscapeClosure(t *testing.T) {
	src := `
class V { Int x = 1; }
static Int main() {
    var f = () -> new V()
    return 0
}`
	got := escapeOf(t, src)
	if got["main"] != "other" {
		t.Fatalf("闭包内 new 应 other，实际 %v", got)
	}
}
