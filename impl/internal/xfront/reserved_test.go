package xfront

import "testing"

// NEG-1.3a：6 个保留名不能作为标识符（S1 §1.3）。
func TestReservedNamesRejected(t *testing.T) {
	for _, name := range []string{"async", "await", "yield", "unsafe", "extern", "macro"} {
		src := "static Int main() {\n    Int " + name + " = 1\n    return 0\n}"
		if _, diags := ParseUnit("reserved.x", src); len(diags) == 0 {
			t.Errorf("保留名 `%s` 作局部变量名应被拒绝", name)
		}
		// 参数位置
		src = "static Int f(Int " + name + ") { return 0 }\nstatic Int main() { return 0 }"
		if _, diags := ParseUnit("reserved.x", src); len(diags) == 0 {
			t.Errorf("保留名 `%s` 作参数名应被拒绝", name)
		}
	}
}
