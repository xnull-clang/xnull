// struct.go：结构体值类型发射（S2 §3）。
//
// 表示：无对象头、无 vtable 的按值 C 结构体。赋值/传参/返回都是 C 结构体复制，
// 天然满足 §3.3 值语义。方法接收者用 `T *self`（静态派发）。
package codegen

import (
	"fmt"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

// collectStructs 把 struct 装配成类结构（cname=xn_Struct_<Name>，无基类/协议）。
func (g *gen) collectStructs(u *xfront.CompilationUnit) error {
	decls := map[string]*xfront.StructDecl{}
	for _, d := range u.Decls {
		if sd, ok := d.(*xfront.StructDecl); ok {
			decls[sd.Name] = sd
		}
	}
	var build func(name string) error
	building := map[string]bool{}
	build = func(name string) error {
		if _, ok := g.structs[name]; ok {
			return nil
		}
		sd, ok := decls[name]
		if !ok {
			return fmt.Errorf("codegen：未定义的结构体 %s", name)
		}
		if building[name] {
			return fmt.Errorf("codegen：结构体递归值包含 %s（S2 §3.2）", name)
		}
		building[name] = true
		syn := &xfront.ClassDecl{Name: sd.Name, Fields: sd.Fields, Methods: sd.Methods, Ctors: sd.Ctors}
		ci := &classInfo{decl: syn, cname: "xn_Struct_" + sd.Name,
			typeVar: "RT_TYPE_XN_STRUCT_" + sd.Name, methods: map[string]*classInfo_m{},
			ctors: sd.Ctors, primary: sd.Primary, ctorName: map[*xfront.CtorDecl]string{}}
		// 先登记占位，保证字段内嵌套 struct 的 cType 可解析。
		g.structs[sd.Name] = ci
		for _, f := range sd.Fields {
			if st, ok := f.Type.(*xfront.NamedType); ok {
				if _, isStruct := decls[typeName(st)]; isStruct {
					if err := build(typeName(st)); err != nil {
						return err
					}
				}
			}
			ct, err := g.cType(f.Type)
			if err != nil {
				return err
			}
			ci.fields = append(ci.fields, classField{name: f.Name, cname: fieldCName(f), ctype: ct, init: f.Init})
		}
		var ctorList []*xfront.CtorDecl
		if sd.Primary != nil {
			ctorList = append(ctorList, sd.Primary)
		}
		ctorList = append(ctorList, sd.Ctors...)
		for i, c := range ctorList {
			n := ci.cname + "_new"
			if i > 0 {
				n = fmt.Sprintf("%s_new_%d", ci.cname, i)
			}
			ci.ctorName[c] = n
		}
		for _, m := range sd.Methods {
			if m.IsDeinit {
				return fmt.Errorf("codegen：结构体不能声明 deinit（S2 §3.1）")
			}
			if _, dup := ci.methods[m.Name]; dup {
				return fmt.Errorf("codegen：结构体 %s 方法重名 %s", sd.Name, m.Name)
			}
			ci.methods[m.Name] = &classInfo_m{decl: m, cname: ci.cname + "_" + m.Name, owner: ci}
		}
		ci.collected = true
		building[name] = false
		return nil
	}
	for _, d := range u.Decls {
		if sd, ok := d.(*xfront.StructDecl); ok {
			if err := build(sd.Name); err != nil {
				return err
			}
		}
	}
	return nil
}

// isStructC 判断 C 类型是否为结构体值类型。
func (g *gen) isStructC(c string) bool {
	return strings.HasPrefix(c, "xn_Struct_")
}

// structOfC 反查结构体信息（允许 self 指针类型 "T *"）。
func (g *gen) structOfC(c string) (*classInfo, bool) {
	name := strings.TrimSuffix(strings.TrimPrefix(c, "xn_Struct_"), " *")
	ci, ok := g.structs[name]
	return ci, ok
}

// structSep 结构体字段访问分隔符（值类型 "."，self 指针 "->"）。
func structSep(c string) string {
	if strings.HasSuffix(c, " *") {
		return "->"
	}
	return "."
}

// structCtor 按类型与实参个数选构造器。
func (ci *classInfo) structCtorByArity(argc int) *xfront.CtorDecl {
	var list []*xfront.CtorDecl
	if ci.primary != nil {
		list = append(list, ci.primary)
	}
	list = append(list, ci.ctors...)
	for _, c := range list {
		if len(c.Params) == argc {
			return c
		}
	}
	return nil
}

// emitStructTypes 输出结构体 typedef 与构造器（返回值语义）。
func (g *gen) emitStructTypes(b *strings.Builder) error {
	names := make([]string, 0, len(g.structs))
	for n := range g.structs {
		names = append(names, n)
	}
	sortStrings(names)
	for _, n := range names {
		ci := g.structs[n]
		fmt.Fprintf(b, "typedef struct %s {\n", ci.cname)
		for _, f := range ci.fields {
			fmt.Fprintf(b, "    %s %s;\n", f.ctype, f.cname)
		}
		b.WriteString("} " + ci.cname + ";\n\n")
	}
	for _, n := range names {
		ci := g.structs[n]
		var ctors []*xfront.CtorDecl
		if ci.primary != nil {
			ctors = append(ctors, ci.primary)
		}
		ctors = append(ctors, ci.ctors...)
		if len(ctors) == 0 {
			// 隐式无参构造器：字段初值后返回。
			fmt.Fprintf(b, "static %s %s_new(void) {\n", ci.cname, ci.cname)
			fmt.Fprintf(b, "    %s self = (%s){0};\n", ci.cname, ci.cname)
			inits, err := g.structCtorInit(ci)
			if err != nil {
				return err
			}
			for _, l := range inits {
				b.WriteString("    " + l + "\n")
			}
			b.WriteString("    return self;\n}\n\n")
			continue
		}
		for _, c := range ctors {
			parts, pnames, locals, err := g.ctorParamDecls(c)
			if err != nil {
				return err
			}
			fmt.Fprintf(b, "static %s %s(%s) {\n", ci.cname, ci.ctorName[c], strings.Join(parts, ", "))
			fmt.Fprintf(b, "    %s self = (%s){0};\n", ci.cname, ci.cname)
			inits, err := g.structCtorInit(ci)
			if err != nil {
				return err
			}
			for _, l := range inits {
				b.WriteString("    " + l + "\n")
			}
			if c == ci.primary {
				for _, p := range c.Params {
					fmt.Fprintf(b, "    self.%s = xn_p_%s;\n", p.Name, p.Name)
				}
			}
			if c.Body != nil {
				sc := &scope{g: g, retC: "void", params: pnames, locals: locals, self: newSelfCtx(ci)}
				sc.self.cvar = "self"
				sc.self.value = true
				body, err := sc.emitBlock(c.Body.Stmts)
				if err != nil {
					return err
				}
				b.WriteString(body)
			}
			b.WriteString("    return self;\n}\n\n")
		}
	}
	return nil
}

// structCtorInit 字段初值（值字段，无 release）。
func (g *gen) structCtorInit(ci *classInfo) ([]string, error) {
	var out []string
	sc := &scope{g: g, locals: map[string]string{}}
	for _, f := range ci.fields {
		if f.init == nil {
			continue
		}
		if err := g.validateFieldInit(f.init, ci.decl.Name, f.name); err != nil {
			return nil, err
		}
		lines, expr, err := g.fieldInitValue(sc, f, f.init, ci.decl.Name)
		if err != nil {
			return nil, err
		}
		out = append(out, lines...)
		out = append(out, sc.pending...)
		sc.pending = nil
		out = append(out, fmt.Sprintf("self.%s = %s;", f.cname, expr))
	}
	return out, nil
}

// emitStructBodies 输出结构体方法。
func (g *gen) emitStructBodies(b *strings.Builder) error {
	names := make([]string, 0, len(g.structs))
	for n := range g.structs {
		names = append(names, n)
	}
	sortStrings(names)
	for _, n := range names {
		ci := g.structs[n]
		for _, md := range ci.decl.Methods {
			m := ci.methods[md.Name]
			proto, err := g.methodProto(ci, m)
			if err != nil {
				return err
			}
			b.WriteString(proto + "\n")
		}
		b.WriteString("\n")
		for _, md := range ci.decl.Methods {
			mc, err := g.genMethod(ci, ci.methods[md.Name])
			if err != nil {
				return err
			}
			b.WriteString(mc + "\n")
		}
	}
	return nil
}

// structCtorCall 生成结构体构造调用（无显式构造器时用隐式无参构造）。
func (sg *gen) structCtorCall(ci *classInfo, argc int, args []string) (string, error) {
	if ci.structCtorByArity(argc) == nil {
		if argc != 0 || len(ci.ctors) > 0 || ci.primary != nil {
			return "", fmt.Errorf("codegen：结构体 %s 没有 %d 个参数的构造器（S2 §3.5）", ci.decl.Name, argc)
		}
		return ci.cname + "_new()", nil
	}
	c := ci.structCtorByArity(argc)
	return ci.ctorName[c] + "(" + strings.Join(args, ", ") + ")", nil
}

// structValue 生成结构体值表达式；+值语义（C 结构体赋值）。
func (s *scope) structValue(e xfront.Expr, tc string) ([]string, string, error) {
	switch n := e.(type) {
	case *xfront.New:
		nt, ok := n.Type.(*xfront.NamedType)
		if !ok {
			return nil, "", fmt.Errorf("codegen：new 的结构体类型必须是命名类型")
		}
		ci, ok := s.g.structs[typeName(nt)]
		if !ok {
			return nil, "", fmt.Errorf("codegen：未定义的结构体 %s", typeName(nt))
		}
		args, err := s.callArgs(n.Args)
		if err != nil {
			return nil, "", err
		}
		lines := append([]string{}, s.pending...)
		s.pending = nil
		call, err := s.g.structCtorCall(ci, len(n.Args), args)
		if err != nil {
			return nil, "", err
		}
		return lines, call, nil
	case *xfront.IdentExpr:
		return nil, s.cRef(n.Name), nil
	case *xfront.Paren:
		return s.structValue(n.X, tc)
	case *xfront.Call:
		if id, ok := n.Callee.(*xfront.IdentExpr); ok {
			if s.self != nil && s.params != nil && !s.params[id.Name] {
				if _, local := s.locals[id.Name]; !local {
					if m, ok := s.self.ci.methodOf(id.Name); ok {
						if rc, err := s.g.methodRetC(m); err == nil && rc == tc {
							expr, err := s.methodCall(s.self.ci, m, s.self.cvar, n.Args)
							if err != nil {
								return nil, "", err
							}
							lines := append([]string{}, s.pending...)
							s.pending = nil
							return lines, expr, nil
						}
					}
				}
			}
			args, err := s.callArgs(n.Args)
			if err != nil {
				return nil, "", err
			}
			cn, err := s.g.callName(id.Name, n.TypeArgs, len(n.Args))
			if err != nil {
				return nil, "", err
			}
			lines := append([]string{}, s.pending...)
			s.pending = nil
			return lines, cn + "(" + strings.Join(args, ", ") + ")", nil
		}
		if mem, ok := n.Callee.(*xfront.Member); ok {
			rn, rc, err := recvCName(mem.X, s)
			if err != nil {
				return nil, "", err
			}
			if s.g.isStructC(rc) {
				ci, _ := s.g.structOfC(rc)
				m, ok := ci.methodOf(mem.Name)
				if !ok {
					return nil, "", fmt.Errorf("codegen：结构体 %s 没有方法 %s", ci.decl.Name, mem.Name)
				}
				expr, err := s.methodCall(ci, m, "(&"+rn+")", n.Args)
				if err != nil {
					return nil, "", err
				}
				lines := append([]string{}, s.pending...)
				s.pending = nil
				return lines, expr, nil
			}
		}
	}
	return nil, "", fmt.Errorf("codegen：结构体值 %T 未支持（S2 §3）", e)
}

func sortStrings(in []string) {
	for i := 1; i < len(in); i++ {
		for j := i; j > 0 && in[j] < in[j-1]; j-- {
			in[j], in[j-1] = in[j-1], in[j]
		}
	}
}
