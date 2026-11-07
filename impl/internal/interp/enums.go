// enums.go 是解释器的枚举运行时（S2 §8）：简单枚举按底层 Int 值内联，
// 数据枚举项按单例对象构造并缓存；`Enum.Item` 由 evalMember 解析。
package interp

import (
	"fmt"

	"xnull.dev/xnull/internal/xfront"
)

// registerEnum 登记枚举并计算简单枚举的底层值（§8.2：显式值后裸项递增）。
func (in *Interp) registerEnum(d *xfront.EnumDecl) {
	in.enums[d.Name] = d
	vals := map[string]int64{}
	next := int64(0)
	for _, it := range d.Items {
		v := next
		if it.Value != nil {
			ev := in.eval(it.Value, in.globals)
			if ev.K != vInt {
				panic(runtimeErr{fmt.Sprintf("枚举 %s.%s 的值必须是 Int 字面量（§8.2）", d.Name, it.Name)})
			}
			v = ev.I
		}
		vals[it.Name] = v
		next = v + 1
	}
	in.enumVals[d.Name] = vals
	in.enumItems[d.Name] = map[string]*Value{}
}

// enumItem 解析 `Enum.Item`：简单枚举返回值对象，数据枚举惰性构造单例。
func (in *Interp) enumItem(d *xfront.EnumDecl, name string, pos xfront.Pos) *Value {
	cache := in.enumItems[d.Name]
	if cache == nil {
		cache = map[string]*Value{}
		in.enumItems[d.Name] = cache
	}
	if v, ok := cache[name]; ok {
		return v
	}
	var it *xfront.EnumItem
	for _, x := range d.Items {
		if x.Name == name {
			it = x
			break
		}
	}
	if it == nil {
		panic(runtimeErr{fmt.Sprintf("枚举 %s 没有项 %s（§8.4）", d.Name, name)})
	}
	if !d.IsData {
		v := &Value{K: vEnum, E: d.Name, S: it.Name, I: in.enumVals[d.Name][it.Name]}
		cache[name] = v
		return v
	}
	v := in.buildDataEnumItem(d, it)
	cache[name] = v
	return v
}

// buildDataEnumItem 构造数据枚举项：零值字段 → 字段初值 → 匹配构造器体（§8.3/§8.4）。
func (in *Interp) buildDataEnumItem(d *xfront.EnumDecl, it *xfront.EnumItem) *Value {
	cls := in.enumClass(d)
	obj := &objv{cls: cls, fields: map[string]*Value{}, enumName: d.Name, enumItem: it.Name}
	for _, f := range d.Fields {
		key := fieldKey(f)
		obj.order = append(obj.order, key)
		obj.fields[key] = zeroValue(f.Type)
	}
	v := &Value{K: vObj, O: obj}
	selfScope := newScope(in.globals)
	selfScope.defineTyped("self", nil, v)
	for _, f := range d.Fields {
		if f.Init != nil {
			obj.fields[fieldKey(f)] = coerceByDecl(f.Type, in.eval(f.Init, selfScope))
		}
	}
	var ctor *xfront.CtorDecl
	for _, c := range d.Ctors {
		if len(c.Params) == len(it.Args) {
			ctor = c
			break
		}
	}
	if ctor == nil {
		if len(it.Args) > 0 {
			panic(runtimeErr{fmt.Sprintf("枚举项 %s.%s 没有匹配 %d 个参数的构造器（§8.4）", d.Name, it.Name, len(it.Args))})
		}
		return v
	}
	args := make([]*Value, len(it.Args))
	for i, a := range it.Args {
		args[i] = in.eval(a, in.globals)
	}
	in.execCtorBody(obj, ctor, args)
	return v
}

// execCtorBody 在 self 作用域中执行枚举/类构造器体。
func (in *Interp) execCtorBody(obj *objv, c *xfront.CtorDecl, args []*Value) {
	in.execCtorBodySkip(obj, c, args, in.globals, 0)
}

// enumClass 为数据枚举生成合成 ClassDecl，使 callMethod/readMember 可复用。
func (in *Interp) enumClass(d *xfront.EnumDecl) *xfront.ClassDecl {
	if c, ok := in.enumCls[d.Name]; ok {
		return c
	}
	c := &xfront.ClassDecl{P: d.P, Name: d.Name, Fields: d.Fields, Methods: d.Methods, Ctors: d.Ctors}
	in.enumCls[d.Name] = c
	return c
}

// objectIsNamed：类继承链、数据枚举项、协议实现（含协议继承）。
func (in *Interp) objectIsNamed(o *objv, name string) bool {
	if o == nil || o.cls == nil {
		return false
	}
	if o.enumName != "" && o.enumName == name {
		return true
	}
	for c := o.cls; c != nil; c = in.baseClass(c) {
		if c.Name == name {
			return true
		}
	}
	return in.implementsProtocol(o.cls, name)
}

func (in *Interp) implementsProtocol(cls *xfront.ClassDecl, name string) bool {
	if _, ok := in.protocols[name]; !ok {
		return false
	}
	for c := cls; c != nil; c = in.baseClass(c) {
		for _, p := range c.Protocols {
			if in.protocolReaches(lastQual(p), name, map[string]bool{}) {
				return true
			}
		}
	}
	return false
}

func (in *Interp) protocolReaches(from, target string, seen map[string]bool) bool {
	if from == target {
		return true
	}
	if seen[from] {
		return false
	}
	seen[from] = true
	d, ok := in.protocols[from]
	if !ok {
		return false
	}
	for _, e := range d.Extends {
		if in.protocolReaches(lastQual(e), target, seen) {
			return true
		}
	}
	return false
}
