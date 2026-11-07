// errors.go：xdk.errors 解释器语义（S4 §2.3/§4）：wrap/mapErr/report。
package interp

import (
	"fmt"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

// callErrorsBuiltin 执行 xdk.errors 三个内置函数（用户同名函数优先，见 evalCall）。
func (in *Interp) callErrorsBuiltin(name string, n *xfront.Call, sc *scope) *Value {
	switch name {
	case "wrap":
		if len(n.Args) != 2 {
			panic(runtimeErr{"wrap 恰好接受 2 个参数（S4 §2.3）"})
		}
		r := in.eval(n.Args[0], sc)
		if !r.isResult() {
			panic(runtimeErr{"wrap 的第一个参数必须是 Result（S4 §2.3）"})
		}
		if r.R.ok {
			return r
		}
		return &Value{K: vResult, R: &resv{ok: false, e: in.eval(n.Args[1], sc)}}
	case "mapErr":
		if len(n.Args) != 2 {
			panic(runtimeErr{"mapErr 恰好接受 2 个参数（S4 §2.3）"})
		}
		r := in.eval(n.Args[0], sc)
		if !r.isResult() {
			panic(runtimeErr{"mapErr 的第一个参数必须是 Result（S4 §2.3）"})
		}
		if r.R.ok {
			return r
		}
		f := in.eval(n.Args[1], sc)
		mapped := in.callValueFn(f, []*Value{r.R.e}, n.P)
		return &Value{K: vResult, R: &resv{ok: false, e: mapped}}
	case "report":
		if len(n.Args) != 1 {
			panic(runtimeErr{"report 恰好接受 1 个参数（S4 §2.3）"})
		}
		r := in.eval(n.Args[0], sc)
		if !r.isResult() {
			panic(runtimeErr{"report 的参数必须是 Result（S4 §2.3）"})
		}
		if !r.R.ok {
			in.emitReport(r.R.e)
		}
		return r // XDK 定案 3-a-1：report 返回原 Result，支持 return report(r)
	}
	panic(runtimeErr{"未定义的函数：" + name})
}

// callValueFn 调用闭包值（mapErr 的转换函数）。
func (in *Interp) callValueFn(f *Value, args []*Value, pos xfront.Pos) *Value {
	if f == nil || f.K != vClosure {
		panic(runtimeErr{"mapErr 第二个参数必须是转换函数（S4 §2.3）"})
	}
	return in.callClosure(f.Clo, args)
}

// emitReport 写单行诊断：`<kind>: <describe>`（S4 §4.3；无调用栈）。
func (in *Interp) emitReport(errVal *Value) {
	kind := "Internal"
	desc := format(errVal)
	if kv := in.errorMember(errVal, "kind"); kv != nil {
		kind = reportText(kv)
	}
	if dv := in.errorMember(errVal, "describe"); dv != nil {
		desc = reportText(dv)
	}
	desc = strings.ReplaceAll(desc, "\r", " ")
	desc = strings.ReplaceAll(desc, "\n", " ")
	fmt.Fprintf(in.diag, "%s: %s\n", kind, desc)
}

// errorMember 安全调用错误值的 kind()/describe()；非 Error 类型返回 nil（走兜底）。
func (in *Interp) errorMember(errVal *Value, name string) (v *Value) {
	defer func() {
		if r := recover(); r != nil {
			if _, ok := r.(runtimeErr); ok {
				v = nil
				return
			}
			panic(r)
		}
	}()
	switch errVal.K {
	case vObj:
		out, err := in.callMethod(errVal.O, name, nil, xfront.Pos{})
		if err != nil {
			return nil
		}
		return out
	case vStruct:
		out, err := in.callStructMethod(errVal.St, name, nil, xfront.Pos{})
		if err != nil {
			return nil
		}
		return out
	}
	return nil
}

// reportText 把 kind/describe 运行值转成单行文本（String 原样，其余按格式规则）。
func reportText(v *Value) string {
	if v == nil {
		return ""
	}
	if v.K == vStr {
		return v.S
	}
	return format(v)
}

// registerBuiltinXDKErrors 预置 xdk.errors 的 ErrorKind 枚举与 Error 协议（S4 §2/§3）。
// 用户显式同名声明优先，不覆盖。
func (in *Interp) registerBuiltinXDKErrors() {
	if _, exists := in.enums["ErrorKind"]; !exists {
		names := []string{
			"InvalidArgument", "NotFound", "AlreadyExists", "PermissionDenied",
			"Io", "Network", "Timeout", "Cancelled", "Busy", "Unavailable",
			"DataCorrupted", "Unsupported", "OutOfMemory", "Internal",
		}
		d := &xfront.EnumDecl{Name: "ErrorKind"}
		for _, n := range names {
			d.Items = append(d.Items, &xfront.EnumItem{Name: n})
		}
		in.registerEnum(d)
	}
	if _, exists := in.protocols["Error"]; !exists {
		in.protocols["Error"] = &xfront.ProtocolDecl{
			Name: "Error",
			Sigs: []*xfront.ProtocolSig{
				{Name: "kind", Ret: &xfront.NamedType{Qual: []string{"ErrorKind"}}},
				{Name: "describe", Ret: &xfront.NamedType{Qual: []string{"String"}}},
			},
		}
	}
}
