// Package ffi 解析 .xfb 绑定声明文件并执行 S7 合同校验，产出绑定注册表。
//
// 边界：
//   - 只消费声明文本（.xfb 方言），不触及语言文法（.x 零改动）；
//   - 对外只暴露 Registry 与四个入口（Load / EmitCall / EmitSupport /
//     DeclareDiagnostics），其余类型与流程内部化；
//   - 输出确定性：注册表按名称排序、诊断按位置排序（DET-01）。
//
// 合同来源：impl/docs/ffi-design.md、impl/docs/ffi-contract.md。
package ffi

import (
	"fmt"
	"sort"

	"xnull.dev/xnull/internal/diag"
)

// Diagnostic 复用统一诊断渲染（file:line:col: error[CODE]: message）。
type Diagnostic = diag.Diagnostic

// DiagSpec 是一个 FFI 诊断码的规格。
type DiagSpec struct {
	Code    string
	Summary string
}

// Specs 是 FFI 段位诊断码全集（确定性顺序）。
var Specs = []DiagSpec{
	{"FFI-100", "绑定声明语法错误"},
	{"FFI-101", "入口合同声明缺失或不完整（@ffiEntry/cName、@lease 覆盖与参数不符）"},
	{"FFI-102", "移交（.transfer）缺少对称归还（.reclaim）且未声明 neverReclaim 理由"},
	{"FFI-103", "String/Text 声明移交或归还（不可移交，S7 §3.4）"},
	{"FFI-104", "嵌套数组或数组元素类型非法（S7 §3.5）"},
	{"FFI-105", "类型不跨边界（S7 §2.1/§3.6；含未知类型、可选、容器、未声明句柄/结构）"},
	{"FFI-106", "错误码声明不合法（@errorCode 形参或 errorMap 条目非法）"},
	{"FFI-107", "阻塞分类缺失或非法；长阻塞缺专用执行器伴生形态（S7 §7.3）"},
	{"FFI-108", "裸指针类型或指针/长度合同违规（S7 §3.2/§3.4）"},
	{"FFI-109", "layout(c) 声明违规（字段类型、递归包含、重名、未声明）"},
	{"FFI-110", "@unsafe 缺合同文本或位置违规（仅限绑定层，S7 §8）"},
	{"FFI-111", "重复声明（入口/结构/句柄同名）"},
}

// DeclareDiagnostics 返回 FFI 段位诊断码全集。
func DeclareDiagnostics() []DiagSpec { return Specs }

// Snippet 是生成代码片段（EmitCall/EmitSupport 的返回单元）。
type Snippet struct {
	Text     string   // C 代码文本
	Includes []string // 需要的公共头（当前恒为 xrt.h）
	// Problems 是未能生成的入口（编组未覆盖等）。非空即构建失败，
	// 绝不静默降级（ffi-design §3.2 规则 8）。
	Problems []string
}

// LinkLib 是工程清单 link.libraries 的一项（S8 §7）。
type LinkLib struct {
	Name   string
	Kind   string // static | dynamic
	System bool   // 系统库：不打包、不复制到产物目录
}

// TempName 是 codegen 分配的目标临时变量名。
type TempName string

// ArgExpr 是一个已生成的实参表达式。
type ArgExpr struct {
	Text string // C 表达式文本
	Ref  bool   // 引用类型实参（调用方持有，编组需 retain/借出标记）
}

// BoundKind 是跨边界类型种类。
type BoundKind int

const (
	KindVoid BoundKind = iota
	KindScalar
	KindString
	KindText
	KindBytes
	KindArray
	KindLayout
	KindHandle
)

// BoundType 是参数/返回值的边界类型。
type BoundType struct {
	Kind BoundKind
	Name string     // 标量名 / 结构名 / 句柄名
	Elem *BoundType // 数组元素（KindArray）
}

// String 渲染为声明态类型文本（诊断与文档用）。
func (t BoundType) String() string {
	switch t.Kind {
	case KindVoid:
		return "Void"
	case KindArray:
		if t.Elem == nil {
			return "[]"
		}
		return t.Elem.String() + "[]"
	default:
		return t.Name
	}
}

// LeaseKind 是逐参数调用租约（S7 §2.2）。
type LeaseKind int

