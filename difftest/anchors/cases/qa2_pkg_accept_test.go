package sema

// QA2 独立验收用例（M1-PKG-01）。不引用 pkg_test.go 的 helper，单独构造
// 依赖包与入口，覆盖台账 7 项验收要点 + §3.5 同类诊断。
// 本文件只存在于临时副本 /tmp/qa2-pkg01，不进入仓库。

import (
	"sort"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/diag"
	"xnull.dev/xnull/internal/xfront"
)

// ---------- helpers ----------

func qa2Dep(t *testing.T, path, src string) *Package {
	t.Helper()
	u, ds := xfront.ParseUnit(path+".x", src)
	if len(ds) != 0 {
		t.Fatalf("依赖包 %s 解析失败：%v", path, ds)
	}
	return NewPackage(strings.Split(path, "."), u)
}

func qa2Diags(t *testing.T, src string, deps ...*Package) []diag.Diagnostic {
	t.Helper()
	u, ds := xfront.ParseUnit("entry.x", src)
	if len(ds) != 0 {
		t.Fatalf("入口解析失败：%v", ds)
	}
	_, sd := AnalyzeWithDeps("entry.x", u, deps)
	return sd
}

func qa2SortedCodes(ds []diag.Diagnostic) []string {
	out := make([]string, 0, len(ds))
	for _, d := range ds {
		out = append(out, d.Code)
	}
	sort.Strings(out)
	return out
}

// qa2Want 断言诊断码集合完全相等（顺序无关，但数量必须一致）。
func qa2Want(t *testing.T, name, src string, want []string, deps ...*Package) {
	t.Helper()
	t.Run(name, func(t *testing.T) {
		got := qa2SortedCodes(qa2Diags(t, src, deps...))
		w := append([]string{}, want...)
		sort.Strings(w)
		if strings.Join(got, ",") != strings.Join(w, ",") {
			t.Fatalf("诊断码不匹配\n期望: %v\n实际: %v\n源:\n%s", w, got, src)
		}
	})
}

func qa2Text(t *testing.T) *Package {
	t.Helper()
	return qa2Dep(t, "lib.text", `package lib.text

String banner(String s) { return "[" + s + "]" }

static String shout(String s) { return banner(s) }

private String secret() { return "s" }

protected String guard() { return "g" }
`)
}

// qa2AB 两个包导出同名 X/Y，用于别名与歧义。
func qa2AB(t *testing.T) (*Package, *Package) {
	t.Helper()
	a := qa2Dep(t, "lib.a", "package lib.a\n\nInt X() { return 1 }\n\nInt Y() { return 2 }\n")
	b := qa2Dep(t, "lib.b", "package lib.b\n\nInt X() { return 3 }\n\nInt Y() { return 4 }\n")
	return a, b
}

// ---------- ① 符号导入 ----------

func TestQA2SymbolImport(t *testing.T) {
	text := qa2Text(t)
	types := qa2Dep(t, "lib.types", `package lib.types

class Widget {
    Int id = 0;
}

private class Hidden {
    Int id = 1;
}
`)

	qa2Want(t, "single-symbol-visible", `package app
import lib.text.banner
static Int main() {
    String b = banner("x")
    return 0
}`, nil, text)

	qa2Want(t, "sibling-symbol-hidden", `package app
import lib.text.banner
static Int main() {
    String c = shout("x")
    return 0
}`, []string{ResUndefined}, text)

	qa2Want(t, "symbol-missing", `package app
import lib.text.Nope
static Int main() { return 0 }
`, []string{ResNotFound}, text)

	qa2Want(t, "private-symbol", `package app
import lib.text.secret
static Int main() { return 0 }
`, []string{ResNotFound}, text)

	qa2Want(t, "protected-symbol", `package app
import lib.text.guard
static Int main() { return 0 }
`, []string{ResNotFound}, text)

	qa2Want(t, "class-symbol", `package app
import lib.types.Widget
static Int main() { return 0 }
`, nil, types)

	qa2Want(t, "private-class-symbol", `package app
import lib.types.Hidden
static Int main() { return 0 }
`, []string{ResNotFound}, types)
}

// ---------- ② 别名 ----------

