// structs.go：结构体值语义（S2 §3）：构造、字段、方法、复制独立性。
package interp

import (
	"fmt"

	"xnull.dev/xnull/internal/xfront"
)

// structv 是结构体运行值（无对象头/身份；赋值时整体复制）。
type structv struct {
	decl   *xfront.StructDecl
	fields map[string]*Value
	order  []string
}

// structTypeOf 解析结构体类型引用。
func (in *Interp) structTypeOf(t xfront.TypeRef) (*xfront.StructDecl, bool) {
	nt, ok := t.(*xfront.NamedType)
	if !ok {
		return nil, false
	}
	st, ok := in.structs[lastQual(nt)]
	return st, ok
}

// zeroOf 返回声明类型的零值（struct 递归构造，§3.3）。
func (in *Interp) zeroOf(t xfront.TypeRef) *Value {
	if st, ok := in.structTypeOf(t); ok {
		return in.zeroStruct(st)
	}
	return zeroValue(t)
}

func (in *Interp) zeroStruct(st *xfront.StructDecl) *Value {
	s := &structv{decl: st, fields: map[string]*Value{}}
	for _, f := range st.Fields {
		key := fieldKey(f)
		s.order = append(s.order, key)
		s.fields[key] = in.zeroOf(f.Type)
	}
	return &Value{K: vStruct, St: s}
}

// newStruct 执行结构体构造：字段初值 → 构造器体（§3.5）；无非空构造器时生成无参构造。
func (in *Interp) newStruct(st *xfront.StructDecl, args []*Value, caller *scope) *Value {
	s := &structv{decl: st, fields: map[string]*Value{}}
	for _, f := range st.Fields {
		key := fieldKey(f)
		s.order = append(s.order, key)
		s.fields[key] = in.zeroOf(f.Type)
	}
	self := &Value{K: vStruct, St: s}
	var ctor *xfront.CtorDecl
	if p := st.Primary; p != nil {
		if len(args) != len(p.Params) {
			panic(runtimeErr{fmt.Sprintf("结构体 %s 的主构造器需要 %d 个参数，实际 %d 个", st.Name, len(p.Params), len(args))})
		}
		ctor = p
	} else {
		for _, c := range st.Ctors {
			if len(c.Params) == len(args) {
				ctor = c
				break
			}
		}
		if ctor == nil && (len(args) > 0 || len(st.Ctors) > 0) {
			panic(runtimeErr{fmt.Sprintf("结构体 %s 没有匹配 %d 个参数的构造器（§3.5）", st.Name, len(args))})
		}
	}
	selfScope := newScope(caller)
	selfScope.defineTyped("self", nil, self)
	for _, f := range st.Fields {
		if f.Init == nil {
			continue
		}
		if st.Primary != nil {
			if _, bound := primaryParamIn(st.Primary.Params, f.Name); bound {
				continue
			}
		}
		s.fields[fieldKey(f)] = cloneTupleValue(in.eval(f.Init, selfScope))
	}
	if p := st.Primary; p != nil {
		for i, prm := range p.Params {
			s.fields[prm.Name] = cloneTupleValue(args[i])
		}
	}
	if ctor != nil && ctor.Body != nil {
		in.execStructCtorBody(s, ctor, args, caller)
	}
	return self
}

// primaryParam 在参数表中按名查找（结构体主构造器绑定）。
func primaryParamIn(params []*xfront.Param, name string) (*xfront.Param, bool) {
	for _, p := range params {
		if p.Name == name {
			return p, true
		}
	}
	return nil, false
}

func (in *Interp) execStructCtorBody(s *structv, c *xfront.CtorDecl, args []*Value, caller *scope) {
	defer func() {
		if r := recover(); r != nil {
			if _, ok := r.(ctrlReturn); ok {
				return
			}
			panic(r)
		}
	}()
	sc := newScope(caller)
	sc.defineTyped("self", nil, &Value{K: vStruct, St: s})
	for i, prm := range c.Params {
		if i < len(args) {
			sc.defineTyped(prm.Name, prm.Type, args[i])
		} else {
			sc.defineTyped(prm.Name, prm.Type, &Value{K: vNull})
		}
	}
	in.execBlock(c.Body, sc)
}

func (in *Interp) findStructMethod(st *xfront.StructDecl, name string) []*xfront.MethodDecl {
	var out []*xfront.MethodDecl
	for _, m := range st.Methods {
		if !m.Mod.Static && !m.IsDeinit && m.Name == name {
			out = append(out, m)
		}
	}
	// §11：struct 扩展方法。
	for _, m := range in.extMethods[st.Name] {
		if !m.Mod.Static && m.Name == name {
			out = append(out, m)
		}
	}
	return out
}

// callStructMethod 调用结构体方法；self 指向接收者存储槽（写入方法修改接收者）。
func (in *Interp) callStructMethod(s *structv, name string, args []*Value, pos xfront.Pos) (v *Value, err error) {
	cands := in.findStructMethod(s.decl, name)
	if len(cands) == 0 {
		panic(runtimeErr{"该结构体没有成员方法 " + name + "：" + s.decl.Name})
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
	sc := newScope(in.globals)
	sc.define("self", &Value{K: vStruct, St: s})
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

func (in *Interp) readStructMember(s *structv, name string) *Value {
	if v, ok := s.fields[name]; ok {
		return v
	}
	if v, ok := s.fields["_"+name]; ok {
		return v
	}
	panic(runtimeErr{"该结构体没有字段 " + name + "：" + s.decl.Name})
}

func (in *Interp) writeStructMember(s *structv, name string, v *Value) {
	if _, ok := s.fields[name]; ok {
		s.fields[name] = v
		return
	}
	if _, ok := s.fields["_"+name]; ok {
		s.fields["_"+name] = v
		return
	}
	panic(runtimeErr{"该结构体没有字段 " + name + "：" + s.decl.Name})
}