const (
	LeaseNone LeaseKind = iota
	LeaseBorrow
	LeaseTransfer
	LeaseClaim // .reclaim：归还路径
)

// String 渲染租约文本。
func (l LeaseKind) String() string {
	switch l {
	case LeaseBorrow:
		return ".borrow"
	case LeaseTransfer:
		return ".transfer"
	case LeaseClaim:
		return ".reclaim"
	default:
		return "."
	}
}

// Blocking 是阻塞分类（S7 §7.3）。
type Blocking int

const (
	BlockingUnclassified Blocking = iota
	BlockingAware
	BlockingUnaware
)

// String 渲染阻塞分类文本。
func (b Blocking) String() string {
	switch b {
	case BlockingAware:
		return ".aware"
	case BlockingUnaware:
		return ".unaware"
	default:
		return "（未声明）"
	}
}

// ErrRule 是错误码到本地错误分类的一条映射。
type ErrRule struct {
	Code int32
	Kind string // ErrorKind 分类名（Invalid/NotFound/... /Internal）
}

// Param 是一个边界参数。
type Param struct {
	Name string
	Type BoundType
}

// Entry 是一个 FFI 入口的合同投影。
type Entry struct {
	Name         string
	CName        string
	Region       string
	Ret          BoundType
	Params       []Param
	Lease        []LeaseKind // 与 Params 同序
	ErrorCode    string      // 错误码通道：返回码时为空串且 Ret 为 Int32；形参时为形参名
	ErrorCodeRet bool        // true：错误码即返回值（.result）
	ErrorMap     []ErrRule   // 按码升序
	Blocking     Blocking
	LongRunning  bool
	Unsafe       bool
	ContractText string
	CloseOf      string // 非空：该入口是某句柄的 close
}

// LayoutField 是 layout(c) 结构的一个字段。
type LayoutField struct {
	Name string
	Type string // 标量名
}

// Layout 是 layout(c) 结构声明。
type Layout struct {
	Name   string
	Region string
	Fields []LayoutField
}

// Handle 是不透明句柄声明。
type Handle struct {
	Name   string
	Region string
	Close  string // close 入口名
}

// Registry 是全部绑定声明的机器可读产物（确定性：各项按名称排序）。
type Registry struct {
	Entries []Entry
	Layouts []Layout
	Handles []Handle
}

// Empty 报告注册表是否为空（无 FFI 的空路径）。
func (r *Registry) Empty() bool {
	return r == nil || (len(r.Entries) == 0 && len(r.Layouts) == 0 && len(r.Handles) == 0)
}

// Entry 按名称查找入口。
func (r *Registry) Entry(name string) (Entry, bool) {
	if r == nil {
		return Entry{}, false
	}
	for i := range r.Entries {
		if r.Entries[i].Name == name {
			return r.Entries[i], true
		}
	}
	return Entry{}, false
}

// sortAll 按名称排序（DET-01）。
func (r *Registry) sortAll() {
	sort.Slice(r.Entries, func(i, j int) bool { return r.Entries[i].Name < r.Entries[j].Name })
	sort.Slice(r.Layouts, func(i, j int) bool { return r.Layouts[i].Name < r.Layouts[j].Name })
	sort.Slice(r.Handles, func(i, j int) bool { return r.Handles[i].Name < r.Handles[j].Name })
}

// sortDiags 诊断按文件/行/列/码排序，保证同一输入同一输出顺序。
func sortDiags(ds []Diagnostic) {
	sort.SliceStable(ds, func(i, j int) bool {
		a, b := ds[i], ds[j]
		if a.File != b.File {
			return a.File < b.File
		}
		if a.Line != b.Line {
			return a.Line < b.Line
		}
		if a.Col != b.Col {
			return a.Col < b.Col
		}
		return a.Code < b.Code
	})
}

// pos 是声明文件内的行列位置。
type pos struct {
	Line int
	Col  int
}

// kindName 供错误消息使用。
func kindName(k BoundKind) string {
	names := map[BoundKind]string{
		KindVoid: "Void", KindScalar: "标量", KindString: "String", KindText: "Text",
		KindBytes: "Bytes", KindArray: "数组", KindLayout: "layout(c) 结构", KindHandle: "句柄",
	}
	if n, ok := names[k]; ok {
		return n
	}
	return fmt.Sprintf("kind(%d)", int(k))
}
