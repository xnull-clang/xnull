// objects.go 是解释器的类/协议运行时（M4.4b，CEO 裁决 A 案）。
//
// 边界（裁决原文口径）：
//   - 内存由 Go GC 托管，**不做 ARC 时序模拟**；deinit 不自动触发（引用计数时序不可比，
//     双路径一致性只断言 stdout 与退出码）；
//   - 协议分派按对象实际类的方法名解析（§5 协议方法调用即按名分派，vtable 是 codegen 的实现细节）；
//   - 继承：单继承按基类链查找字段与方法；多级继承支持到基类链穷尽为止。
package interp

import (
	"fmt"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

// objv 是类实例：字段按声明序保存（保持确定性），cls 指向运行时类声明。
type objv struct {
	cls        *xfront.ClassDecl
	fields     map[string]*Value
	order      []string
	enumName   string // 非空表示数据枚举项（S2 §8.3）
	enumItem   string // 数据枚举项名
	singleName string // 非空表示 singleton 实例（S2 §9）
	owners     int    // 强持有计数（§4.4 协议/变量/字段）
	escaped    bool   // 返回值所有权已转交调用方
}

// findClass 按名查类（含点分限定名的末段）。
func (in *Interp) findClass(name string) (*xfront.ClassDecl, bool) {
	c, ok := in.classes[name]
	return c, ok
}

// findField 在类链上查字段声明与所属实例（单继承）。
func findField(cls *xfront.ClassDecl, name string) (*xfront.FieldDecl, bool) {
	for c := cls; c != nil; c = nil {
		for _, f := range c.Fields {
			if f.Name == name || f.Canonical == name || f.Canonical == "_"+name {
				return f, true
			}
		}
		break
	}
	return nil, false
}

// findMethod 在类链上查方法（单继承：基类在 codegen 侧展开，解释器按 Base 递归）。
func (in *Interp) findMethod(cls *xfront.ClassDecl, name string) (*xfront.MethodDecl, bool) {
	for c := cls; c != nil; c = in.baseClass(c) {
		for _, m := range c.Methods {
			if m.Name == name {
				return m, true
			}
		}
	}
	return nil, false
}

func (in *Interp) baseClass(c *xfront.ClassDecl) *xfront.ClassDecl {
	if c.Base == nil {
		return nil
	}
	nt, ok := c.Base.(*xfront.NamedType)
	if !ok {
		return nil
	}
	if b, ok := in.findClass(lastQual(nt)); ok {
		return b
	}
	return nil
}

// evalNew 构造实例：分配并清零整条继承链 → super(...) → 当前类字段初值 → 构造器体（§6.5）。
func (in *Interp) evalNew(n *xfront.New, sc *scope) *Value {
	nt, ok := n.Type.(*xfront.NamedType)
	if !ok {
		panic(runtimeErr{"new 的类型必须是命名类（S1 §7.1）"})
	}
	name := lastQual(nt)
	args := make([]*Value, len(n.Args))
	for i, a := range n.Args {
		args[i] = in.eval(a, sc)
	}
	if st, ok := in.structs[name]; ok {
		return in.newStruct(st, args, sc)
	}
	cls, ok := in.findClass(name)
	if !ok {
		panic(runtimeErr{"未定义的类：" + name})
	}
	obj := in.newObject(cls)
	in.initClass(obj, cls, args, sc)
	v := &Value{K: vObj, O: obj}
	in.addTemp(sc, obj)
	return v
}

// newObject 按继承链声明序登记字段并置零（§6.5 第 1 步）。
func (in *Interp) newObject(cls *xfront.ClassDecl) *objv {
	obj := &objv{cls: cls, fields: map[string]*Value{}}
	var chain []*xfront.ClassDecl
	for c := cls; c != nil; c = in.baseClass(c) {
		chain = append([]*xfront.ClassDecl{c}, chain...)
	}
	for _, c := range chain {
		for _, f := range c.Fields {
			key := fieldKey(f)
			obj.order = append(obj.order, key)
			obj.fields[key] = zeroValue(f.Type)
		}
	}
	return obj
}

// initClass 在已分配对象上执行某一层的构造：先父构造器，再主构造器绑定，
// 再本层字段初值，最后构造器体（§6.3/§6.5）。
func (in *Interp) initClass(obj *objv, cls *xfront.ClassDecl, args []*Value, caller *scope) {
	var ctor *xfront.CtorDecl
	if p := cls.Primary; p != nil {
		if len(args) != len(p.Params) {
			panic(runtimeErr{fmt.Sprintf("类 %s 的主构造器需要 %d 个参数，实际 %d 个", cls.Name, len(p.Params), len(args))})
		}
		ctor = p
	} else {
		for _, c := range cls.Ctors {
			if len(c.Params) == len(args) {
				ctor = c
				break
			}
		}
		if ctor == nil && (len(args) > 0 || len(cls.Ctors) > 0) {
			panic(runtimeErr{fmt.Sprintf("类 %s 没有匹配 %d 个参数的构造器（§6.3）", cls.Name, len(args))})
		}
	}
	superCall, skip := explicitSuper(ctor)
	if parent := in.baseClass(cls); parent != nil {
		var sargs []*Value
		if superCall != nil {
			cscope := in.ctorScope(obj, ctor, args, caller)
			sargs = make([]*Value, len(superCall.Args))
			for i, a := range superCall.Args {
				sargs[i] = in.eval(a, cscope)
			}
		}
		in.initClass(obj, parent, sargs, caller)
	} else if superCall != nil {
		panic(runtimeErr{"没有父类时不能调用 super(...)（§6.3）"})
	}
	// 主构造器参数在 super 之后绑定同名字段（§6.3）。
	if p := cls.Primary; p != nil {
		for i, prm := range p.Params {
			obj.fields[prm.Name] = args[i]
		}
	}
	// 本层字段初始化式在 super 之后、构造器体之前（§6.5 第 4 步）。
	selfScope := newScope(caller)
	selfScope.define("self", &Value{K: vObj, O: obj})
	for _, f := range cls.Fields {
		if f.Init == nil {
			continue
		}
		if cls.Primary != nil {
			if _, isPrimaryParam := primaryParam(cls, f.Name); isPrimaryParam {
				continue
			}
		}
		obj.fields[fieldKey(f)] = coerceByDecl(f.Type, in.eval(f.Init, selfScope))
	}
	if ctor != nil && ctor.Body != nil {
		in.execCtorBodySkip(obj, ctor, args, caller, skip)
	}
}

// explicitSuper 识别构造器体首条的 `super(...)`，返回调用与需跳过的语句数。
func explicitSuper(ctor *xfront.CtorDecl) (*xfront.Call, int) {
	if ctor == nil || ctor.Body == nil || len(ctor.Body.Stmts) == 0 {
		return nil, 0
	}
	es, ok := ctor.Body.Stmts[0].(*xfront.ExprStmt)
	if !ok {
		return nil, 0
	}
	call, ok := es.X.(*xfront.Call)
	if !ok {
		return nil, 0
	}
	id, ok := call.Callee.(*xfront.IdentExpr)
	if !ok || id.Name != "super" {
		return nil, 0
	}
	return call, 1
}

// execCtorBodySkip 执行构造器体，可跳过首条 super(...)（§6.3）。
func (in *Interp) execCtorBodySkip(obj *objv, c *xfront.CtorDecl, args []*Value, caller *scope, skip int) {
	defer func() {
		if r := recover(); r != nil {
			if _, ok := r.(ctrlReturn); ok {
				return // 构造器不返回值；sema 已禁止 return
			}
			panic(r)
		}
	}()
	sc := in.ctorScope(obj, c, args, caller)
	if c != nil {
		for i, prm := range c.Params {
			if i < len(args) {
				in.takeOwnership(sc, prm.Name, args[i])
			}
		}
	}
	body := c.Body
	if skip > 0 && skip <= len(body.Stmts) {
		body = &xfront.Block{P: body.P, Stmts: body.Stmts[skip:]}
	}
	in.execBlock(body, sc)
}

// ctorScope 绑定 self 与构造器参数，供 super(...) 实参求值。
func (in *Interp) ctorScope(obj *objv, ctor *xfront.CtorDecl, args []*Value, caller *scope) *scope {
	sc := newScope(caller)
	sc.define("self", &Value{K: vObj, O: obj})
	if ctor != nil {
		for i, prm := range ctor.Params {
			if i < len(args) {
				sc.defineTyped(prm.Name, prm.Type, args[i])
				in.takeOwnership(sc, prm.Name, args[i])
			} else {
				sc.defineTyped(prm.Name, prm.Type, &Value{K: vNull})
			}
		}
	}
	return sc
}

// fieldKey 是字段在运行期的存储键：私有字段用规范名 `_name`（§7.4）。
func fieldKey(f *xfront.FieldDecl) string {
	if f.Canonical != "" {
		return f.Canonical
	}
	// 直跑 interp.Run（未经 sema）时 Canonical 尚未物化，按 §7.4 现场归一。
	if strings.HasPrefix(f.Name, "_") {
		return f.Name
	}
	if f.Mod.Vis == "private" {
		return "_" + f.Name
	}
	return f.Name
}

// selfField 在 self 当前对象上解析裸字段名（§5.8：局部/参数优先，其次字段）。
func (in *Interp) selfField(sc *scope, name string) (*Value, bool) {
	sv, ok := sc.lookup("self")
	if !ok || sv.K != vObj {
		return nil, false
	}
	if v, ok := sv.O.fields[name]; ok {
		return v, true
	}
	if v, ok := sv.O.fields["_"+name]; ok {
		return v, true
	}
	return nil, false
}

// writeSelfField 写 self 上的裸字段名（§5.8/§7.4）。
func (in *Interp) writeSelfField(sc *scope, name string, v *Value) bool {
	sv, ok := sc.lookup("self")
	if !ok || sv.K != vObj {
		return false
	}
	if _, ok := sv.O.fields[name]; ok {
		sv.O.fields[name] = v
		return true
	}
	if _, ok := sv.O.fields["_"+name]; ok {
		sv.O.fields["_"+name] = v
		return true
	}
	return false
}

// primaryParam 判断字段是否为主构造器参数绑定。
func primaryParam(c *xfront.ClassDecl, field string) (*xfront.Param, bool) {
	if c.Primary == nil {
		return nil, false
	}
	for _, p := range c.Primary.Params {
		if p.Name == field {
			return p, true
		}
	}
	return nil, false
}

// callMethod 调用实例方法：绑定 self 与参数，恢复 ctrlReturn（含 defer 语义由 execBlock 承载）。
func (in *Interp) callMethod(obj *objv, name string, args []*Value, pos xfront.Pos) (*Value, error) {
	return in.callMethodFrom(obj.cls, obj, name, args, pos)
}

// callMethodFrom 从 start 类起静态查找实例方法（super.m() 用父类起点，§5.4）。
func (in *Interp) callMethodFrom(start *xfront.ClassDecl, obj *objv, name string, args []*Value, pos xfront.Pos) (v *Value, err error) {
	cands := in.findMethodsFrom(start, name)
	if len(cands) == 0 {
		panic(runtimeErr{"该类型没有成员方法 " + name + "：" + start.Name})
	}
	m := in.selectMethod(name, cands, args)
	declCls := in.declaringClass(start, m)
	defer func() {
		if r := recover(); r != nil {
			switch sig := r.(type) {
			case ctrlReturn:
				v, err = sig.v, nil
			case ctrlErr:
				v, err = &Value{K: vResult, R: sig.r}, nil
			case ctrlBreak, ctrlContinue:
				err = fmt.Errorf("break/continue 出现在循环或 switch 之外")
			case runtimeErr, fatal:
				panic(sig)
			default:
				panic(r)
			}
		}
	}()
	in.methodStack = append(in.methodStack, declCls)
	defer func() { in.methodStack = in.methodStack[:len(in.methodStack)-1] }()
	sc := newScope(in.globals)
	sc.define("self", &Value{K: vObj, O: obj})
	for i, prm := range m.Params {
		if i < len(args) {
			sc.defineTyped(prm.Name, prm.Type, args[i])
			in.takeOwnership(sc, prm.Name, args[i])
		} else {
			sc.defineTyped(prm.Name, prm.Type, &Value{K: vNull})
		}
	}
	if m.Body != nil {
		in.execBlock(m.Body, sc)
	}
	return &Value{K: vNull}, nil
}

// readMember 读实例字段（协议/类成员访问的公共入口）。
func (in *Interp) readMember(obj *objv, name string, pos xfront.Pos) *Value {
	if v, ok := obj.fields[name]; ok {
		return v
	}
	// 私有字段规范名：_name（S2 §7.4）
	if v, ok := obj.fields["_"+name]; ok {
		return v
	}
	panic(runtimeErr{"该类型没有字段 " + name + "：" + obj.cls.Name})
}

// writeMember 写实例字段（成员赋值，§7.4 可见性由 sema 守护）；引用字段强持有。
func (in *Interp) writeMember(obj *objv, name string, v *Value) {
	key := name
	if _, ok := obj.fields[key]; !ok {
		if _, ok := obj.fields["_"+name]; ok {
			key = "_" + name
		} else {
			panic(runtimeErr{"该类型没有字段 " + name + "：" + obj.cls.Name})
		}
	}
	in.setObjectField(obj, key, v)
}

// setObjectField 写对象字段并维护强持有计数（§4.4/§6.4）。
func (in *Interp) setObjectField(obj *objv, key string, v *Value) {
	old := obj.fields[key]
	var oldObj, newObj *objv
	if old != nil && old.K == vObj {
		oldObj = old.O
	}
	if v != nil && v.K == vObj {
		newObj = v.O
	}
	if oldObj != nil && oldObj != newObj {
		in.releaseObject(oldObj)
	}
	obj.fields[key] = v
	if newObj != nil && newObj != oldObj {
		newObj.escaped = false
		newObj.owners++
	}
}
