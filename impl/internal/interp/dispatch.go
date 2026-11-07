// dispatch.go：类静态派发与协议动态派发的区分（S2 §5.6）。
package interp

import (
	"xnull.dev/xnull/internal/xfront"
)

// typeOf 返回名字的声明类型（沿作用域链；被遮蔽的名字以最近声明为准）。
func (s *scope) typeOf(name string) (xfront.TypeRef, bool) {
	for c := s; c != nil; c = c.parent {
		if _, ok := c.vars[name]; ok {
			t, typed := c.types[name]
			return t, typed
		}
	}
	return nil, false
}

// dispatchCall 按接收者静态类型选择派发方式：
//   - 协议类型：校验方法属于协议，再按运行时实际类动态派发（vtable 语义）；
//   - 类类型 / self：从静态类起点静态派发；
//   - 其他（Any/Object/表达式）：动态回退。
func (in *Interp) dispatchCall(sc *scope, recvExpr xfront.Expr, obj *objv, name string, args []*Value, pos xfront.Pos) (*Value, error) {
	if id, ok := recvExpr.(*xfront.IdentExpr); ok {
		if id.Name == "self" {
			if cur := in.currentClass(); cur != nil {
				return in.callMethodFrom(cur, obj, name, args, pos)
			}
		}
		if t, typed := sc.typeOf(id.Name); typed {
			if nt, ok := t.(*xfront.NamedType); ok {
				tn := lastQual(nt)
				if _, isProto := in.protocols[tn]; isProto {
					if !in.protocolHasMethod(tn, name) {
						panic(runtimeErr{"协议 " + tn + " 没有方法 " + name + "（§5.6）"})
					}
					return in.callMethod(obj, name, args, pos) // 动态：按实际类
				}
				if cls, found := in.findClass(tn); found {
					return in.callMethodFrom(cls, obj, name, args, pos) // 静态：按声明类
				}
			}
		}
	}
	return in.callMethod(obj, name, args, pos)
}

// protocolHasMethod 判断协议（含继承协议）是否声明了某方法。
func (in *Interp) protocolHasMethod(pname, method string) bool {
	d, ok := in.protocols[pname]
	if !ok {
		return false
	}
	for _, sig := range d.Sigs {
		if sig.Name == method {
			return true
		}
	}
	for _, ext := range d.Extends {
		if in.protocolHasMethod(lastQual(ext), method) {
			return true
		}
	}
	return false
}
