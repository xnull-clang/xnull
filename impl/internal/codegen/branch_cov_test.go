package codegen

import (
	"strings"
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// M6-B0-05 未覆盖分支 1/2：字面量目标类型不支持时给出显式诊断（不得 panic）。
func TestContainerLiteralTargetErrors(t *testing.T) {
	s := &scope{g: &gen{cs: newContainers()}, locals: map[string]string{}}
	// 空数组字面量对 Map 是合法的（S3-01 容器 GC 化），用非空字面量触发出错分支。
	lit := &xfront.ArrayLit{Elems: []xfront.Expr{&xfront.IntLitExpr{Text: "1", Base: 10}}}
	if _, _, err := s.arrayLit(lit, "xn_map_s_i"); err == nil ||
		!strings.Contains(err.Error(), "数组字面量目标类型") {
		t.Fatalf("数组字面量目标类型分支应显式报错，实际：%v", err)
	}
	if _, _, err := s.mapLit(&xfront.MapLit{}, "xn_arr_i"); err == nil ||
		!strings.Contains(err.Error(), "Map 字面量目标类型") {
		t.Fatalf("Map 字面量目标类型分支应显式报错，实际：%v", err)
	}
}

// M6-B0-05 未覆盖分支 3：String 成员接收者支持下标读（a[0].length()）。
func TestStringMemberIndexReceiver(t *testing.T) {
	got, code := compileAndRun(t, `static Int main() {
    String[] a = ["abc", "de"]
    print(a[0].length())
    print(a[1].length())
    return 0
}`)
	if code != 0 || got != "3\n2\n" {
		t.Fatalf("got=%q code=%d，期望 3/2", got, code)
	}
}
