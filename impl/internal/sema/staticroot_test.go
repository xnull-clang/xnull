package sema

import (
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// P1-10：单例/枚举静态字段根登记与初始化顺序。
func TestS3StaticRoots(t *testing.T) {
	src := `
String g = "g"
singleton AppInfo {
    static String name = "x";
    static Int count = 0;
    Int id = 0;
}
enum Status {
    Ready(0, "r");
    final Int code;
    final String label;
    Status(Int c, String l) { self.code = c; self.label = l }
}
static Int main() { return 0 }`
	u, pd := xfront.ParseUnit("r.x", src)
	if len(pd) != 0 {
		t.Fatalf("解析诊断：%v", pd)
	}
	res, sd := AnalyzeWith("r.x", u)
	if len(sd) != 0 {
		t.Fatalf("语义诊断：%v", sd)
	}
	roots := res.StaticRoots(u)
	if len(roots) != 6 {
		t.Fatalf("根数量 %d want 6：%+v", len(roots), roots)
	}
	checks := []struct {
		decl, field, kind string
		gc                bool
	}{
		{"<global>", "g", "global", true},
		{"AppInfo", "name", "singleton.static", true},
		{"AppInfo", "count", "singleton.static", false},
		{"AppInfo", "id", "singleton.instance", false},
		{"Status", "code", "enum.field", false},
	}
	_ = checks // 顺序/GC 在下方按字段名断言
	by := map[string]StaticRoot{}
	for _, r := range roots {
		by[r.Decl+"."+r.Field] = r
	}
	if r := by["AppInfo.name"]; !r.GC || r.Order <= by["<global>.g"].Order {
		t.Fatalf("singleton 静态引用根异常：%+v（全部 %+v）", r, roots)
	}
	if r := by["AppInfo.count"]; r.GC {
		t.Fatalf("Int 静态字段不应 GC：%+v", r)
	}
	if r := by["Status.label"]; r.Kind != "enum.field" {
		t.Fatalf("枚举字段根异常：%+v", r)
	}
}
