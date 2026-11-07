package sema

import (
	"strings"
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// ---------- PKG-01（S1 §3.2/§3.4/§3.5）：包导入 / 符号导入 / 别名 / 歧义 / 导入环 ----------

// depPkg 解析一个依赖包源文本并构造符号表。
func depPkg(t *testing.T, path, src string) *Package {
	t.Helper()
	u, ds := xfront.ParseUnit(path+".x", src)
	if len(ds) != 0 {
		t.Fatalf("依赖包 %s 解析诊断：%v", path, ds)
	}
	return NewPackage(strings.Split(path, "."), u)
}

// codesWithDeps 分析入口单元并返回诊断码集合。
func codesWithDeps(t *testing.T, src string, deps ...*Package) []string {
	t.Helper()
	u, ds := xfront.ParseUnit("entry.x", src)
	if len(ds) != 0 {
		t.Fatalf("入口解析诊断：%v", ds)
	}
	_, sd := AnalyzeWithDeps("entry.x", u, deps)
	out := make([]string, 0, len(sd))
	for _, d := range sd {
		out = append(out, d.Code)
	}
	return out
}

func wantNoneWithDeps(t *testing.T, src string, deps ...*Package) {
	t.Helper()
	if got := codesWithDeps(t, src, deps...); len(got) != 0 {
		t.Fatalf("不应有语义诊断，实际：%v（源：%s）", got, src)
	}
}

func wantCodeWithDeps(t *testing.T, src, code string, deps ...*Package) {
	t.Helper()
	for _, c := range codesWithDeps(t, src, deps...) {
		if c == code {
			return
		}
	}
	t.Fatalf("期望诊断 %s，实际：%v（源：%s）", code, codesWithDeps(t, src, deps...), src)
}

func textDep(t *testing.T) *Package {
	t.Helper()
	return depPkg(t, "lib.text", `package lib.text

String banner(String s) { return "[" + s + "]" }

static String shout(String s) { return banner(s) }

private String secret() { return "s" }

protected String guard() { return "g" }
`)
}

// ---------- ① 包导入 ----------

func TestPkgImport(t *testing.T) {
	text := textDep(t)

	// import P 引入 P 的全部公开顶层符号（§3.2）
	wantNoneWithDeps(t, `package app

import lib.text

static Int main() {
    String b = banner("x")
    String c = shout(b)
    return 0
}`, text)

	// 包导入不绑定包命名空间别名（§3.2）
	wantCodeWithDeps(t, `package app

import lib.text

static Int main() {
    String b = text.banner("x")
    return 0
}`, ResUndefined, text)

	// 顶层 private / protected 不可导入（§3.1/§3.5）
	wantCodeWithDeps(t, `package app
import lib.text
static Int main() {
    String s = secret()
    return 0
}`, ResUndefined, text)
	wantCodeWithDeps(t, `package app
import lib.text
static Int main() {
    String s = guard()
    return 0
}`, ResUndefined, text)

	// 当前包顶层声明遮蔽同名导入（§3.3），不是歧义
	wantNoneWithDeps(t, `package app

import lib.text

String banner(String s) { return s }

static Int main() {
    String b = banner("x")
    return 0
}`, text)
}

// ---------- ② 符号导入 ----------

func TestSymbolImport(t *testing.T) {
	text := textDep(t)

	// import P.S 只引入 S（§3.2）
	wantNoneWithDeps(t, `package app

import lib.text.banner

static Int main() {
    String b = banner("x")
    return 0
}`, text)

	// 同包其他符号不因符号导入而可见
	wantCodeWithDeps(t, `package app

import lib.text.banner

static Int main() {
    String c = shout("x")
    return 0
}`, ResUndefined, text)

	// 符号不存在（§3.5）
	wantCodeWithDeps(t, `package app

import lib.text.Nope

static Int main() { return 0 }
`, ResNotFound, text)

	// 私有符号不能被符号导入（§3.5）
	wantCodeWithDeps(t, `package app

import lib.text.secret

static Int main() { return 0 }
`, ResNotFound, text)
}

// ---------- ③ 同名消歧别名 ----------

func TestAliasDisambiguation(t *testing.T) {
	a := depPkg(t, "lib.a", "package lib.a\n\nInt Thing(Int x) { return x }\n")
	b := depPkg(t, "lib.b", "package lib.b\n\nInt Thing(Int x) { return x + 1 }\n")

	// 两处同名符号各自用 as 消歧 → 合法（§3.2）
	wantNoneWithDeps(t, `package app

import lib.a.Thing as AThing
import lib.b.Thing as BThing

static Int main() {
    return AThing(1) + BThing(2)
}`, a, b)

	// 别名替换原简单名：原简单名不可再裸用
	wantCodeWithDeps(t, `package app

import lib.a.Thing as AThing
import lib.b.Thing as BThing

static Int main() {
    return Thing(1)
}`, ResUndefined, a, b)

	// 一处消歧、一处裸导入 → 合法；裸导入的简单名仍可用
	wantNoneWithDeps(t, `package app

import lib.a.Thing as AThing
import lib.b.Thing

static Int main() {
    return AThing(1) + Thing(2)
}`, a, b)
}

// ---------- ④ 非冲突别名被拒绝 ----------

func TestNeedlessAliasRejected(t *testing.T) {
	text := textDep(t)

	// 单一符号导入使用 as → RES-107（§3.2）
	wantCodeWithDeps(t, `package app

import lib.text.banner as B

static Int main() { return 0 }
`, ResNeedlessAlias, text)

	// 包导入不得使用 as 包别名（§3.2）→ RES-107
	wantCodeWithDeps(t, `package app

import lib.text as T

static Int main() { return 0 }
`, ResNeedlessAlias, text)

	// XDK 包别名同样拒绝（§3.2）
	expectCode(t, `import xdk.text as T

static Int main() { return 0 }
`, ResNeedlessAlias)

	// 别名冲突：同一别名指向两个符号（§3.5）→ RES-103
	a := depPkg(t, "lib.a", "package lib.a\n\nInt Thing(Int x) { return x }\n")
	b := depPkg(t, "lib.b", "package lib.b\n\nInt Thing(Int x) { return x }\n")
	wantCodeWithDeps(t, `package app

import lib.a.Thing as P
import lib.b.Thing as P

static Int main() { return 0 }
`, ResAliasConflict, a, b)

	// 别名不得与当前文件顶层声明冲突（§3.3）→ RES-103
	wantCodeWithDeps(t, `package app

import lib.a.Thing as P

Int P = 1

static Int main() { return P }
`, ResAliasConflict, a)

	// 别名不得与预定义类型名冲突（§3.3）→ RES-103
	wantCodeWithDeps(t, `package app

import lib.a.Thing as Int

static Int main() { return 0 }
`, ResAliasConflict, a)
}

// ---------- ⑤ 简单名歧义 ----------

func TestAmbiguousSimpleName(t *testing.T) {
	a := depPkg(t, "lib.a", "package lib.a\n\nInt Thing(Int x) { return x }\n")
	b := depPkg(t, "lib.b", "package lib.b\n\nInt Thing(Int x) { return x + 1 }\n")

	// 两个导入提供同一简单名且未消歧 → RES-104（§3.2/§3.5）
	wantCodeWithDeps(t, `package app

import lib.a.Thing
import lib.b.Thing

static Int main() { return Thing(1) }
`, ResAmbiguousName, a, b)

	// 重复导入同一包/同一符号允许，不产生新绑定（§3.2）
	wantNoneWithDeps(t, `package app

import lib.a.Thing
import lib.a.Thing

static Int main() { return Thing(1) }
`, a)
	expectNone(t, `import xdk.text
import xdk.text

static Int main() { return 0 }
`)
}

// ---------- ⑥ XDK 未导入 ----------

func TestXdkNotImportedStrict(t *testing.T) {
	// 未导入即使用 XDK 静态入口 → RES-105（§3.2/§3.5）
	expectCode(t, `static Int main() {
    diagnose("x")
    return 0
}`, ResXdkNotImport)

	// 显式导入后可用
	expectNone(t, `import xdk.runtime

static Int main() {
    diagnose("x")
    return 0
}`)

	// 其他（用户包）导入不能掩盖 XDK 未导入
	text := textDep(t)
	wantCodeWithDeps(t, `package app

import lib.text

static Int main() {
    diagnose("x")
    return 0
}`, ResXdkNotImport, text)
}

// ---------- ⑦ 导入环 ----------

func TestImportCycle(t *testing.T) {
	a := depPkg(t, "lib.a", "package lib.a\n\nimport lib.b\n\nInt fa() { return 1 }\n")
	b := depPkg(t, "lib.b", "package lib.b\n\nimport lib.a\n\nInt fb() { return 2 }\n")

	// 入口 → lib.a → lib.b → lib.a → RES-108（§3.4）
	wantCodeWithDeps(t, `package app

import lib.a

static Int main() { return fa() }
`, ResImportCycle, a, b)

	// 无环链：lib.a → lib.c 合法
	c := depPkg(t, "lib.c", "package lib.c\n\nInt fc() { return 3 }\n")
	a2 := depPkg(t, "lib.a", "package lib.a\n\nimport lib.c\n\nInt fa() { return fc() }\n")
	wantNoneWithDeps(t, `package app

import lib.a

static Int main() { return fa() }
`, a2, c)
}

// ---------- 包不存在 / 默认包 ----------

func TestImportTargetRules(t *testing.T) {
	// 包不存在 → RES-106（§3.5）
	wantCodeWithDeps(t, `package app

import lib.none

static Int main() { return 0 }
`, ResNotFound)

	// 默认包不能被其他包导入（§3.1/§3.5）→ RES-111
	plain := depPkg(t, "lib.plain", "Int helper() { return 1 }\n")
	wantCodeWithDeps(t, `package app

import lib.plain

static Int main() { return helper() }
`, ResDefaultPkg, plain)

	// 默认包入口导入默认包文件：同一编译单元分片，允许（examples/multi 形态）
	wantNoneWithDeps(t, `import lib.plain

static Int main() { return helper() }
`, plain)
}
