// statics.go：静态字段/静态方法与实例方法重载选择（S2 §6.8、§7.1、§7.2）。
package interp

import (
	"fmt"

	"xnull.dev/xnull/internal/xfront"
)

// registerStaticFields 在启动时为零值登记每个类自己的静态字段（§7.1）。
func (in *Interp) registerStaticFields(cls *xfront.ClassDecl) {
	m := in.staticVals[cls.Name]
	if m == nil {
		m = map[string]*Value{}
		in.staticVals[cls.Name] = m
	}
	for _, f := range cls.Fields {
		if f.Mod.Static {
			m[fieldKey(f)] = zeroValue(f.Type)
		}
	}
}

// initStaticFields 按类声明顺序执行静态字段初始化式（§7.1、§6.5 启动顺序）。
func (in *Interp) initStaticFields() {
	for _, cls := range in.classOrder {
		for _, f := range cls.Fields {
			if !f.Mod.Static || f.Init == nil {
				continue
			}
			prev := in.staticCtx
			in.staticCtx = cls
			v := coerceByDecl(f.Type, in.eval(f.Init, in.globals))
			in.staticCtx = prev
			in.staticVals[cls.Name][fieldKey(f)] = v
		}
	}
}

// findStaticField 从 cls 起沿基类链查静态字段（子类同名静态字段隐藏父类，§7.2）。
func (in *Interp) findStaticField(cls *xfront.ClassDecl, name string) (*Value, bool) {
	for c := cls; c != nil; c = in.baseClass(c) {
		for _, f := range c.Fields {
			if !f.Mod.Static {
				continue
			}
			if f.Name == name || f.Canonical == name || "_"+f.Name == name {
				return in.staticVals[c.Name][fieldKey(f)], true
			}
		}
	}
	return nil, false
}

func (in *Interp) writeStaticField(cls *xfront.ClassDecl, name string, v *Value) bool {
	for c := cls; c != nil; c = in.baseClass(c) {
		for _, f := range c.Fields {
			if !f.Mod.Static {
				continue
			}
			if f.Name == name || f.Canonical == name || "_"+f.Name == name {
				in.staticVals[c.Name][fieldKey(f)] = v
				return true
			}
		}
	}
	return false
}

// findMethods 收集继承链上的实例方法候选（同名重载；类继承本身无覆写）。
func (in *Interp) findMethods(cls *xfront.ClassDecl, name string) []*xfront.MethodDecl {
	return in.findMethodsFrom(cls, name)
}

func (in *Interp) findMethodsFrom(cls *xfront.ClassDecl, name string) []*xfront.MethodDecl {
	var out []*xfront.MethodDecl
	for c := cls; c != nil; c = in.baseClass(c) {
		for _, m := range c.Methods {
			if !m.Mod.Static && !m.IsDeinit && m.Name == name {
				out = append(out, m)
			}
		}
		// §11：扩展方法参与目标类型（含子类继承）的静态方法集合。
		for _, m := range in.extMethods[c.Name] {
			if !m.Mod.Static && m.Name == name {
				out = append(out, m)
			}
		}
	}
	return out
}

// declaringClass 返回方法 m 在 start 链上的声明类（super 起点/当前类栈）。
func (in *Interp) declaringClass(start *xfront.ClassDecl, m *xfront.MethodDecl) *xfront.ClassDecl {
	for c := start; c != nil; c = in.baseClass(c) {
		for _, x := range c.Methods {
			if x == m {
				return c
			}
		}
	}
	return start
}

func (in *Interp) currentClass() *xfront.ClassDecl {
	if len(in.methodStack) == 0 {
		return nil
	}
	return in.methodStack[len(in.methodStack)-1]
}

// findStaticMethods：子类同名静态方法隐藏父类同名集合（§7.2）。
func (in *Interp) findStaticMethods(cls *xfront.ClassDecl, name string) []*xfront.MethodDecl {
	for c := cls; c != nil; c = in.baseClass(c) {
		var out []*xfront.MethodDecl
		for _, m := range c.Methods {
			if m.Mod.Static && m.Name == name {
				out = append(out, m)
			}
		}
		if len(out) > 0 {
			return out
		}
	}
	return nil
}

// selectMethod 按实参数与类型选择重载（§6.8）：参数个数 + 类型可赋性 + 具体性打分。
func (in *Interp) selectMethod(name string, cands []*xfront.MethodDecl, args []*Value) *xfront.MethodDecl {
	var best *xfront.MethodDecl
	bestScore := -1
	for _, m := range cands {
		if len(m.Params) != len(args) {
			continue
		}
		okAll, score := true, 0
		for i, prm := range m.Params {
			if !in.typeMatches(prm.Type, args[i]) {
				okAll = false
				break
			}
			score += in.specificity(prm.Type, args[i])
		}
		if okAll && score > bestScore {
			best, bestScore = m, score
		}
	}
	if best == nil {
		panic(runtimeErr{fmt.Sprintf("方法 %s 没有匹配 %d 个实参的重载（§6.8）", name, len(args))})
	}
	return best
}

// specificity 用于在多个可适用重载中选更具体者（Any/Object < 协议 < 基类 < 精确类型）。
func (in *Interp) specificity(t xfront.TypeRef, v *Value) int {
	switch ty := t.(type) {
	case *xfront.SuffixedType:
		if v.K == vNull {
			return 1
		}
		return in.specificity(ty.Base, v)
	case *xfront.NamedType:
		name := lastQual(ty)
		switch name {
		case "Any", "Object":
			return 0
		case "Int", "Long", "Byte", "Short", "UByte", "UShort", "UInt", "ULong", "Int128", "UInt128",
			"Float", "Double", "Bool", "Char", "String", "Result", "List", "Map", "Set":
			return 3
		}
		if v.K == vObj {
			if v.O.enumName == name || (v.O.cls != nil && v.O.cls.Name == name) {
				return 4
			}
			d := 1
			for c := v.O.cls; c != nil; c = in.baseClass(c) {
				if c.Name == name {
					return 4 - d
				}
				d++
			}
			if in.implementsProtocol(v.O.cls, name) {
				return 2
			}
		}
		if v.K == vEnum && v.E == name {
			return 3
		}
		if v.K == vStruct && v.St.decl.Name == name {
			return 4
		}
		return 3
	}
	return 1
}

// callStatic 调用静态方法（无 self；静态上下文内裸静态名可解析）。
func (in *Interp) callStatic(cls *xfront.ClassDecl, name string, args []*Value, pos xfront.Pos) (v *Value, err error) {
	cands := in.findStaticMethods(cls, name)
	if len(cands) == 0 {
		panic(runtimeErr{"该类型没有静态方法 " + name + "：" + cls.Name})
	}
	m := in.selectMethod(name, cands, args)
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
	prev := in.staticCtx
	in.staticCtx = cls
	defer func() { in.staticCtx = prev }()
	sc := newScope(in.globals)
	for i, prm := range m.Params {
		if i < len(args) {
			sc.defineTyped(prm.Name, prm.Type, args[i])
		} else {
			sc.defineTyped(prm.Name, prm.Type, &Value{K: vNull})
		}
	}
	if m.Body != nil {
		in.execBlock(m.Body, sc)
	}
	return &Value{K: vNull}, nil
}