func TestQA2Alias(t *testing.T) {
	a, b := qa2AB(t)
	text := qa2Text(t)

	qa2Want(t, "both-aliased", `package app
import lib.a.X as AX
import lib.b.X as BX
static Int main() { return AX() + BX() }
`, nil, a, b)

	qa2Want(t, "alias-replaces-original", `package app
import lib.a.X as AX
import lib.b.X as BX
static Int main() { return X() }
`, []string{ResUndefined}, a, b)

	qa2Want(t, "one-aliased-one-bare", `package app
import lib.a.X as AX
import lib.b.X
static Int main() { return AX() + X() }
`, nil, a, b)

	qa2Want(t, "needless-alias-single", `package app
import lib.text.banner as B
static Int main() { return 0 }
`, []string{ResNeedlessAlias}, text)

	qa2Want(t, "package-alias-forbidden", `package app
import lib.text as T
static Int main() { return 0 }
`, []string{ResNeedlessAlias}, text)

	qa2Want(t, "xdk-package-alias-forbidden", `package app
import xdk.text as T
static Int main() { return 0 }
`, []string{ResNeedlessAlias})

	qa2Want(t, "cross-source-alias-conflict", `package app
import lib.a.X as P
import lib.b.X as P
static Int main() { return 0 }
`, []string{ResAliasConflict}, a, b)

	// §3.3「导入别名必须唯一」：同一来源的两个不同符号也不得共用一个别名。
	// 两个符号各自都有同名冲突（X/Y 均在 lib.a/lib.b 中），所以 as 是必要的；
	// 唯一的错误是别名 P 被 lib.a.X 与 lib.a.Y 同时使用 → 期望 RES-103。
	qa2Want(t, "same-source-alias-conflict", `package app
import lib.a.X as P
import lib.b.X as BX
import lib.a.Y as P
import lib.b.Y as BY
static Int main() { return P() + BX() + BY() }
`, []string{ResAliasConflict}, a, b)

	qa2Want(t, "alias-vs-top-level", `package app
import lib.a.X as P
Int P = 1
static Int main() { return P }
`, []string{ResAliasConflict}, a)

	qa2Want(t, "alias-vs-builtin", `package app
import lib.a.X as Int
static Int main() { return 0 }
`, []string{ResAliasConflict}, a)
}

// ---------- ③ 同名消歧 / ④ 歧义 ----------

func TestQA2Disambiguation(t *testing.T) {
	a, b := qa2AB(t)
	text := qa2Text(t)
	p := qa2Dep(t, "lib.p", "package lib.p\n\nInt X() { return 1 }\n")
	q := qa2Dep(t, "lib.q", "package lib.q\n\nInt X() { return 2 }\n")
	c := qa2Dep(t, "lib.c", "package lib.c\n\nInt X() { return 3 }\n")

	qa2Want(t, "two-bare-same-name", `package app
import lib.a.X
import lib.b.X
static Int main() { return 0 }
`, []string{ResAmbiguousName}, a, b)

	qa2Want(t, "duplicate-package-import", `package app
import lib.text
import lib.text
static Int main() { return 0 }
`, nil, text)

	qa2Want(t, "duplicate-symbol-import", `package app
import lib.a.X
import lib.a.X
static Int main() { return X() }
`, nil, a)

	qa2Want(t, "top-level-shadow", `package app
import lib.text
String banner(String s) { return s }
static Int main() {
    print(banner("x"))
    return 0
}
`, nil, text)

	qa2Want(t, "package-imports-share-symbol", `package app
import lib.p
import lib.q
static Int main() { return 0 }
`, []string{ResAmbiguousName}, p, q)

	qa2Want(t, "three-sources-one-aliased", `package app
import lib.a.X
import lib.b.X
import lib.c.X as CX
static Int main() { return CX() }
`, []string{ResAmbiguousName}, a, b, c)

	// 别名 P 占用简单名 Y 后，再裸导入 lib.b.Y → 简单名冲突 RES-104。
	qa2Want(t, "alias-vs-bare-name", `package app
import lib.a.X as Y
import lib.b.X as BX
import lib.b.Y
static Int main() { return 0 }
`, []string{ResAmbiguousName}, a, b)
}

