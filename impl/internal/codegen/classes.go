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
func (g *gen) collectClass(d *xfront.ClassDecl) error {
	if d.Base != nil {
		return fmt.Errorf("codegen：继承暂未支持（M4.4b 范围：单类；基类 %v）", d.Base)
	}
	if len(d.Protocols) > 0 {
		return fmt.Errorf("codegen：协议实现暂未支持（M4.4b 范围：单类无协议）")
	}
	ci := &classInfo{decl: d, cname: classCName(d.Name), typeVar: classTypeVar(d.Name), methods: map[string]*classInfo_m{}}
	// 先注册再填字段：自引用字段（List<Node> kids，AST 子节点）需要类名已可见
	g.classes[d.Name] = ci
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

// emitClassCtorBody 生成构造器里的字段初值语句（初值为编译期可求值的简单形态；
// 复杂初值在 M4.4b 只支持字面量/标量表达式，超出显式报错）。
func (g *gen) classCtorInit(ci *classInfo) ([]string, error) {
	var out []string
	for i, f := range ci.fields {
		fd := ci.decl.Fields[i]
		if fd.Init == nil {
			continue
		}
		switch {
		case f.isStr:
			if lit, ok := fd.Init.(*xfront.StrLitExpr); ok {
				t := g.tmpName()
				out = append(out, fmt.Sprintf("rt_string *%s = rt_string_from_c(%s);", t, cQuote(plainText(lit))))
				out = append(out, fmt.Sprintf("rt_release(o->%s);", f.cname))
				out = append(out, fmt.Sprintf("o->%s = %s;", f.cname, t))
				continue
			}
			return nil, fmt.Errorf("codegen：类字段 %s.%s 的 String 初值暂只支持字面量（M4.4b 范围）", ci.decl.Name, f.name)
		case f.ctype == "int64_t" || f.ctype == "int":
			sc := &scope{g: g, locals: map[string]string{}}
			v, err := sc.intExpr(fd.Init)
			if err != nil {
				return nil, err
			}
			out = append(out, fmt.Sprintf("o->%s = %s;", f.cname, v))
			continue
		case f.isArr:
			al, ok := fd.Init.(*xfront.ArrayLit)
			if !ok || len(al.Elems) != 0 {
				return nil, fmt.Errorf("codegen：类字段 %s.%s 的容器初值暂只支持空字面量 []（M5.1-b 范围）", ci.decl.Name, f.name)
			}
			out = append(out, fmt.Sprintf("o->%s = %s_new(0);", f.cname, f.ctype))
			continue
		case f.isCls:
			return nil, fmt.Errorf("codegen：类字段 %s.%s 不支持初值（引用字段只能后赋，M5.1-b 范围）", ci.decl.Name, f.name)
		}
		return nil, fmt.Errorf("codegen：类字段 %s.%s 的初值类型 %s 暂未支持（M4.4b 范围）", ci.decl.Name, f.name, f.ctype)
	}
	return out, nil
}

func (g *gen) tmpName() string { g.tmp++; return fmt.Sprintf("xn_c%d", g.tmp) }
