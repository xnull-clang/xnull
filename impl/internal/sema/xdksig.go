package sema

import (
	"fmt"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

// S6-01：XDK 8 包的语言面内建签名（S6 v1.1.0 §4）。
//
// 设计边界：
//   - 这里登记的是**语言面公开 API**，不依赖 codegen 的 `.xfb` 注入；
//     `xnull check` 与 `xnull build` 使用同一张表。
//   - S6 §4.5/§4.6 只给出能力类别、未冻结具体方法名的 API（collections 算法、
//     Regex 动态编译、net socket）不猜签名：包内保留名 + 成员调用走 TY-229
//     显式诊断，避免“静默放行/假装可用”。
//   - 绑定层尚未落地的已定案 API（env/资源读取/parse）仍给出签名，供 check 先
//     行验收；运行时实现由 S6-02..05 接。

// xdkFuncSig 是 XDK 顶层函数签名。
// params/ret 使用 sema 的类型串（与 texpr.key 同构）。
type xdkFuncSig struct {
	pkg      string
	params   []string
	ret      string
	blocking bool // 默认可阻塞/异步形态：XDK-02 第 3 条要求首参 Context
}

// xdkFuncSigs 是 XDK 顶层函数签名表。键为源码中的简单名（包导入后绑定）。
var xdkFuncSigs = map[string]xdkFuncSig{
	// ---- xdk.runtime（S6 §4.4） ----
	"diagnose": {"runtime", []string{"String"}, "void", false},
	"exit":     {"runtime", []string{"Int"}, "void", false},
	"nowMono":  {"runtime", nil, "Int", false},
	"nowWall":  {"runtime", nil, "Int", false},
	"env":      {"runtime", []string{"String"}, "String?", false},
	"dumpTasks": {"runtime", nil, "void", false},

	// ---- xdk.sys：文件/目录/存在性（S6 §4.7；当前绑定面） ----
	"fileOpenRead":  {"sys", []string{"String"}, "File", false},
	"fileOpenWrite": {"sys", []string{"String"}, "File", false},
	"fileRead":      {"sys", []string{"File", "Bytes", "Int32"}, "Int64", false},
	"fileWrite":     {"sys", []string{"File", "Bytes"}, "Int32", false},
	"fileClose":     {"sys", []string{"File"}, "Bool", false},
	"dirOpen":       {"sys", []string{"String"}, "Dir", false},
	"dirRead":       {"sys", []string{"Dir"}, "String", false},
	"dirClose":      {"sys", []string{"Dir"}, "Bool", false},
	"pathExists":    {"sys", []string{"String"}, "Bool", false},
	"utf8Valid":     {"sys", []string{"String"}, "Int", false},
	"readFileText":  {"sys", []string{"String"}, "String", false},
	"writeFileText": {"sys", []string{"String", "String"}, "Int", false},
	"procStatus":    {"sys", []string{"String"}, "Int", false},

	// ---- xdk.sys：资源读取（S6 §4.8；默认异步形态，首参 Context） ----
	"resourceExists":   {"sys", []string{"String"}, "Bool", false},
	"readResource":     {"sys", []string{"Context", "String"}, "Result<Bytes,Error>", true},
	"readResourceText": {"sys", []string{"Context", "String"}, "Result<Text,Error>", true},
	"listResources":    {"sys", []string{"Context", "String"}, "Result<List<String>,Error>", true},
	"resourceSize":     {"sys", []string{"String"}, "Int?", false},

	// ---- xdk.text：解析与编码转换（S6 §4.6/XDK-08） ----
	// UTF-8↔UTF-16 以字节/码元序列表达，避免隐式端序：UTF-16 方向返回 List<UInt16> 码元。
	"parseInt":    {"text", []string{"String"}, "Result<Int,Error>", false},
	"parseFloat":  {"text", []string{"String"}, "Result<Double,Error>", false},
	"utf8ToUtf16": {"text", []string{"Bytes"}, "Result<List<UInt16>,Error>", false},
	"utf16ToUtf8": {"text", []string{"List<UInt16>"}, "Result<Bytes,Error>", false},
}

// xdkTypeNames 是 XDK 语言面公开类型（可出现在类型位置，成员未支持时 TY-229）。
var xdkTypeNames = map[string]bool{
	// tasks/sync（S5-05/S5-03）
	"Task": true, "TaskGroup": true, "Context": true, "CancelToken": true,
	"TaskError": true, "CancelledError": true,
	"Mutex": true, "Channel": true, "AtomicInt": true, "AtomicBool": true, "AtomicRef": true,
	// sys（S6 §4.7）
	"File": true, "Dir": true, "Process": true,
	// text（S6 §4.6）
	"Regex": true, "Format": true,
	// collections（S6 §4.5）
	"RingBuffer": true, "OrderedMap": true, "BTreeMap": true, "PriorityQueue": true,
	// net（S6 §4.7；独立包）
	"Socket": true, "Listener": true,
}

// xdkSpecialSigned 是已有专用签名检查、不进入 xdkFuncSigs 的包（S4/S5 已交）。
var xdkSpecialSigned = map[string]bool{"errors": true}

// lookupXdkFuncSig 查签名表。
func lookupXdkFuncSig(name string) (xdkFuncSig, bool) {
	sig, ok := xdkFuncSigs[name]
	return sig, ok
}

// xdkTypeBase 提取 XDK 类型基础名（去掉可空与泛型实参）。
func xdkTypeBase(key string) string {
	k := strings.TrimSuffix(key, "?")
	if i := strings.Index(k, "<"); i > 0 {
		k = k[:i]
	}
	return k
}

// xdkKnownType 判断类型串是否为 XDK 公开类型。
func xdkKnownType(key string) bool {
	return xdkTypeNames[xdkTypeBase(key)]
}

// inferXdkFuncCall 按内建签名检查实参并返回结果类型。
func (e *tyenv) inferXdkFuncCall(n *xfront.Call, name string, sig xdkFuncSig, p xfront.Pos) texpr {
	if len(n.Args) != len(sig.params) {
		e.errf(p, TyAssignability,
			fmt.Sprintf("xdk.%s.%s 需要 %d 个参数，实际 %d 个（S6 §4）",
				sig.pkg, name, len(sig.params), len(n.Args)), "")
		for _, a := range n.Args {
			e.infer(a)
		}
		return texpr{key: sig.ret}
	}
	for i, want := range sig.params {
		got := e.infer(n.Args[i])
		if !assignable(got, want) {
			e.errf(n.Args[i].Pos(), assignDiag(got, want),
				fmt.Sprintf("xdk.%s.%s 参数 %d 类型 %s 不能赋给 %s（S6 §4）",
					sig.pkg, name, i+1, describeKey(got), want), "")
		}
	}
	return texpr{key: sig.ret}
}
