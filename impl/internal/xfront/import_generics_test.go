package xfront

// NEG-01 / GEN-01 跨域修复的 xfront 回归用例。
//   - NEG-01 neg-3.2-02：包导入不得使用 as 别名（§3.2）→ SYN-112
//   - GEN-01 B1：多类型参数 `<T, U>`（§8.1）解析
//   - GEN-01 B1b：嵌套类型实参 `>>` 拆分（附录 A TypeArgList）
//   - 回归：移位 `>>` 语义不变

import "testing"

func TestImportPackageAliasRejected(t *testing.T) {
	_, diags := ParseUnit("t.x", "package app\n\nimport P as Q\n\nstatic Int main() { return 0 }")
	if !hasCode(diags, synPackageAlias) {
		t.Fatalf("包别名应报 %s，实际：%v", synPackageAlias, codes(diags))
	}
	// 符号导入别名（路径 ≥2 段）不受影响（消歧合法性由 sema 判定）
	if _, diags := ParseUnit("t.x", "import com.acme.Thing as AcmeThing\n\nstatic Int main() { return 0 }"); len(diags) != 0 {
		t.Fatalf("符号导入别名不应有解析诊断：%v", codes(diags))
	}
}

func TestGenericMultiTypeParams(t *testing.T) {
	u, diags := ParseUnit("t.x", "static T pick<T, U>(T a, U b) { return a }\n\nstatic Int main() { return 0 }")
	if len(diags) != 0 {
		t.Fatalf("多类型参数不应有解析诊断：%v", codes(diags))
	}
	var fn *TopFunc
	for _, d := range u.Decls {
		if f, ok := d.(*TopFunc); ok && f.Name == "pick" {
			fn = f
		}
	}
	if fn == nil {
		t.Fatal("未解析出 pick 函数")
	}
	if len(fn.TypePars) != 2 || fn.TypePars[0] != "T" || fn.TypePars[1] != "U" {
		t.Fatalf("类型参数应为 [T U]，实际 %v", fn.TypePars)
	}
}

func TestNestedTypeArgs(t *testing.T) {
	cases := []string{
		"static Int f() { return g<List<Int>>(x) }",
		"static Int f() { Map<String, List<Int>> m = [:]\nreturn 0 }",
		"static Int f() { return h<Map<String, List<Int>>>(m) }",
	}
	for _, src := range cases {
		if _, diags := ParseUnit("t.x", src); len(diags) != 0 {
			t.Fatalf("嵌套泛型不应有解析诊断（%s）：%v", src, codes(diags))
		}
	}
	// 移位语义不变
	e, diags := ParseExpr("t.x", "a >> b")
	if len(diags) != 0 {
		t.Fatalf("移位不应有诊断：%v", codes(diags))
	}
	if got := PrintExpr(e); got != "(binary >> (ident a) (ident b))" {
		t.Fatalf("移位解析不符：%s", got)
	}
}