// ---------- ⑤ XDK ----------

func TestQA2Xdk(t *testing.T) {
	text := qa2Text(t)

	qa2Want(t, "use-without-import", `static Int main() {
    diagnose("x")
    return 0
}`, []string{ResXdkNotImport})

	qa2Want(t, "explicit-import", `import xdk.runtime
static Int main() {
    diagnose("x")
    return 0
}`, nil)

	qa2Want(t, "user-import-does-not-mask", `package app
import lib.text
static Int main() {
    diagnose("x")
    return 0
}`, []string{ResXdkNotImport}, text)

	qa2Want(t, "type-position-without-import", `static Int main() {
    Regex r
    return 0
}`, []string{ResXdkNotImport})

	qa2Want(t, "type-position-with-import", `import xdk.text
static Int main() {
    Regex r
    return 0
}`, nil)

	qa2Want(t, "xdk-symbol-import", `import xdk.runtime.diagnose
static Int main() {
    diagnose("x")
    return 0
}`, nil)

	qa2Want(t, "xdk-symbol-missing", `import xdk.runtime.nope
static Int main() { return 0 }
`, []string{ResNotFound})

	qa2Want(t, "xdk-unknown-package", `import xdk.nosuch
static Int main() { return 0 }
`, []string{ResNotFound})

	qa2Want(t, "xdk-root", `import xdk
static Int main() { return 0 }
`, []string{ResNotFound})

	qa2Want(t, "xdk-net-package", `import xdk.net
static Int main() { return 0 }
`, nil)

	// §3.2/§11.1：XDK 包路径可以多级，包名为末段；xdk.net.http 是合法包。
	qa2Want(t, "xdk-multilevel-package", `import xdk.net.http
static Int main() { return 0 }
`, nil)
}

// ---------- ⑥ 导入环 ----------

func TestQA2ImportCycle(t *testing.T) {
	twoA := qa2Dep(t, "lib.a", "package lib.a\n\nimport lib.b\n\nInt fa() { return 1 }\n")
	twoB := qa2Dep(t, "lib.b", "package lib.b\n\nimport lib.a\n\nInt fb() { return 2 }\n")

	qa2Want(t, "two-node", `package app
import lib.a
static Int main() { return fa() }
`, []string{ResImportCycle}, twoA, twoB)

	chainA := qa2Dep(t, "lib.a", "package lib.a\n\nimport lib.b\n\nInt fa() { return 1 }\n")
	chainB := qa2Dep(t, "lib.b", "package lib.b\n\nimport lib.c\n\nInt fb() { return 2 }\n")
	chainC := qa2Dep(t, "lib.c", "package lib.c\n\nimport lib.a\n\nInt fc() { return 3 }\n")

	qa2Want(t, "three-node", `package app
import lib.a
static Int main() { return fa() }
`, []string{ResImportCycle}, chainA, chainB, chainC)

	self := qa2Dep(t, "lib.a", "package lib.a\n\nimport lib.a\n\nInt fa() { return 1 }\n")
	qa2Want(t, "self-cycle", `package app
import lib.a
static Int main() { return fa() }
`, []string{ResImportCycle}, self)

	dagA := qa2Dep(t, "lib.a", "package lib.a\n\nimport lib.c\n\nInt fa() { return 1 }\n")
	dagB := qa2Dep(t, "lib.b", "package lib.b\n\nimport lib.c\n\nInt fb() { return 2 }\n")
	dagC := qa2Dep(t, "lib.c", "package lib.c\n\nInt fc() { return 3 }\n")
	qa2Want(t, "diamond-dag", `package app
import lib.a
import lib.b
static Int main() { return fa() + fb() }
`, nil, dagA, dagB, dagC)

	xdkA := qa2Dep(t, "lib.a", "package lib.a\n\nimport xdk.text\n\nInt fa() { return 1 }\n")
	qa2Want(t, "xdk-edge-not-cycle", `package app
import lib.a
static Int main() { return 0 }
`, nil, xdkA)
}

// ---------- ⑦ §3.5 同类：包不存在 / 默认包 / 私有 ----------

