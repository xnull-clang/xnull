package sema

import "testing"

// ---------- §3.5 导入诊断（XDK 注册表：S6 §2/§4） ----------

func TestImportNotFound(t *testing.T) {
	// 包不存在
	expectCode(t, "import xdk.nonexist\n\nstatic Int main() { return 0 }", ResNotFound)
	// 符号不存在（xdk.text 只定案 Regex）
	expectCode(t, "import xdk.text.Formatter\n\nstatic Int main() { return 0 }", ResNotFound)
	// 合法包与符号
	expectNone(t, "import xdk.text\n\nstatic Int main() { return 0 }")
	expectNone(t, "import xdk.text.Regex\n\nstatic Int main() { return 0 }")
}

func TestXdkNotImported(t *testing.T) {
	// 使用 XDK 符号但未导入 → RES-105（§3.5：XDK 包未显式导入）
	expectCode(t, "static Int main() {\n    diagnose(\"x\")\n    return 0\n}", ResXdkNotImport)
	expectCode(t, "static Int main() {\n    Mutex<Mutex>? m\n    return 0\n}", ResXdkNotImport)
	// 导入后可用
	expectNone(t, "import xdk.runtime\n\nstatic Int main() {\n    diagnose(\"x\")\n    return 0\n}")
}

func TestAliasRules(t *testing.T) {
	// 非冲突场景使用 as → RES-107（§3.5：别名只用于消歧）
	expectCode(t, "import xdk.text.Regex as Pattern\n\nstatic Int main() { return 0 }", ResNeedlessAlias)
	// 别名冲突 → RES-103（同名别名指向两个符号）
	expectCode(t, "import xdk.text.Regex as P\nimport xdk.tasks.Context as P\n\nstatic Int main() { return 0 }",
		ResAliasConflict)
	// 各自合法导入共存
	expectNone(t, "import xdk.text\nimport xdk.sync\n\nstatic Int main() { return 0 }")
}

// 导入环与默认包符号跨包导入需要多包编译单元（工程清单模式），
// RES-104 未消歧简单名需要注册表中存在同名符号（当前 S6 定案符号无重名）——
// 二者属多包切片验收，此处不构造假注册（PKG-01 维持"部分"的理由）。
