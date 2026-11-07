package sema

import (
	"fmt"

	"xnull.dev/xnull/internal/xfront"
)

// S7-01：FFI 调用点的 sema 面。
//
// E4 在 Analyze 前用 RegisterFFIEntries/RegisterExternalLayout 注入 .xfb 的
// 机器可读投影；sema 负责调用点类型检查（Text/layout/数组/Float/Char/UInt、
// 句柄 out、Bytes transfer/reclaim）。C 发射与包装仍归 E4。
//
// 边界：这里不读取 .xfb、不生成 C；只消费已校验的签名与 layout 尺寸。

// FFIField 是 layout(c) 的一个字段（类型为 S7 标量或已登记 layout）。
type FFIField struct {
	Name string
	Type string
}

// FFIParam 是 FFI 入口的一个参数。
type FFIParam struct {
	Name  string
	Type  string // sema 类型串：Text/Float/Char/UInt/Int[]/layout 名/File/Bytes...
	Lease string // ""/"borrow"/"transfer"/"reclaim"
	Out   bool   // 原生写出（句柄 out 形态）
}

// FFIEntry 是 FFI 入口的 sema 签名投影。
type FFIEntry struct {
	Name   string
	Params []FFIParam
	Ret    string
}

type ffiLayoutInfo struct {
	Size  int
	Align int
}

var (
	externalFFIEntries = map[string]FFIEntry{}
	externalLayouts    = map[string]ffiLayoutInfo{}
)

// RegisterFFIEntries 登记 FFI 入口签名（幂等；同名覆盖）。
func RegisterFFIEntries(entries ...FFIEntry) error {
	for _, e := range entries {
		if e.Name == "" {
			return fmt.Errorf("sema: FFI 入口缺名称")
		}
		for _, p := range e.Params {
			switch p.Lease {
			case "", "borrow", "transfer", "reclaim":
			default:
				return fmt.Errorf("sema: FFI 入口 %s 参数 %s 租约 %q 非法", e.Name, p.Name, p.Lease)
			}
		}
		externalFFIEntries[e.Name] = e
	}
	return nil
}

// RegisterExternalLayout 登记 layout(c) 的字段与 C 侧 sizeof，并校验尺寸。
// 只允许 S7 标量或已登记的嵌套 layout；尺寸按 C 自然对齐计算，必须与 cSize 一致。
func RegisterExternalLayout(name string, fields []FFIField, cSize int) error {
	if name == "" {
		return fmt.Errorf("sema: layout 缺名称")
	}
	if len(fields) == 0 {
		return fmt.Errorf("sema: layout %s 至少需要一个字段（S7 §3.3）", name)
	}
	seen := map[string]bool{}
	offset, maxAlign := 0, 1
	for _, f := range fields {
		if f.Name == "" || seen[f.Name] {
			return fmt.Errorf("sema: layout %s 字段名空或重复：%q", name, f.Name)
		}
		seen[f.Name] = true
		size, align, ok := ffiLayoutFieldSize(f.Type)
		if !ok {
			return fmt.Errorf("sema: layout %s 字段 %s 类型 %s 非标量/嵌套 layout（S7 §3.3）", name, f.Name, f.Type)
		}
		offset = ffiAlignUp(offset, align)
		offset += size
		if align > maxAlign {
			maxAlign = align
		}
	}
	total := ffiAlignUp(offset, maxAlign)
	if cSize != total {
		return fmt.Errorf("sema: layout %s 尺寸 %d 与 C sizeof %d 不一致（S7 §3.3）", name, total, cSize)
	}
	externalLayouts[name] = ffiLayoutInfo{Size: total, Align: maxAlign}
	RegisterExternalTypes(name)
	return nil
}

// LayoutSize 返回已登记 layout 的 C sizeof。
func LayoutSize(name string) (int, bool) {
	l, ok := externalLayouts[name]
	return l.Size, ok
}

func ffiLayoutFieldSize(t string) (size, align int, ok bool) {
	if l, ok := externalLayouts[t]; ok {
		return l.Size, l.Align, true
	}
	switch t {
	case "Int8", "UInt8", "Bool", "Byte", "UByte":
		return 1, 1, true
	case "Int16", "UInt16", "Short", "UShort":
		return 2, 2, true
	case "Int32", "UInt32", "Float32", "Char":
		return 4, 4, true
	case "Int", "UInt", "Int64", "UInt64", "Long", "ULong", "Float", "Float64", "Double":
		return 8, 8, true
	}
	return 0, 0, false
}

func ffiAlignUp(n, align int) int {
	if align <= 1 {
		return n
	}
	rem := n % align
	if rem == 0 {
		return n
	}
	return n + align - rem
}

func lookupFFIEntry(name string) (FFIEntry, bool) {
	e, ok := externalFFIEntries[name]
	return e, ok
}

func isExternalFFIName(name string) bool {
	_, ok := externalFFIEntries[name]
	return ok
}

// inferFFICall 检查 FFI 调用点实参/返回类型与 out/transfer 形参。
func (e *tyenv) inferFFICall(n *xfront.Call, entry FFIEntry, p xfront.Pos) texpr {
	if len(n.Args) != len(entry.Params) {
		e.errf(p, TyAssignability,
			fmt.Sprintf("FFI 入口 `%s` 需要 %d 个参数，实际 %d 个（S7 §2）", entry.Name, len(entry.Params), len(n.Args)), "")
		for _, a := range n.Args {
			e.infer(a)
		}
		return texpr{key: entry.Ret}
	}
	for i, param := range entry.Params {
		got := e.infer(n.Args[i])
		if !assignable(got, param.Type) {
			e.errf(n.Args[i].Pos(), assignDiag(got, param.Type),
				fmt.Sprintf("FFI 入口 `%s` 参数 %d 类型 %s 不能赋给 %s（S7 §3）",
					entry.Name, i+1, describeKey(got), param.Type), "")
		}
		if param.Out || param.Lease == "transfer" || param.Lease == "reclaim" {
			if _, ok := n.Args[i].(*xfront.IdentExpr); !ok {
				e.errf(n.Args[i].Pos(), TyBadOperand,
					fmt.Sprintf("FFI 入口 `%s` 的 %s 参数必须是变量（S7 §4.2 所有权明确）", entry.Name, param.Name), "")
			}
		}
	}
	if entry.Ret == "" {
		return texpr{}
	}
	return texpr{key: entry.Ret}
}