func TestQA2TargetRules(t *testing.T) {
	text := qa2Text(t)
	plain := qa2Dep(t, "lib.plain", "Int helper() { return 1 }\n")

	qa2Want(t, "package-missing", `package app
import lib.none
static Int main() { return 0 }
`, []string{ResNotFound})

	qa2Want(t, "default-package-import", `package app
import lib.plain
static Int main() { return 0 }
`, []string{ResDefaultPkg}, plain)

	qa2Want(t, "default-symbol-import", `package app
import lib.plain.helper
static Int main() { return 0 }
`, []string{ResDefaultPkg}, plain)

	qa2Want(t, "default-entry-imports-default-fragment", `import lib.plain
static Int main() { return helper() }
`, nil, plain)

	qa2Want(t, "private-use-after-package-import", `package app
import lib.text
static Int main() {
    print(secret())
    return 0
}
`, []string{ResUndefined}, text)
}

// ---------- ⑧ 诊断位置与确定性 ----------

func TestQA2DiagnosticPosition(t *testing.T) {
	src := `package app

import lib.none

static Int main() { return 0 }
`
	ds := qa2Diags(t, src)
	if len(ds) != 1 || ds[0].Code != ResNotFound {
		t.Fatalf("期望单条 RES-106，实际：%v", qa2SortedCodes(ds))
	}
	if ds[0].File != "entry.x" || ds[0].Line != 3 {
		t.Fatalf("诊断位置错误：file=%q line=%d（期望 entry.x:3）", ds[0].File, ds[0].Line)
	}
	if ds[0].Col < 1 || ds[0].Message == "" || ds[0].Hint == "" {
		t.Fatalf("诊断缺列/消息/提示：%+v", ds[0])
	}
}

func TestQA2Determinism(t *testing.T) {
	a, b := qa2AB(t)
	src := `package app
import lib.a.X
import lib.b.X
static Int main() { return X() }
`
	var first string
	for i := 0; i < 10; i++ {
		ds := qa2Diags(t, src, a, b)
		var parts []string
		for _, d := range ds {
			parts = append(parts, d.Code+"@"+itoa(d.Line)+":"+itoa(d.Col))
		}
		got := strings.Join(parts, "|")
		if i == 0 {
			first = got
			continue
		}
		if got != first {
			t.Fatalf("第 %d 次诊断不稳定：%q != %q", i+1, got, first)
		}
	}
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var b []byte
	for n > 0 {
		b = append([]byte{byte('0' + n%10)}, b...)
		n /= 10
	}
	return string(b)
}

// ---------- ⑨ 语法面（§3.1/§3.2/§3.5） ----------

func TestQA2SyntaxGuards(t *testing.T) {
	cases := []struct {
		name string
		src  string
		code string // 空表示只要解析失败即可
	}{
		{"xdk-prefix-package", "package xdk.app\n\nstatic Int main() { return 0 }\n", "SYN-111"},
		{"wildcard-import", "package app\nimport lib.*\nstatic Int main() { return 0 }\n", ""},
		{"import-after-declaration", "package app\nstatic Int main() { return 0 }\nimport lib.a\n", ""},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			_, ds := xfront.ParseUnit("entry.x", c.src)
			if len(ds) == 0 {
				t.Fatalf("期望解析失败，实际无诊断")
			}
			if c.code == "" {
				return
			}
			for _, d := range ds {
				if d.Code == c.code {
					return
				}
			}
			t.Fatalf("期望诊断 %s，实际：%v", c.code, qa2SortedCodes(ds))
		})
	}
}

// 补充复现：同一来源的别名与已绑定简单名冲突（§3.3 别名唯一）。
func TestQA2SameSourceAliasVsBare(t *testing.T) {
	a := qa2Dep(t, "lib.a", "package lib.a\n\nInt X() { return 1 }\n\nInt Y() { return 2 }\n")
	b := qa2Dep(t, "lib.b", "package lib.b\n\nInt X() { return 3 }\n")
	qa2Want(t, "alias-name-already-bound", `package app
import lib.a.X as Y
import lib.b.X as BX
import lib.a.Y
static Int main() { return 0 }
`, []string{ResAliasConflict}, a, b)
}
