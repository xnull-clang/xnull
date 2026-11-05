package diag

import "testing"

func TestRenderWithSnippet(t *testing.T) {
	d := Diagnostic{
		File: "xnull.project", Line: 12, Col: 3, Code: "XPD-204",
		Message: `unknown field "optonal" in dependency`,
		Snippet: "  optonal = true",
		Width:   7,
		Hint:    "未知字段；可用字段：version, scope, optional, exclusions",
	}
	want := "xnull.project:12:3: error[XPD-204]: unknown field \"optonal\" in dependency\n" +
		" 12 |   optonal = true\n" +
		"    |   ^^^^^^^ 未知字段；可用字段：version, scope, optional, exclusions"
	if got := d.String(); got != want {
		t.Fatalf("渲染不符：\n--- got ---\n%s\n--- want ---\n%s", got, want)
	}
}

func TestRenderWithoutSnippet(t *testing.T) {
	d := Diagnostic{File: "xnull", Line: 1, Col: 1, Code: "CLI-003", Message: "找不到 xnull.project", Hint: "在进程内向上查找清单"}
	want := "xnull:1:1: error[CLI-003]: 找不到 xnull.project\n  在进程内向上查找清单"
	if got := d.String(); got != want {
		t.Fatalf("渲染不符：\n%s", got)
	}
}

func TestWidthDefault(t *testing.T) {
	d := Diagnostic{File: "a", Line: 3, Col: 1, Code: "XPD-101", Message: "x", Snippet: "y", Width: 0}
	if got := d.String(); got[len(got)-1:] != "^" {
		t.Fatalf("宽度缺省应至少一个插入符：%q", got)
	}
}
