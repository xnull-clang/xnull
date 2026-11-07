// super.go：`super.m()` / `super.field` 的静态查找（S2 §5.4：super 静态派发）。
package interp

import (
	"xnull.dev/xnull/internal/xfront"
)

// superBase 返回当前实例方法声明类的父类（super 查找起点）。
func (in *Interp) superBase() *xfront.ClassDecl {
	cur := in.currentClass()
	if cur == nil {
		panic(runtimeErr{"super 只能在实例方法中使用（§5.4）"})
	}
	parent := in.baseClass(cur)
	if parent == nil {
		panic(runtimeErr{"当前类没有父类，不能使用 super（§5.4）：" + cur.Name})
	}
	return parent
}

// superField 在父类链上查字段，返回声明与承载对象（同一 self）。
func (in *Interp) superField(sc *scope, name string) (*xfront.FieldDecl, *objv, bool) {
	self, ok := sc.lookup("self")
	if !ok || self.K != vObj {
		return nil, nil, false
	}
	for c := in.superBase(); c != nil; c = in.baseClass(c) {
		for _, f := range c.Fields {
			if f.Name == name || f.Canonical == name || "_"+f.Name == name {
				return f, self.O, true
			}
		}
	}
	return nil, nil, false
}
