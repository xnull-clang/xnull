package xfront

import (
	"strings"
	"testing"
)

// unit 解析编译单元，要求零诊断，返回 S 表达式。
func unit(t *testing.T, src string) string {
	t.Helper()
	u, diags := ParseUnit("t.x", src)
	if len(diags) != 0 {
		t.Fatalf("不应有诊断：%v", render(diags))
	}
	return PrintUnit(u)
}

// unitFail 解析必须产生含指定码的诊断。
func unitFail(t *testing.T, src, code string) {
	t.Helper()
	_, diags := ParseUnit("t.x", src)
	for _, d := range diags {
		if d.Code == code {
			return
		}
	}
	t.Fatalf("期望诊断 %s，实际：%v", code, render(diags))
}

// ---------- §3.1 package ----------

func TestPackageDecl(t *testing.T) {
	if got := unit(t, "package com.acme.order"); got != "(unit (package com.acme.order))" {
		t.Errorf("包名：%s", got)
	}
	if got := unit(t, "package com.acme.order;"); got != "(unit (package com.acme.order))" {
		t.Errorf("分号可选：%s", got)
	}
	if got := unit(t, "// 注释\npackage a.b\n"); got != "(unit (package a.b))" {
		t.Errorf("注释后 package：%s", got)
	}
	// 默认包：省略 package
	if got := unit(t, "static Int main() { return 0 }"); got != "(unit (func static Int main (params) (block (return (int 0)))))" {
		t.Errorf("默认包 + main：%s", got)
	}
	// 空段拒绝
	unitFail(t, "package com..order", synExpect)
	// xdk 保留命名空间（§3.1、§3.5）
	unitFail(t, "package xdk.text", synXdkPackage)
}

// ---------- §3.2 import ----------

func TestImportDecl(t *testing.T) {
	src := "package com.acme.order\nimport xdk.text\nimport xdk.net.http\nimport com.acme.common.Thing as AcmeThing"
	want := "(unit (package com.acme.order)" +
		" (import xdk.text)" +
		" (import xdk.net.http)" +
		" (import com.acme.common.Thing as AcmeThing))"
	if got := unit(t, src); got != want {
		t.Errorf("导入矩阵：\n  got  %s\n  want %s", got, want)
	}
	// 导入必须在其他声明之前（文法顺序强制）
	unitFail(t, "static Int f() { return 0 }\nimport xdk.text", synExpect)
	// 通配符无语法形态（* 不是合法路径段）
	unitFail(t, "import xdk.text.*", synExpect)
}

// ---------- §4.1 顶层函数 ----------

func TestTopFuncs(t *testing.T) {
	// §4.1 示例：static 可写可省略
	src := "static Int add(final Int left, Int right) {\n    return left + right\n}"
	want := "(unit (func static Int add (params (param final Int left) (param Int right)) (block (return (binary + (ident left) (ident right))))))"
	if got := unit(t, src); got != want {
		t.Errorf("顶层函数：\n  got  %s\n  want %s", got, want)
	}
	if got := unit(t, "Int add(Int a) { return a }"); !strings.HasPrefix(got, "(unit (func Int add") {
		t.Errorf("static 省略：%s", got)
	}
	// void 返回
	if got := unit(t, "static void notify(final String message) { handle(message) }"); got !=
		"(unit (func static void notify (params (param final String message)) (block (expr (call (ident handle) (ident message))))))" {
		t.Errorf("void 函数：%s", got)
	}
	// 泛型参数
	if got := unit(t, "static T first<T>(T[] items) { return items[0] }"); got !=
		"(unit (func static T first <T> (params (param T[] items)) (block (return (index (ident items) (int 0))))))" {
		t.Errorf("泛型函数：%s", got)
	}
	// 重载形态（同名不同参）与相互递归（前向引用 §3.4）
	src = "static Int f(Int x) { return g(x) }\nstatic Int g(Int x) { return f(x) }"
	if got := unit(t, src); !strings.Contains(got, "(func static Int f") || !strings.Contains(got, "(func static Int g") {
		t.Errorf("重载/前向引用：%s", got)
	}
	// 可见性修饰符（§4.5）
	if got := unit(t, "private Int secret() { return 1 }"); !strings.HasPrefix(got, "(unit (func private") {
		t.Errorf("private：%s", got)
	}
	// 缺函数体拒绝（§4.1：必须有函数体）
	unitFail(t, "static Int add(Int a)", synExpect)
}

