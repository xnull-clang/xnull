// objects.go 是解释器的类/协议运行时（M4.4b）。
//
// 边界（裁决口径）：
//   - 内存由 Go GC 托管，**不做 ARC 时序模拟**；deinit 不自动触发（引用计数时序不可比，
//     双路径一致性只断言 stdout 与退出码）；
//   - 协议分派按对象实际类的方法名解析（§5 协议方法调用即按名分派，vtable 是 codegen 的实现细节）；
//   - 继承：单继承按基类链查找字段与方法；多级继承支持到基类链穷尽为止。
package interp

import (
	"fmt"

	"xnull.dev/xnull/internal/xfront"
)

// objv 是类实例：字段按声明序保存（保持确定性），cls 指向运行时类声明。
type objv struct {
	cls    *xfront.ClassDecl
	fields map[string]*Value
	order  []string
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

// evalNew 构造实例：先按主构造器绑定同名字段（§6.1），再按声明序求字段初值
// （无主构造器的形态同样走字段初值）。字段初值在实例作用域中求值（可引用 self）。
func (in *Interp) evalNew(n *xfront.New, sc *scope) *Value {
	nt, ok := n.Type.(*xfront.NamedType)
	if !ok {
		panic(runtimeErr{"new 的类型必须是命名类（S1 §7.1）"})
	}
	name := lastQual(nt)
	cls, ok := in.findClass(name)
	if !ok {
		panic(runtimeErr{"未定义的类：" + name})
	}
	obj := &objv{cls: cls, fields: map[string]*Value{}}
	// 字段声明序登记（含基类链，基类先）
	var chain []*xfront.ClassDecl
	for c := cls; c != nil; c = in.baseClass(c) {
		chain = append([]*xfront.ClassDecl{c}, chain...)
	}
	for _, c := range chain {
		for _, f := range c.Fields {
			obj.order = append(obj.order, f.Name)
			obj.fields[f.Name] = zeroValue(f.Type)
		}
	}
	selfScope := newScope(sc)
	selfScope.define("self", &Value{K: vObj, O: obj})

	// 主构造器：参数个数匹配时绑定同名字段（final Int id 形态）
	if p := cls.Primary; p != nil && len(p.Params) > 0 {
		if len(n.Args) != len(p.Params) {
			panic(runtimeErr{fmt.Sprintf("类 %s 的主构造器需要 %d 个参数，实际 %d 个", name, len(p.Params), len(n.Args))})
		}
		for i, prm := range p.Params {
			obj.fields[prm.Name] = in.eval(n.Args[i], sc)
		}
	} else if len(n.Args) > 0 {
		panic(runtimeErr{"类 " + name + " 没有带参构造器（§6.1）"})
	}
	// 字段初值（无初值的字段保留零值/主构造器绑定值）
	for _, c := range chain {
		for _, f := range c.Fields {
			if f.Init == nil {
				continue
			}
			if _, bound := obj.fields[f.Name]; bound && c.Primary != nil {
				// 主构造器已绑定同名字段：以参数为准（final 字段）
				if _, isPrimaryParam := primaryParam(c, f.Name); isPrimaryParam {
					continue
				}
			}
			obj.fields[f.Name] = coerceByDecl(f.Type, in.eval(f.Init, selfScope))
		}
	}
	return &Value{K: vObj, O: obj}
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
func (in *Interp) callMethod(obj *objv, name string, args []*Value, pos xfront.Pos) (v *Value, err error) {
	m, ok := in.findMethod(obj.cls, name)
	if !ok {
		panic(runtimeErr{"该类型没有成员方法 " + name + "：" + obj.cls.Name})
	}
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
	sc := newScope(in.globals)
	sc.define("self", &Value{K: vObj, O: obj})
	for i, prm := range m.Params {
		if i < len(args) {
			sc.define(prm.Name, args[i])
		} else {
			sc.define(prm.Name, &Value{K: vNull})
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

// writeMember 写实例字段（成员赋值，§7.4 可见性由 sema 守护）。
func (in *Interp) writeMember(obj *objv, name string, v *Value) {
	if _, ok := obj.fields[name]; ok {
		obj.fields[name] = v
		return
	}
	if _, ok := obj.fields["_"+name]; ok {
		obj.fields["_"+name] = v
		return
	}
	panic(runtimeErr{"该类型没有字段 " + name + "：" + obj.cls.Name})
}
