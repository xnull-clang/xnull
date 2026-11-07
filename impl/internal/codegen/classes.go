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
	name     string
	cname    string // C 成员名（私有字段 _name）
	ctype    string
	isStr    bool
	isArr    bool        // 容器值字段（xn_arr_/xn_set_/xn_map_ 值结构）
	isCls    bool        // 类引用字段（xn_Cls_X *）
	isHandle bool        // 不透明句柄字段（xrt_handle *）
	isBytes  bool        // 可变字节缓冲字段（xrt_bytes_obj *）
	elem     string      // 容器元素 C 类型（isArr 时用于 deinit 释放；辅助记录）
	init     xfront.Expr // 字段初始化式（可空；主构造器字段无初值）
}

// isRefField 判断字段是否持有 ARC 引用（deinit/赋值需 retain/release）。
func (f classField) isRefField() bool {
	return f.isStr || f.isCls || f.isHandle || f.isBytes
}

// classInfo 是一个类的生成信息。
type classInfo struct {
	decl       *xfront.ClassDecl
	cname      string // xn_Cls_<Name>
	typeVar    string // RT_TYPE_XN_<Name>
	base       *classInfo
	protocols  []*xfront.NamedType
	vptr       bool // 协议 vtable 指针槽（S2 §5.7）
	fields     []classField
	methods    map[string]*classInfo_m // 方法名 → 签名
	ctors      []*xfront.CtorDecl      // 普通构造器（S2 §6.3）
	primary    *xfront.CtorDecl        // 主构造器
	ctorName   map[*xfront.CtorDecl]string
	deinit     *classInfo_m // 用户 deinit 体（静态派发，先于字段释放）
	collected  bool
	collecting bool
}

type classInfo_m struct {
	decl  *xfront.MethodDecl
	cname string // xn_Cls_<Name>_<method>
	owner *classInfo
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
	ci := g.classes[d.Name]
	if ci == nil {
		ci = &classInfo{decl: d, cname: classCName(d.Name), typeVar: classTypeVar(d.Name), methods: map[string]*classInfo_m{}}
		g.classes[d.Name] = ci
	}
	if ci.collected {
		return nil
	}
	if ci.collecting {
		return fmt.Errorf("codegen：继承环（类 %s）", d.Name)
	}
	ci.collecting = true
	defer func() { ci.collecting = false }()
	// 单继承布局（S2 §2.5/§5.1）：父类字段按声明序前置（逻辑父类子对象），
	// 子类字段追加；父类方法经 methodOf 链式可见（静态派发）。
	if d.Base != nil {
		nt, ok := d.Base.(*xfront.NamedType)
		if !ok {
			return fmt.Errorf("codegen：父类必须是命名类（%T）", d.Base)
		}
		bname := typeName(nt)
		bd, ok := g.classDecls[bname]
		if !ok {
			return fmt.Errorf("codegen：未定义的父类 %s", bname)
		}
		if err := g.collectClass(bd); err != nil {
			return err
		}
		ci.base = g.classes[bname]
		if ci.base == nil {
			return fmt.Errorf("codegen：父类 %s 未登记", bname)
		}
	}
	ci.protocols = d.Protocols
	// vtable 槽：本类或祖先实现协议时存在（S2 §5.7；派发批次填充，当前仅布局）。
	ci.vptr = len(d.Protocols) > 0 || (ci.base != nil && ci.base.vptr)
	ci.decl = d
	ci.fields = nil
	if ci.base != nil {
		ci.fields = append(ci.fields, ci.base.fields...)
	}
	ci.methods = map[string]*classInfo_m{}
	ci.ctors = d.Ctors
	ci.primary = d.Primary
	ci.ctorName = map[*xfront.CtorDecl]string{}
	ci.deinit = nil
	// 主构造器参数即隐式同名字段（S2 §6.3），排在声明字段之前（类头在类体前）。
	// sema 的 materializePrimary 可能已把参数物化进 Fields；已存在则不重复添加。
	if d.Primary != nil {
		declared := map[string]bool{}
		for _, f := range d.Fields {
			declared[f.Name] = true
		}
		for _, p := range d.Primary.Params {
			if declared[p.Name] {
				continue
			}
			ct, err := g.cType(p.Type)
			if err != nil {
				return err
			}
			ci.fields = append(ci.fields, classField{name: p.Name, cname: p.Name, ctype: ct,
				isStr: ct == "rt_string *", isArr: isContainerC(ct), isCls: isClassPtr(ct),
				isHandle: isHandlePtr(ct), isBytes: ct == "xrt_bytes_obj *"})
		}
	}
	for _, f := range d.Fields {
		ct, err := g.cType(f.Type)
		if err != nil {
			return err
		}
		ci.fields = append(ci.fields, classField{name: f.Name, cname: fieldCName(f), ctype: ct,
			isStr: ct == "rt_string *", isArr: isContainerC(ct), isCls: isClassPtr(ct),
			isHandle: isHandlePtr(ct), isBytes: ct == "xrt_bytes_obj *", init: f.Init})
	}
	// 构造器 C 名：首个（主构造器优先）无后缀，其余按声明序编号（S2 §6.3 重载）。
	var ctorList []*xfront.CtorDecl
	if d.Primary != nil {
		ctorList = append(ctorList, d.Primary)
	}
	ctorList = append(ctorList, d.Ctors...)
	for i, c := range ctorList {
		name := ci.cname + "_new"
		if i > 0 {
			name = fmt.Sprintf("%s_new_%d", ci.cname, i)
		}
		ci.ctorName[c] = name
	}
	for _, m := range d.Methods {
		if m.IsDeinit {
			// 用户 deinit 体静态派发，先于字段释放执行（S2-E5-02）。
			// 独立 C 名，避免与类型 deinit 钩子 `<cname>_deinit_hook` 冲突。
			if ci.deinit != nil {
				return fmt.Errorf("codegen：类 %s 声明了多个 deinit（sema 应已拒绝）", d.Name)
			}
			ci.deinit = &classInfo_m{decl: m, cname: ci.cname + "_deinit_user", owner: ci}
			continue
		}
		if _, ok := ci.methods[m.Name]; ok {
			return fmt.Errorf("codegen：类 %s 方法重名 %s（重载未支持，M4.4b 范围）", d.Name, m.Name)
		}
		ci.methods[m.Name] = &classInfo_m{decl: m, cname: classMethodCName(d.Name, m.Name), owner: ci}
	}
	ci.collected = true
	return nil
}

