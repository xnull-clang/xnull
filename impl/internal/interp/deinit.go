// deinit.go：解释器确定性 deinit（S2 §6.4）：块/函数作用域退出执行派生→父类链。
package interp

import (
	"xnull.dev/xnull/internal/xfront"
)

// closeScope 在作用域退出时按声明逆序释放变量持有，最后一次 release 触发 deinit（§6.4）。
func (in *Interp) closeScope(sc *scope) {
	for i := len(sc.objOrder) - 1; i >= 0; i-- {
		name := sc.objOrder[i]
		in.releaseObject(sc.objOwner[name])
		delete(sc.objOwner, name)
	}
	// 临时对象在调用方块结束时释放（被调方 errdefer/错误处理先完成）。
	for i := len(sc.temps) - 1; i >= 0; i-- {
		in.releaseObject(sc.temps[i])
	}
	sc.temps = nil
}

// detachTemp 把临时引用转交给变量（同作用域最近一次匹配）。
func (in *Interp) detachTemp(sc *scope, obj *objv) bool {
	for i := len(sc.temps) - 1; i >= 0; i-- {
		if sc.temps[i] == obj {
			sc.temps = append(sc.temps[:i], sc.temps[i+1:]...)
			if obj.owners > 0 {
				obj.owners--
			}
			return true
		}
	}
	return false
}

// addTemp 登记 new 产生的临时对象：由创建它的作用域在块结束时释放。
func (in *Interp) addTemp(sc *scope, obj *objv) {
	if obj == nil {
		return
	}
	obj.owners++
	sc.temps = append(sc.temps, obj)
}

// takeOwnership 变量首次持有一个对象（强持有 +1）。
func (in *Interp) takeOwnership(sc *scope, name string, v *Value) {
	if v == nil || v.K != vObj {
		return
	}
	obj := v.O
	// `T x = new T()`：临时引用转交变量，避免同一作用域多持有一份。
	in.detachTemp(sc, obj)
	obj.escaped = false
	obj.owners++
	if _, exists := sc.objOwner[name]; !exists {
		sc.objOrder = append(sc.objOrder, name)
	}
	sc.objOwner[name] = obj
}

// rebindOwnership 变量重新赋值：释放旧对象，持有新对象（§4.4 强持有）。
func (in *Interp) rebindOwnership(sc *scope, name string, v *Value) {
	var holder *scope
	for c := sc; c != nil; c = c.parent {
		if _, ok := c.vars[name]; ok {
			holder = c
			break
		}
	}
	if holder == nil {
		return
	}
	old := holder.objOwner[name]
	var nw *objv
	if v != nil && v.K == vObj {
		nw = v.O
	}
	if old == nw {
		if nw != nil {
			nw.escaped = false
		}
		return
	}
	if old != nil {
		in.releaseObject(old)
	}
	if nw != nil {
		in.detachTemp(sc, nw)
		nw.escaped = false
		nw.owners++
		if _, exists := holder.objOwner[name]; !exists {
			holder.objOrder = append(holder.objOrder, name)
		}
		holder.objOwner[name] = nw
	} else {
		delete(holder.objOwner, name)
	}
}

// releaseObject 释放一个强引用；归零时执行 deinit（返回值转交的 escaped 只跳过一次）。
func (in *Interp) releaseObject(obj *objv) {
	if obj == nil {
		return
	}
	if obj.owners > 0 {
		obj.owners--
	}
	if obj.owners > 0 {
		return
	}
	if obj.escaped {
		obj.escaped = false
		return
	}
	in.runDeinit(obj)
}

// markEscaped 标记返回值所有权转交调用方（被调方作用域释放时不 deinit）。
func (in *Interp) markEscaped(v *Value) {
	if v == nil {
		return
	}
	switch v.K {
	case vObj:
		v.O.escaped = true
	case vResult:
		if v.R != nil {
			if v.R.ok {
				in.markEscaped(v.R.v)
			} else {
				in.markEscaped(v.R.e)
			}
		}
	case vTuple:
		for _, e := range v.A {
			in.markEscaped(e)
		}
	}
}

// runDeinit 对单个对象执行一次 deinit 链（以 deinited 去重）。
func (in *Interp) runDeinit(obj *objv) {
	if obj == nil || in.deinited[obj] {
		return
	}
	in.deinited[obj] = true
	in.runDeinitFrom(obj.cls, obj)
	for _, v := range obj.fields { // §6.4：deinit 链完成后释放字段引用
		if v != nil && v.K == vObj {
			in.releaseObject(v.O)
		}
	}
}

// findDeinit 从 start 起沿父类链找 deinit 声明。
func (in *Interp) findDeinit(start *xfront.ClassDecl) (*xfront.ClassDecl, *xfront.MethodDecl, bool) {
	for c := start; c != nil; c = in.baseClass(c) {
		for _, m := range c.Methods {
			if m.IsDeinit {
				return c, m, true
			}
		}
	}
	return nil, nil, false
}

// runDeinitFrom 执行 start 链上的 deinit；若体内未显式 super.deinit，则自动继续父类链。
func (in *Interp) runDeinitFrom(start *xfront.ClassDecl, obj *objv) {
	declCls, m, ok := in.findDeinit(start)
	if !ok {
		return
	}
	done := false
	in.deinitFrames = append(in.deinitFrames, &done)
	in.callDeinitBody(obj, declCls, m)
	in.deinitFrames = in.deinitFrames[:len(in.deinitFrames)-1]
	if !done {
		if parent := in.baseClass(declCls); parent != nil {
			in.runDeinitFrom(parent, obj)
		}
	}
}

// callDeinitBody 执行 deinit 体：绑定 self、静态派发到声明类。
func (in *Interp) callDeinitBody(obj *objv, declCls *xfront.ClassDecl, m *xfront.MethodDecl) {
	defer func() {
		if r := recover(); r != nil {
			if _, ok := r.(ctrlReturn); ok {
				return // deinit 无返回值
			}
			panic(r)
		}
	}()
	in.methodStack = append(in.methodStack, declCls)
	defer func() { in.methodStack = in.methodStack[:len(in.methodStack)-1] }()
	sc := newScope(in.globals)
	sc.define("self", &Value{K: vObj, O: obj})
	if m.Body != nil {
		in.execBlock(m.Body, sc)
	}
}
