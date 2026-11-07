package sema

import (
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// S4-03：E 不得嵌套 Result；@mustUse 强度矩阵。
func TestS4EAndMustUse(t *testing.T) {
	expectCode(t, `
static Int main() {
    Result<Int, Result<Int, String>> r = Ok(1)
    return 0
}`, ErResultCtor)

	src := `
static Result<Int, String> g() { return Ok(1) }
static Int main() { g(); return 0 }`
	u, pd := xfront.ParseUnit("m.x", src)
	if len(pd) != 0 {
		t.Fatalf("解析诊断：%v", pd)
	}
	if _, ds := AnalyzeWithOptions("m.x", u, Options{MustUse: "error"}); len(ds) == 0 {
		t.Fatalf("error 强度应报 ERR-201")
	}
	if _, ds := AnalyzeWithOptions("m.x", u, Options{MustUse: "warn"}); len(ds) != 0 {
		t.Fatalf("warn 强度不应产生硬错误：%v", ds)
	}
	if _, ds := AnalyzeWithOptions("m.x", u, Options{MustUse: "off"}); len(ds) != 0 {
		t.Fatalf("off 强度不应产生诊断：%v", ds)
	}
}