// ctorsInDeclOrder 返回按 C 名序的构造器列表（首个无需后缀）。
func (ci *classInfo) ctorList() []*xfront.CtorDecl {
	var out []*xfront.CtorDecl
	seen := map[*xfront.CtorDecl]bool{}
	if ci.primary != nil {
		out = append(out, ci.primary)
		seen[ci.primary] = true
	}
	for _, c := range ci.ctors {
		if seen[c] {
			continue // sema materializePrimary 可能把主构造器也追加进 Ctors
		}
		seen[c] = true
		out = append(out, c)
	}
	return out
}

// ctorByArity 按实参个数选择构造器；无匹配返回 nil（S2 §6.3 重载）。
func (ci *classInfo) ctorByArity(argc int) *xfront.CtorDecl {
	for _, c := range ci.ctorList() {
		if len(c.Params) == argc {
			return c
		}
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
			g.classDecls[c.Name] = c
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
		ci := g.classes[name]
		ctors := ci.ctorList()
		if len(ctors) == 0 {
			fmt.Fprintf(b, "static %s *%s_new(void);\n", ci.cname, ci.cname)
		} else {
			for _, c := range ctors {
				parts := []string{}
				for _, p := range c.Params {
					pc, err := g.cType(p.Type)
					if err != nil {
						continue
					}
					parts = append(parts, pc+" xn_p_"+p.Name)
				}
				fmt.Fprintf(b, "static %s *%s(%s);\n", ci.cname, ci.ctorName[c], strings.Join(parts, ", "))
			}
		}
		if ci.deinit != nil {
			fmt.Fprintf(b, "static void %s(%s *self);\n", ci.deinit.cname, ci.cname)
		}
	}
	if len(names) > 0 {
		b.WriteString("\n")
	}
}

// emitClassStruct 生成结构体、类型描述符与构造器。
func (g *gen) emitClassStruct(b *strings.Builder, ci *classInfo) {
	fmt.Fprintf(b, "/* 类 %s（M4.4b） */\n", ci.decl.Name)
	fmt.Fprintf(b, "typedef struct %s {\n    rt_header hdr;\n", ci.cname)
	if ci.vptr {
		b.WriteString("    void **__vtable; /* 协议 vtable 槽（S2 §5.7；派发批次填充） */\n")
	}
	for _, f := range ci.fields {
		fmt.Fprintf(b, "    %s %s;\n", f.ctype, f.cname)
	}
	b.WriteString("} " + ci.cname + ";\n\n")

	// 类型 deinit 钩子（S2 §6.4）：用户体（静态派发）→ 父类用户体链 →
	// 释放仍非空的引用字段（rt_release 对 NULL 幂等，保留置 null 提前释放语义）。
	fmt.Fprintf(b, "static void %s_deinit_hook(void *p) {\n", ci.cname)
	fmt.Fprintf(b, "    %s *o = (%s *)p;\n", ci.cname, ci.cname)
	if ci.deinit != nil {
		fmt.Fprintf(b, "    %s(o);\n", ci.deinit.cname)
	}
	for base := ci.base; base != nil; base = base.base {
		if base.deinit != nil {
			fmt.Fprintf(b, "    %s((%s *)o);\n", base.deinit.cname, base.cname)
		}
	}
	for _, f := range ci.fields {
		switch {
		case f.isRefField():
			fmt.Fprintf(b, "    rt_release(o->%s);\n", f.cname)
		case f.isArr:
			fmt.Fprintf(b, "    %s_free(&o->%s);\n", f.ctype, f.cname)
		}
	}
	b.WriteString("}\n\n")
	fmt.Fprintf(b, "static const rt_type %s = { %q, sizeof(%s), %s_deinit_hook, NULL };\n\n",
		ci.typeVar, ci.decl.Name, ci.cname, ci.cname)

}

