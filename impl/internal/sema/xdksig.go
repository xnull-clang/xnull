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
	"diagnose":  {"runtime", []string{"String"}, "void", false},
	"exit":      {"runtime", []string{"Int"}, "void", false},
	"nowMono":   {"runtime", nil, "Int", false},
	"nowWall":   {"runtime", nil, "Int", false},
	"env":       {"runtime", []string{"String"}, "String?", false},
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

	// ---- xdk.net：socket plain/Async（S6 §4.7 / S6-09） ----
	"connect":      {"net", []string{"String", "Int"}, "Result<Socket,Error>", false},
	"connectAsync": {"net", []string{"Context", "String", "Int"}, "Result<Socket,Error>", true},
	"bind":         {"net", []string{"String", "Int"}, "Result<Listener,Error>", false},
	"bindAsync":    {"net", []string{"Context", "String", "Int"}, "Result<Listener,Error>", true},

	// ---- xdk.net.http（S6-09） ----
	"get":       {"net.http", []string{"String"}, "Result<Response,Error>", false},
	"post":      {"net.http", []string{"String", "Bytes"}, "Result<Response,Error>", false},
	"getAsync":  {"net.http", []string{"Context", "String"}, "Result<Response,Error>", true},
	"postAsync": {"net.http", []string{"Context", "String", "Bytes"}, "Result<Response,Error>", true},
	// ---- xdk.net：socket plain/Async + HTTP（S6-09 / ADR-009） ----
	"socketConnect": {"net", []string{"String", "Int32"}, "Result<Socket,ErrorKind>", false},
	"socketListen":  {"net", []string{"String", "Int32"}, "Result<Listener,ErrorKind>", false},
	"socketAccept":  {"net", []string{"Listener"}, "Result<Socket,ErrorKind>", false},
	"socketRead":    {"net", []string{"Socket", "Bytes"}, "Result<Int64,ErrorKind>", false},
	"socketWrite":   {"net", []string{"Socket", "Bytes"}, "Result<Int64,ErrorKind>", false},
	"socketClose":   {"net", []string{"Socket"}, "Bool", false},
	"listenerClose": {"net", []string{"Listener"}, "Bool", false},

	"socketConnectAsync": {"net", []string{"Context", "String", "Int32"}, "Result<Socket,ErrorKind>", true},
	"socketListenAsync":  {"net", []string{"Context", "String", "Int32"}, "Result<Listener,ErrorKind>", true},
	"socketAcceptAsync":  {"net", []string{"Context", "Listener"}, "Result<Socket,ErrorKind>", true},
	"socketReadAsync":    {"net", []string{"Context", "Socket", "Bytes"}, "Result<Int64,ErrorKind>", true},
	"socketWriteAsync":   {"net", []string{"Context", "Socket", "Bytes"}, "Result<Int64,ErrorKind>", true},
	"socketCloseAsync":   {"net", []string{"Context", "Socket"}, "Result<void,ErrorKind>", true},
	"listenerCloseAsync": {"net", []string{"Context", "Listener"}, "Result<void,ErrorKind>", true},
	"httpGet":            {"net.http", []string{"Context", "String"}, "Result<Bytes,ErrorKind>", true},
	"httpPost":           {"net.http", []string{"Context", "String", "Bytes"}, "Result<Bytes,ErrorKind>", true},

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
	"Socket": true, "Listener": true, "Request": true, "Response": true,
}

// xdkSpecialSigned 是已有专用签名检查、不进入 xdkFuncSigs 的包（S4/S5 已交）。
var xdkSpecialSigned = map[string]bool{"errors": true}

// lookupXdkFuncSig 查签名表。
func lookupXdkFuncSig(name string) (xdkFuncSig, bool) {
	sig, ok := xdkFuncSigs[name]
	return sig, ok
}

// inferXdkCtor 处理 xdk.sync 内建类型的构造调用（S5 §7）：
//
//	Mutex<T>(value) / Channel<T>(capacity) / AtomicRef<T>(value)
//	AtomicInt(initial) / AtomicBool(initial)
//
// 返回 (类型, true) 表示已处理；否则 (_, false) 交给普通调用路径。
func (e *tyenv) inferXdkCtor(n *xfront.Call, name string) (texpr, bool) {
	inferArgs := func() {
		for _, a := range n.Args {
			e.infer(a)
		}
	}
	switch name {
	case "Mutex", "Channel", "AtomicRef":
		if len(n.TypeArgs) != 1 {
			e.errf(n.P, GenTypeArgs,
				"`"+name+"<T>` 构造需要 1 个类型实参（S5 §7）", "写 "+name+"<T>(...)")
			inferArgs()
			return texpr{}, true
		}
		tk := typeKey(n.TypeArgs[0])
		if e.a.tc != nil {
			e.a.tc.checkSyncTypeArg(name, tk, n.P)
		}
		want := tk
		if name == "Channel" {
			want = "Int" // 有界容量
		}
		if len(n.Args) != 1 {
			e.errf(n.P, TyAssignability,
				"`"+name+"<"+tk+">` 构造需要 1 个参数（S5 §7）", "")
			inferArgs()
			return texpr{key: name + "<" + tk + ">"}, true
		}
		got := e.infer(n.Args[0])
		if !assignable(got, want) {
			e.errf(n.Args[0].Pos(), assignDiag(got, want),
				"`"+name+"<"+tk+">` 构造参数类型 "+describeKey(got)+" 不能赋给 "+want+"（S5 §7）", "")
		}
		return texpr{key: name + "<" + tk + ">"}, true
	case "AtomicInt":
		return e.inferXdkAtomicCtor(n, "Int", "AtomicInt", inferArgs), true
	case "AtomicBool":
		return e.inferXdkAtomicCtor(n, "Bool", "AtomicBool", inferArgs), true
	}
	return texpr{}, false
}

func (e *tyenv) inferXdkAtomicCtor(n *xfront.Call, want, ret string, inferArgs func()) texpr {
	if len(n.Args) != 1 {
		e.errf(n.P, TyAssignability, "`"+ret+"` 构造需要 1 个初始值（S5 §7）", "")
		inferArgs()
		return texpr{key: ret}
	}
	got := e.infer(n.Args[0])
	if !assignable(got, want) {
		e.errf(n.Args[0].Pos(), assignDiag(got, want),
			"`"+ret+"` 初始值类型 "+describeKey(got)+" 不能赋给 "+want+"（S5 §7）", "")
	}
	return texpr{key: ret}
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
