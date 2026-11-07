// deinit.go：解释器确定性 deinit（S2 §6.4）：块/函数作用域退出执行派生→父类链。
package interp

import (
	"xnull.dev/xnull/internal/xfront"
)

// closeScope 在作用域退出时按声明逆序执行对象 deinit（§6.4）。
func (in *Interp) closeScope(sc *scope) {
	for i := len(sc.owned) - 1; i >= 0; i-- {
		in.runDeinit(sc.owned[i])
	}
}

// runDeinit 对单个对象执行一次 deinit 链（以 deinited 去重）。
func (in *Interp) runDeinit(obj *objv) {
	if obj == nil || in.deinited[obj] {
		return
	}
	in.deinited[obj] = true
	in.runDeinitFrom(obj.cls, obj)
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
