// s701.go：S7-01 调用点投射——把 .xfb 注册表登记给 sema（类型/layout/租约）。
package codegen

import (
	"fmt"

	"xnull.dev/xnull/internal/codegen/ffi"
	"xnull.dev/xnull/internal/sema"
)

func s701ScalarName(n string) bool {
	switch n {
	case "Int", "UInt", "Int8", "Int16", "Int32", "Int64",
		"UInt8", "UInt16", "UInt32", "UInt64",
		"Float", "Float32", "Float64", "Double", "Bool", "Char":
		return true
	}
	return false
}

func s701TypeString(t ffi.BoundType) (string, error) {
	switch t.Kind {
	case ffi.KindScalar:
		return t.Name, nil
	case ffi.KindString:
		return "String", nil
	case ffi.KindText:
		return "Text", nil
	case ffi.KindBytes:
		return "Bytes", nil
	case ffi.KindLayout:
		return t.Name, nil
	case ffi.KindHandle:
		return t.Name, nil
	case ffi.KindArray:
		if t.Elem == nil {
			return "", fmt.Errorf("数组元素缺失（S7 §3.5）")
		}
		es, err := s701TypeString(*t.Elem)
		if err != nil {
			return "", err
		}
		return es + "[]", nil
	}
	return "", fmt.Errorf("类型 %s 未纳入 S7-01 投影", t.String())
}

func s701Lease(l ffi.LeaseKind) string {
	switch l {
	case ffi.LeaseBorrow:
		return "borrow"
	case ffi.LeaseTransfer:
		return "transfer"
	case ffi.LeaseClaim:
		return "reclaim"
	}
	return ""
}

// RegisterFFIProjection 把 .xfb 注册表投射为 sema 的 S7-01 外部面。
func RegisterFFIProjection(reg *ffi.Registry) error {
	if reg == nil {
		return nil
	}
	// layout(c)：按依赖顺序登记（尺寸与 C 自然对齐；E4 与发射共用计算）。
	for _, l := range reg.Layouts {
		fields := make([]sema.FFIField, 0, len(l.Fields))
		for _, f := range l.Fields {
			fields = append(fields, sema.FFIField{Name: f.Name, Type: f.Type})
		}
		size, err := ffi.CSize(l, reg.Layouts)
		if err != nil {
			return err
		}
		if err := sema.RegisterExternalLayout(l.Name, fields, size); err != nil {
			return err
		}
	}
	entries := make([]sema.FFIEntry, 0, len(reg.Entries))
	for _, e := range reg.Entries {
		params := make([]sema.FFIParam, 0, len(e.Params))
		for i, p := range e.Params {
			ts, err := s701TypeString(p.Type)
			if err != nil {
				return fmt.Errorf("入口 %s 参数 %s：%w", e.Name, p.Name, err)
			}
			lease := ffi.LeaseNone
			if i < len(e.Lease) {
				lease = e.Lease[i]
			}
			out := p.Type.Kind == ffi.KindHandle && (lease == ffi.LeaseTransfer || lease == ffi.LeaseClaim)
			if out {
				// 句柄 out 在 XNull 侧以可空句柄接收（E4 包装约定）。
				ts += "?"
			}
			params = append(params, sema.FFIParam{Name: p.Name, Type: ts, Lease: s701Lease(lease), Out: out})
		}
		ret := ""
		if e.Ret.Kind != ffi.KindVoid {
			rs, err := s701TypeString(e.Ret)
			if err != nil {
				return fmt.Errorf("入口 %s 返回：%w", e.Name, err)
			}
			ret = rs
		}
		entries = append(entries, sema.FFIEntry{Name: e.Name, Params: params, Ret: ret})
	}
	return sema.RegisterFFIEntries(entries...)
}