// emitClassCtor 生成全部构造器（S2 §6.3）：分配清零 → 字段初值（声明顺序）
// → 主构造器参数绑定 → 构造器体。无显式构造器时生成隐式无参构造器。
func (g *gen) emitClassCtor(b *strings.Builder, ci *classInfo) error {
	inits, err := g.classCtorInit(ci)
	if err != nil {
		return err
	}
	ctors := ci.ctorList()
	if len(ctors) == 0 {
		fmt.Fprintf(b, "static %s *%s_new(void) {\n", ci.cname, ci.cname)
		fmt.Fprintf(b, "    %s *o = (%s *)rt_arc_new(&%s);\n", ci.cname, ci.cname, ci.typeVar)
		fmt.Fprintf(b, "    memset((char *)o + sizeof(rt_header), 0, sizeof(%s) - sizeof(rt_header));\n", ci.cname)
		for _, l := range inits {
			b.WriteString("    " + l + "\n")
		}
		b.WriteString("    return o;\n}\n\n")
		return nil
	}
	for _, c := range ctors {
		parts := []string{}
		pnames := map[string]bool{}
		locals := map[string]string{}
		for _, p := range c.Params {
			pc, err := g.cType(p.Type)
			if err != nil {
				return err
			}
			parts = append(parts, pc+" xn_p_"+p.Name)
			pnames[p.Name] = true
			locals[p.Name] = pc
		}
		fmt.Fprintf(b, "static %s *%s(%s) {\n", ci.cname, ci.ctorName[c], strings.Join(parts, ", "))
		fmt.Fprintf(b, "    %s *o = (%s *)rt_arc_new(&%s);\n", ci.cname, ci.cname, ci.typeVar)
		fmt.Fprintf(b, "    memset((char *)o + sizeof(rt_header), 0, sizeof(%s) - sizeof(rt_header));\n", ci.cname)
		for _, l := range inits {
			b.WriteString("    " + l + "\n")
		}
		// 主构造器参数绑定同名字段（§6.3：字段初始化式之后、构造器体之前）。
		if c == ci.primary {
			for _, p := range c.Params {
				ctype, _ := g.cType(p.Type)
				field := p.Name
				switch {
				case isRef(ctype):
					fmt.Fprintf(b, "    o->%s = rt_retain(xn_p_%s);\n", field, p.Name)
				default:
					fmt.Fprintf(b, "    o->%s = xn_p_%s;\n", field, p.Name)
				}
			}
		}
		sc := &scope{g: g, retC: ci.cname + " *", params: pnames, locals: locals, self: newSelfCtx(ci), isCtor: true}
		sc.self.cvar = "o"
		if c.Body != nil {
			body, err := sc.emitBlock(c.Body.Stmts)
			if err != nil {
				return err
			}
			b.WriteString(body)
		}
		b.WriteString("    return o;\n}\n\n")
	}
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
	sc := &scope{g: g, retC: retC, params: pnames, locals: locals, self: newSelfCtx(ci)}
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
	case "rt_string *", "xrt_handle *", "xrt_bytes_obj *":
		return "NULL"
	}
	if isClassPtr(ct) {
		return "NULL"
	}
	return "0"
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
		if f.init == nil {
			continue
		}
		if err := g.validateFieldInit(f.init, ci.decl.Name, f.name); err != nil {
			return nil, err
		}
		// 上一字段求值可能留下临时语句（顶层调用/拼接）
		out = append(out, sc.pending...)
		sc.pending = nil
		lines, expr, err := g.fieldInitValue(sc, f, f.init, ci.decl.Name)
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
	case g.isTupleC(f.ctype):
		lines, v, err := sc.tupleExpr(init, f.ctype)
		if err != nil {
			return nil, "", err
		}
		return lines, v, nil
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
	case *xfront.Tuple:
		for _, el := range n.Elems {
			if err := g.validateFieldInit(el, cls, field); err != nil {
				return err
			}
		}
		return nil
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