// ---------- §4.2 顶层字段 ----------

func TestTopFields(t *testing.T) {
	cases := []struct{ src, want string }{
		{"static Int nextId = 0", "(field static Int nextId (int 0))"},
		{"Int version = 1", "(field Int version (int 1))"},
		{"final Int build = 42", "(field final Int build (int 42))"},
		{"const Int limit = 10", "(field const Int limit (int 10))"},
		{"Int counter", "(field Int counter)"}, // 可变字段可省略初始化式（零值）
		{"const Int MAX = 1 << 10", "(field const Int MAX (binary << (int 1) (int 10)))"},
	}
	for _, c := range cases {
		if got := unit(t, c.src); got != "(unit "+c.want+")" {
			t.Errorf("`%s`\n  got  %s\n  want (unit %s)", c.src, got, c.want)
		}
	}
	// 注解前缀（附录 A Annotation = "@" Identifier [ "(" [ ArgList ] ")" ]）
	if got := unit(t, "@Deprecated\nInt old = 1"); !strings.Contains(got, "(@Deprecated)") {
		t.Errorf("注解：%s", got)
	}
	if got := unit(t, "@Range(0, 100)\nInt pct = 50"); !strings.Contains(got, "(@Range (int 0) (int 100))") {
		t.Errorf("带参注解：%s", got)
	}
	// 函数/字段歧义判定：同前缀下 `(` 归函数
	if got := unit(t, "Int value = 1\nInt make(Int x) { return x }"); !strings.Contains(got, "(field Int value") || !strings.Contains(got, "(func Int make") {
		t.Errorf("函数字段混排：%s", got)
	}
}

// ---------- §3.1/§4 组合：完整文件形态 ----------

func TestFullUnit(t *testing.T) {
	src := "package demo\nimport xdk.text\n\nstatic String greet(final String name) {\n    return \"hi\"\n}\n\nInt calls = 0"
	got := unit(t, src)
	want := "(unit (package demo) (import xdk.text)" +
		" (func static String greet (params (param final String name)) (block (return (string \"hi\"))))" +
		" (field Int calls (int 0)))"
	if got != want {
		t.Errorf("完整单元：\n  got  %s\n  want %s", got, want)
	}
}

// ---------- 类型声明：S2 范围，语法层明确拒绝 ----------

func TestTypeDeclDeferred(t *testing.T) {
	unitFail(t, "class Point { }", synTypeDecl)
	unitFail(t, "struct Pair { }", synTypeDecl)
	unitFail(t, "enum Color { }", synTypeDecl)
}

// ---------- 诊断不中断：多错误可报（对照 §1.7 风格） ----------

func TestUnitMultiDiags(t *testing.T) {
	_, diags := ParseUnit("t.x", "package xdk.bad\nimport a.b\nclass X { }\nstatic Int f() { return 0 }")
	if len(diags) < 2 {
		t.Fatalf("xdk 前缀与 class 至少两个诊断：%v", render(diags))
	}
	hasXdk, hasType := false, false
	for _, d := range diags {
		if d.Code == synXdkPackage {
			hasXdk = true
		}
		if d.Code == synTypeDecl {
			hasType = true
		}
	}
	if !hasXdk || !hasType {
		t.Fatalf("应同时报 SYN-111 与 SYN-110：%v", render(diags))
	}
}
