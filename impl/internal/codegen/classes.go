// classes.go 是 M4.4b 类代码生成：ARC 对象结构体 + 类型描述符 + 构造 + 方法。
//
// 表示（经 P-01/P-08 评审冻结面）：
//
//	typedef struct { rt_header hdr; <字段...> } xn_Cls_<Name>;
//	static const rt_type RT_TYPE_XN_<Name> = { "Name", sizeof(...), deinit, NULL };
//
// 内存：对象一律 ARC（rt_arc_new），字段中的 String 由 deinit 释放；含 GC 引用字段
// 的对象需要 scan（M5 GC 类型接入时补，本层显式报错）。
// 分派：方法按静态类型直接绑定（单态）；协议/基类多态（vtable）在继承与协议变量
// 接入时补——超出范围显式报错，不静默降级。
package codegen

import (
	"fmt"
	"sort"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

// classField 是类字段的生成信息。
type classField struct {
	name  string
	cname string // C 成员名（私有字段 _name）
	ctype string
	isStr bool
	isArr bool   // 容器值字段（xn_arr_/xn_set_/xn_map_ 值结构）
	isCls bool   // 类引用字段（xn_Cls_X *）
	elem  string // 容器元素 C 类型（isArr 时用于 deinit 释放；辅助记录）
}

// classInfo 是一个类的生成信息。
type classInfo struct {
	decl    *xfront.ClassDecl
	cname   string // xn_Cls_<Name>
	typeVar string // RT_TYPE_XN_<Name>
	fields  []classField
	methods map[string]*classInfo_m // 方法名 → 签名
}

type classInfo_m struct {
	decl  *xfront.MethodDecl
	cname string // xn_Cls_<Name>_<method>
}

// classCName 类名 → C 结构体名。
func classCName(name string) string         { return "xn_Cls_" + name }
func classTypeVar(name string) string       { return "RT_TYPE_XN_" + name }
func classMethodCName(cls, m string) string { return classCName(cls) + "_" + m }

// fieldCName 字段 C 成员名（私有字段规范名 _name 直接可用）。
func fieldCName(f *xfront.FieldDecl) string {
	if f.Canonical != "" {
		return f.Canonical
	}
	return f.Name
}

// collectClass 登记类（字段类型先解析，触发容器/Result 实例化注册）。
// 前置：EmitC 已预登记全部类名（`registerClassNames`），字段/方法可以引用后声明的类。
func (g *gen) collectClass(d *xfront.ClassDecl) error {
	if d.Base != nil {
		return fmt.Errorf("codegen：继承暂未支持（M4.4b 范围：单类；基类 %v）", d.Base)
	}
	if len(d.Protocols) > 0 {
		return fmt.Errorf("codegen：协议实现暂未支持（M4.4b 范围：单类无协议）")
	}
	ci := g.classes[d.Name]
	if ci == nil {
		ci = &classInfo{decl: d, cname: classCName(d.Name), typeVar: classTypeVar(d.Name), methods: map[string]*classInfo_m{}}
		g.classes[d.Name] = ci
	}
	ci.decl = d
	ci.fields = nil
	ci.methods = map[string]*classInfo_m{}
	for _, f := range d.Fields {
		ct, err := g.cType(f.Type)
		if err != nil {
			return err
		}
		ci.fields = append(ci.fields, classField{name: f.Name, cname: fieldCName(f), ctype: ct,
			isStr: ct == "rt_string *", isArr: isContainerC(ct), isCls: isClassPtr(ct)})
	}
	for _, m := range d.Methods {
		if m.IsDeinit {
			continue // deinit 归一到类型 deinit 钩子（字段释放已生成）
		}
		if _, ok := ci.methods[m.Name]; ok {
			return fmt.Errorf("codegen：类 %s 方法重名 %s（重载未支持，M4.4b 范围）", d.Name, m.Name)
		}
		ci.methods[m.Name] = &classInfo_m{decl: m, cname: classMethodCName(d.Name, m.Name)}
	}
	return nil
}

// needClass 确认类型名是已知类。
func (g *gen) classOf(name string) (*classInfo, bool) {
	ci, ok := g.classes[name]
	return ci, ok
}

// registerClassNames 预登记全部类名（顺序无关）：字段类型、字段初值 new、
// 方法签名都可能引用后声明的类（B0-04 前向引用）。
func (g *gen) registerClassNames(u *xfront.CompilationUnit) {
	for _, d := range u.Decls {
		if c, ok := d.(*xfront.ClassDecl); ok {
			if _, exists := g.classes[c.Name]; !exists {
				g.classes[c.Name] = &classInfo{decl: c, cname: classCName(c.Name),
					typeVar: classTypeVar(c.Name), methods: map[string]*classInfo_m{}}
			}
		}
	}
}

// emitClassForwardDecls 为全部类发前向声明（typedef struct X X; + 构造器原型），排序保证确定性。
// 输出顺序不变量：前向声明（此处）→ 容器结构 → 顶层函数原型 → 类完整定义。
// 多文件合并后使用方可先于定义方出现，指针形态只需该不完整类型即合法（S1-06）；
// 字段初值 `new B()` 也要求 B 的构造器原型先于 A 的构造器（B0-04）。
func (g *gen) emitClassForwardDecls(b *strings.Builder) {
	names := make([]string, 0, len(g.classes))
	for name := range g.classes {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		cn := classCName(name)
		fmt.Fprintf(b, "typedef struct %s %s;\n", cn, cn)
	}
	if len(names) > 0 {
		b.WriteString("\n")
	}
	for _, name := range names {
		cn := classCName(name)
		fmt.Fprintf(b, "static %s *%s_new(void);\n", cn, cn)
	}
	if len(names) > 0 {
		b.WriteString("\n")
	}
}

// emitClassStruct 生成结构体、类型描述符与构造器。
func (g *gen) emitClassStruct(b *strings.Builder, ci *classInfo) {
	fmt.Fprintf(b, "/* 类 %s（M4.4b） */\n", ci.decl.Name)
	fmt.Fprintf(b, "typedef struct %s {\n    rt_header hdr;\n", ci.cname)
	for _, f := range ci.fields {
		fmt.Fprintf(b, "    %s %s;\n", f.ctype, f.cname)
	}
	b.WriteString("} " + ci.cname + ";\n\n")

	// deinit：按字段类别释放（String 引用 / 容器值 / 类引用）
	fmt.Fprintf(b, "static void %s_deinit(void *p) {\n", ci.cname)
	fmt.Fprintf(b, "    %s *o = (%s *)p;\n", ci.cname, ci.cname)
	for _, f := range ci.fields {
		switch {
		case f.isStr:
			fmt.Fprintf(b, "    rt_release(o->%s);\n", f.cname)
		case f.isArr:
			fmt.Fprintf(b, "    %s_free(&o->%s);\n", f.ctype, f.cname)
		case f.isCls:
			fmt.Fprintf(b, "    rt_release(o->%s);\n", f.cname)
		}
	}
	b.WriteString("}\n\n")
	fmt.Fprintf(b, "static const rt_type %s = { %q, sizeof(%s), %s_deinit, NULL };\n\n",
		ci.typeVar, ci.decl.Name, ci.cname, ci.cname)

}

// emitClassCtor 生成构造器（第二遍：字段初值语句已可生成）。
func (g *gen) emitClassCtor(b *strings.Builder, ci *classInfo) error {
	inits, err := g.classCtorInit(ci)
	if err != nil {
		return err
	}
	fmt.Fprintf(b, "static %s *%s_new(void) {\n", ci.cname, ci.cname)
	fmt.Fprintf(b, "    %s *o = (%s *)rt_arc_new(&%s);\n", ci.cname, ci.cname, ci.typeVar)
	b.WriteString("    memset((char *)o + sizeof(rt_header), 0, sizeof(" + ci.cname + ") - sizeof(rt_header));\n")
	for _, l := range inits {
		b.WriteString("    " + l + "\n")
	}
	b.WriteString("    return o;\n}\n\n")
	return nil
}

// methodProto 生成方法前向声明。
func (g *gen) methodProto(ci *classInfo, m *classInfo_m) (string, error) {
	retC := "void"
	if !m.decl.Void {
		c, err := g.cType(m.decl.Ret)
		if err != nil {
			return "", err
		}
		retC = c
	}
	var b strings.Builder
	fmt.Fprintf(&b, "static %s %s(%s *self", retC, m.cname, ci.cname)
	for _, p := range m.decl.Params {
		pc, err := g.cType(p.Type)
		if err != nil {
			return "", err
		}
		fmt.Fprintf(&b, ", %s xn_p_%s", pc, p.Name)
	}
	b.WriteString(");")
	return b.String(), nil
}

// genMethod 生成实例方法：self 指针首参，方法体内 self 直接可见。
func (g *gen) genMethod(ci *classInfo, m *classInfo_m) (string, error) {
	retC := "void"
	if !m.decl.Void {
		c, err := g.cType(m.decl.Ret)
		if err != nil {
			return "", err
		}
		retC = c
	}
	var b strings.Builder
	fmt.Fprintf(&b, "static %s %s(%s *self", retC, m.cname, ci.cname)
	for _, p := range m.decl.Params {
		pc, err := g.cType(p.Type)
		if err != nil {
			return "", err
		}
		fmt.Fprintf(&b, ", %s xn_p_%s", pc, p.Name)
	}
	b.WriteString(") {\n")
	locals := map[string]string{"self": ci.cname + " *"}
	pnames := map[string]bool{}
	for _, p := range m.decl.Params {
		pnames[p.Name] = true
		if pc, err := g.cType(p.Type); err == nil {
			locals[p.Name] = pc
		}
	}
	sc := &scope{g: g, retC: retC, params: pnames, locals: locals}
	body, err := sc.emitBlock(m.decl.Body.Stmts)
	if err != nil {
		return "", err
	}
	b.WriteString(body)
	if retC != "void" {
		b.WriteString("    return (" + retC + ")0; /* sema 保证不可达（函数体全路径 return） */\n")
	}
	b.WriteString("}\n")
	return b.String(), nil
}

func cZeroValue(ct string) string {
	switch ct {
	case "rt_string *":
		return "NULL"
	default:
		return "0"
	}
}

// classCtorInit 生成构造器里的字段初值语句（S2 §6.3 L678-679）：
// 按声明顺序执行；初值可引用常量/静态成员/顶层函数，不得引用 self、其他实例字段或构造器参数。
// 生成形态覆盖：标量表达式、String 表达式（拼接/str/顶层调用）、容器字面量（含非空与空）、
// 类引用 new。借用形态（字段/局部引用）显式拒绝，避免双重释放。
func (g *gen) classCtorInit(ci *classInfo) ([]string, error) {
	var out []string
	sc := &scope{g: g, locals: map[string]string{}}
	for i := range ci.fields {
		f := ci.fields[i]
		fd := ci.decl.Fields[i]
		if fd.Init == nil {
			continue
		}
		if err := g.validateFieldInit(fd.Init, ci.decl.Name, f.name); err != nil {
			return nil, err
		}
		// 上一字段求值可能留下临时语句（顶层调用/拼接）
		out = append(out, sc.pending...)
		sc.pending = nil
		lines, expr, err := g.fieldInitValue(sc, f, fd.Init, ci.decl.Name)
		if err != nil {
			return nil, err
		}
		out = append(out, lines...)
		out = append(out, sc.pending...)
		sc.pending = nil
		switch {
		case f.isStr:
			// 旧值为 memset 的 NULL，release 幂等（rt_release 对 NULL 直接返回）
			out = append(out, fmt.Sprintf("rt_release(o->%s);", f.cname))
		case f.isCls:
			out = append(out, fmt.Sprintf("rt_release(o->%s);", f.cname))
		}
		out = append(out, fmt.Sprintf("o->%s = %s;", f.cname, expr))
	}
	return out, nil
}

// fieldInitValue 为单个字段初值生成 (语句, 右值表达式)。
func (g *gen) fieldInitValue(sc *scope, f classField, init xfront.Expr, cls string) ([]string, string, error) {
	switch {
	case f.isStr:
		lines, err := sc.strExpr(init)
		if err != nil {
			return nil, "", err
		}
		return lines, lastVar(lines), nil
	case f.isArr:
		// `Map<K,V> m = []`：空数组字面量是空 Map 的常用写法，按 map_new(0) 发射。
		if al, ok := init.(*xfront.ArrayLit); ok && len(al.Elems) == 0 && strings.HasPrefix(f.ctype, "xn_map_") {
			return nil, fmt.Sprintf("%s_new(0)", f.ctype), nil
		}
		lines, v, err := sc.valExpr(init, f.ctype)
		if err != nil {
			return nil, "", err
		}
		if _, isIdent := init.(*xfront.IdentExpr); isIdent {
			return nil, "", fmt.Errorf("codegen：类字段 %s.%s 的容器初值不能是借用（变量/字段），需字面量或构造（B0-04）", cls, f.name)
		}
		return lines, v, nil
	case f.isCls:
		nw, ok := init.(*xfront.New)
		if !ok {
			return nil, "", fmt.Errorf("codegen：类字段 %s.%s 的引用初值只支持 `new 类()`（B0-04；不得引用 self/其他字段）", cls, f.name)
		}
		ctor, err := sc.emitNewClass(nw)
		if err != nil {
			return nil, "", err
		}
		return nil, ctor, nil
	case f.ctype == "int64_t" || f.ctype == "int" || f.ctype == "bool":
		v, err := sc.intExpr(init)
		if err != nil {
			return nil, "", err
		}
		return nil, v, nil
	}
	return nil, "", fmt.Errorf("codegen：类字段 %s.%s 的初值类型 %s 暂未支持（B0-04）", cls, f.name, f.ctype)
}

// validateFieldInit 静态校验字段初值（S2 §6.3 L679）：
// 允许 字面量 / 运算符 / 容器与 Map 字面量 / new / 以顶层函数或内建为被调用的 Call；
// 拒绝 裸标识符（字段/局部/参数引用）、成员访问（self.x、obj.x）、下标、元组成员、闭包。
func (g *gen) validateFieldInit(e xfront.Expr, cls, field string) error {
	bad := func(what string) error {
		return fmt.Errorf("codegen：类字段 %s.%s 的初始化式%s（S2 §6.3：字段初值不能引用 self、其他实例字段或构造器参数）", cls, field, what)
	}
	switch n := e.(type) {
	case *xfront.IntLitExpr, *xfront.FloatLitExpr, *xfront.CharLitExpr,
		*xfront.BoolLit, *xfront.NullLit, *xfront.StrLitExpr:
		return nil
	case *xfront.Paren:
		return g.validateFieldInit(n.X, cls, field)
	case *xfront.Unary:
		return g.validateFieldInit(n.X, cls, field)
	case *xfront.Binary:
		if err := g.validateFieldInit(n.L, cls, field); err != nil {
			return err
		}
		return g.validateFieldInit(n.R, cls, field)
	case *xfront.Ternary:
		if err := g.validateFieldInit(n.Cond, cls, field); err != nil {
			return err
		}
		if err := g.validateFieldInit(n.Then, cls, field); err != nil {
			return err
		}
		return g.validateFieldInit(n.Else, cls, field)
	case *xfront.ArrayLit:
		for _, el := range n.Elems {
			if err := g.validateFieldInit(el, cls, field); err != nil {
				return err
			}
		}
		return nil
	case *xfront.MapLit:
		for i := range n.Keys {
			if err := g.validateFieldInit(n.Keys[i], cls, field); err != nil {
				return err
			}
			if err := g.validateFieldInit(n.Vals[i], cls, field); err != nil {
				return err
			}
		}
		return nil
	case *xfront.New:
		for _, a := range n.Args {
			if err := g.validateFieldInit(a, cls, field); err != nil {
				return err
			}
		}
		return nil
	case *xfront.Call:
		if _, ok := n.Callee.(*xfront.IdentExpr); !ok {
			return bad("调用了成员方法（只允许顶层函数/内建）")
		}
		for _, a := range n.Args {
			if err := g.validateFieldInit(a, cls, field); err != nil {
				return err
			}
		}
		return nil
	case *xfront.IdentExpr:
		return bad("引用了标识符 `" + n.Name + "`（不能引用 self、字段、参数或局部）")
	case *xfront.Member:
		return bad("访问了成员 `" + n.Name + "`（不能引用 self 或其他实例字段）")
	}
	return bad(fmt.Sprintf("形态 %T 不受支持", e))
}
