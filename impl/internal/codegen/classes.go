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
	isProto  bool        // 协议类型字段（xn_proto_<P>，强引用，S2 §4.5）
	isAny    bool        // Any/Object 装箱字段（GC，S3 §3）
	isGC     bool        // 类引用字段指向 GC 类（BND-10：由 GC 管理，不进入 ARC 计数）
	semC     string      // 声明语义 C 类型（slot 存储可能加宽到 8 字节，S3 §2）
	elem     string      // 容器元素 C 类型（isArr 时用于 deinit 释放；辅助记录）
	init     xfront.Expr // 字段初始化式（可空；主构造器字段无初值）
}

// isRefField 判断字段是否持有 ARC 引用（deinit/赋值需 retain/release）。
func (f classField) isRefField() bool {
	return f.isStr || f.isCls || f.isHandle || f.isBytes || f.isProto
}

// classInfo 是一个类的生成信息。
type classInfo struct {
	decl         *xfront.ClassDecl
	cname        string // xn_Cls_<Name>
	typeVar      string // RT_TYPE_XN_<Name>
	base         *classInfo
	protocols    []*xfront.NamedType
	vptr         bool // 协议 vtable 指针槽（S2 §5.7）
	fields       []classField
	staticFields []classField              // 静态字段（singleton BND-07）
	methods      map[string]*classInfo_m   // 方法名 → 主签名
	overloads    map[string][]*classInfo_m // 扩展/重载集合（按声明序）
	extCount     int                       // 扩展方法 C 名序号（唯一化）
	ctors        []*xfront.CtorDecl        // 普通构造器（S2 §6.3）
	primary      *xfront.CtorDecl          // 主构造器
	ctorName     map[*xfront.CtorDecl]string
	deinit       *classInfo_m              // 用户 deinit 体（静态派发，先于字段释放）
	subst        map[string]xfront.TypeRef // 泛型类实例的类型参数替换（BND-12）
	isGC         bool                      // 本类按策略判定为 GC（BND-10）
	collected    bool
	collecting   bool
}

type classInfo_m struct {
	decl   *xfront.MethodDecl
	cname  string // xn_Cls_<Name>_<method>
	owner  *classInfo
	static bool // 静态方法：无 self 参数、类名调用（S2 §7.2）
	ext    bool // 扩展方法：静态派发，不进入 vtable（S2 §11）
}

// typeIsExpr 生成 `x is T`：类/协议层次可静态判定，协议接收者按 vtable 运行时判定。
func (s *scope) typeIsExpr(n *xfront.Binary, ta *xfront.TypeAsExpr) (string, error) {
	lt, err := s.exprType(n.L)
	if err != nil {
		return "", err
	}
	rt, err := s.g.cType(s.g.substitute(ta.Type))
	if err != nil {
		return "", err
	}
	// Any/Object：拆箱检查装箱类型名（S3 §3）。
	if s.g.isAnyC(lt) {
		x, err := s.intExpr(n.L)
		if err != nil {
			return "", err
		}
		if s.g.isAnyC(rt) {
			return "(" + x + " != NULL)", nil
		}
		label, ok := s.g.anyTypeLabel(rt)
		if !ok {
			return "", fmt.Errorf("codegen：Any/Object 的 `is %s` 暂未支持（S3 §3）", rt)
		}
		return "xn_any_is(" + x + ", " + cQuote(label) + ")", nil
	}
	if s.g.isAnyC(rt) {
		// `x is Any`：非 null 值均可装箱为 Any。
		x, err := s.intExpr(n.L)
		if err != nil {
			return "", err
		}
		if isClassPtr(lt) || s.g.isProtoC(lt) || s.g.isDataEnumC(lt) ||
			isHandlePtr(lt) || lt == "xrt_bytes_obj *" || lt == "rt_string *" {
			return "(" + x + " != NULL)", nil
		}
		return "1", nil
	}
	if isClassPtr(lt) {
		if isClassPtr(rt) {
			if s.g.classIsA(lt, rt) {
				return "1", nil
			}
			return "0", nil
		}
		if s.g.isProtoC(rt) {
			if s.g.classImplements(lt, strings.TrimPrefix(rt, "xn_proto_")) {
				return "1", nil
			}
			return "0", nil
		}
	}
	if s.g.isProtoC(lt) {
		x, err := s.intExpr(n.L)
		if err != nil {
			return "", err
		}
		if s.g.isProtoC(rt) {
			if lt == rt {
				return "((void *)(" + x + ") != NULL)", nil
			}
			return "0", nil
		}
		if isClassPtr(rt) {
			name := strings.TrimSuffix(strings.TrimPrefix(rt, "xn_Cls_"), " *")
			if _, ok := s.g.classes[name]; ok {
				return "(((void *)(" + x + ") != NULL) && (((xn_vt_obj *)(" + x + "))->__vtable == xn_vt_" + name + "))", nil
			}
		}
	}
	if s.g.isDataEnumC(lt) {
		x, err := s.intExpr(n.L)
		if err != nil {
			return "", err
		}
		if lt == rt {
			return "((void *)(" + x + ") != NULL)", nil
		}
		return "0", nil
	}
	if lt == rt {
		return "1", nil
	}
	return "0", nil
}

// typeAsExpr 生成 `x as T` / `x as? T`：协议→类用 vtable 身份判定。
func (s *scope) typeAsExpr(n *xfront.Binary, ta *xfront.TypeAsExpr, nullSafe bool) (string, error) {
	lt, err := s.exprType(n.L)
	if err != nil {
		return "", err
	}
	rt, err := s.g.cType(s.g.substitute(ta.Type))
	if err != nil {
		return "", err
	}
	cast := rt
	// Any/Object 装箱（S3 §3）：值/引用进入 GC 盒。
	if s.g.isAnyC(rt) && !s.g.isAnyC(lt) {
		return s.anyBoxExpr(n.L, lt)
	}
	x, err := s.intExpr(n.L)
	if err != nil {
		return "", err
	}
	// Any/Object 拆箱：类型不匹配时 as? 取零值、as 终止（S3 §3）。
	if s.g.isAnyC(lt) {
		return s.anyUnboxC(x, rt, nullSafe)
	}
	if s.g.isProtoC(lt) && isClassPtr(rt) {
		name := strings.TrimSuffix(strings.TrimPrefix(rt, "xn_Cls_"), " *")
		if _, ok := s.g.classes[name]; ok {
			cond := "(((void *)(" + x + ") != NULL) && (((xn_vt_obj *)(" + x + "))->__vtable == xn_vt_" + name + "))"
			if nullSafe {
				return "(" + cond + " ? (" + cast + ")(" + x + ") : NULL)", nil
			}
			return "(" + cond + " ? (" + cast + ")(" + x + ") : NULL)", nil
		}
	}
	if isClassPtr(lt) && s.g.isProtoC(rt) {
		if s.g.classImplements(lt, strings.TrimPrefix(rt, "xn_proto_")) {
			return "((" + cast + ")(" + x + "))", nil
		}
		if nullSafe {
			return "NULL", nil
		}
	}
	if lt == rt {
		return x, nil
	}
	if isClassPtr(lt) && isClassPtr(rt) {
		return "((" + cast + ")(" + x + "))", nil
	}
	if nullSafe {
		return "NULL", nil
	}
	return "((" + cast + ")(" + x + "))", nil
}

// classIsA 判断 from 类是否等于或继承 to 类（C 指针类型）。
func (g *gen) classIsA(fromC, toC string) bool {
	fi, ok := g.classOfC(fromC)
	if !ok {
		return false
	}
	ti, ok := g.classOfC(toC)
	if !ok {
		return false
	}
	for cur := fi; cur != nil; cur = cur.base {
		if cur.cname == ti.cname {
			return true
		}
	}
	return false
}

// classImplements 判断类（含祖先）是否实现协议。
func (g *gen) classImplements(classC, protoName string) bool {
	ci, ok := g.classOfC(classC)
	if !ok {
		return false
	}
	for cur := ci; cur != nil; cur = cur.base {
		for _, p := range cur.protocols {
			if typeName(p) == protoName {
				return true
			}
		}
	}
	return false
}
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
	ci.isGC = g.policy[d.Name] == "gc"
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
			ci.fields = append(ci.fields, classField{name: p.Name, cname: p.Name,
				ctype: g.slotCType(ct), semC: ct,
				isStr: ct == "rt_string *", isArr: isContainerC(ct), isCls: isClassPtr(ct),
				isHandle: isHandlePtr(ct), isBytes: ct == "xrt_bytes_obj *", isProto: g.isProtoC(ct), isAny: ct == "xn_Any *",
				isGC: isClassPtr(ct) && g.classIsGC(ct)})
		}
	}
	for _, f := range d.Fields {
		ct, err := g.cType(f.Type)
		if err != nil {
			return err
		}
		ci.fields = append(ci.fields, classField{name: f.Name, cname: fieldCName(f),
			ctype: g.slotCType(ct), semC: ct,
			isStr: ct == "rt_string *", isArr: isContainerC(ct), isCls: isClassPtr(ct),
			isHandle: isHandlePtr(ct), isBytes: ct == "xrt_bytes_obj *", isProto: g.isProtoC(ct), isAny: ct == "xn_Any *",
			isGC: isClassPtr(ct) && g.classIsGC(ct), init: f.Init})
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
			ci.deinit = &classInfo_m{decl: m, cname: ci.cname + "_deinit", owner: ci}
			continue
		}
		if _, ok := ci.methods[m.Name]; ok {
			return fmt.Errorf("codegen：类 %s 方法重名 %s（重载未支持，M4.4b 范围）", d.Name, m.Name)
		}
		ci.methods[m.Name] = &classInfo_m{decl: m, cname: classMethodCName(d.Name, m.Name), owner: ci, static: m.Mod.Static}
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
			if len(c.TypePars) > 0 {
				continue // 泛型类按实例生成（BND-12），声明本身不登记 shell
			}
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
func (g *gen) emitClassForwardDecls(b *strings.Builder) error {
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
		savedSubst := g.subst
		if len(ci.subst) > 0 {
			g.subst = mergeSubst(savedSubst, ci.subst)
		}
		ctors := ci.ctorList()
		if len(ctors) == 0 {
			fmt.Fprintf(b, "static %s *%s_new(void);\n", ci.cname, ci.cname)
			fmt.Fprintf(b, "static void %s(%s *o);\n", ci.initFnName(nil), ci.cname)
		} else {
			for _, c := range ctors {
				parts, _, _, err := g.ctorParamDecls(c)
				if err != nil {
					return err
				}
				fmt.Fprintf(b, "static %s *%s(%s);\n", ci.cname, ci.ctorName[c], strings.Join(parts, ", "))
				fmt.Fprintf(b, "static void %s(%s *o%s);\n", ci.initFnName(c), ci.cname, prefixed(", ", parts))
			}
		}
		if ci.deinit != nil {
			fmt.Fprintf(b, "static void %s(%s *self);\n", ci.deinit.cname, ci.cname)
		}
		if ci.vptr {
			fmt.Fprintf(b, "static void *xn_vt_%s[%d];\n", ci.decl.Name, len(g.slotOrder))
		}
		g.subst = savedSubst
	}
	if len(names) > 0 {
		b.WriteString("\n")
	}
	return nil
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
	// 显式 super.deinit() 接管父链；否则自动沿父类执行用户 deinit（§6.4）。
	if ci.deinit == nil || !deinitCallsSuper(ci.deinit.decl) {
		for base := ci.base; base != nil; base = base.base {
			if base.deinit != nil {
				fmt.Fprintf(b, "    %s((%s *)o);\n", base.deinit.cname, base.cname)
			}
		}
	}
	for _, f := range ci.fields {
		switch {
		case f.isCls && (ci.isGC || f.isGC):
			/* 类引用字段：GC 对象由 GC 管理；GC 类的 ARC 类引用由
			 * sweep 的 scan(sweep_release_arc_ref) 释放，deinit 不重复释放。 */
		case f.isAny && ci.isGC:
			/* Any/Object 装箱是 GC 盒，由 sweep scan 追踪/释放。 */
		case f.isProto && ci.isGC:
			/* 协议字段可能指向 GC/ARC 实现；GC 类由 sweep scan 释放 ARC。 */
		case g.isTupleC(f.ctype):
			for _, tr := range g.tupleRefPaths("o->"+f.cname, f.ctype) {
				if isClassPtr(tr.ctype) || g.isProtoC(tr.ctype) || g.isDataEnumC(tr.ctype) {
					continue // 由 sweep scan 释放
				}
				fmt.Fprintf(b, "    rt_release(%s);\n", tr.path)
			}
		case f.isRefField():
			fmt.Fprintf(b, "    rt_release(o->%s);\n", f.cname)
		case f.isArr:
			fmt.Fprintf(b, "    %s_free(&o->%s);\n", f.ctype, f.cname)
		}
	}
	b.WriteString("}\n\n")

	// scan 钩子（BND-10）：GC 类访问全部类引用字段（交给 sweep 释放 ARC 引用 /
	// 标记 GC 引用）；ARC 类只需访问其中的 GC 引用（作为 GC 根）。
	scanFields := []classField{}
	for _, f := range ci.fields {
		if f.isCls && (ci.isGC || f.isGC) {
			scanFields = append(scanFields, f)
		}
		if (f.isProto || f.isAny) && ci.isGC {
			scanFields = append(scanFields, f)
		}
	}
	hasTupleRefs := false
	for _, f := range ci.fields {
		if !g.isTupleC(f.ctype) {
			continue
		}
		for _, tr := range g.tupleRefPaths("o->"+f.cname, f.ctype) {
			if isClassPtr(tr.ctype) || g.isProtoC(tr.ctype) || g.isDataEnumC(tr.ctype) {
				hasTupleRefs = true
			}
		}
	}
	scanName := "NULL"
	if len(scanFields) > 0 || hasTupleRefs {
		scanName = ci.cname + "_scan"
		fmt.Fprintf(b, "static void %s(void *p, void (*visit)(void *)) {\n", scanName)
		fmt.Fprintf(b, "    %s *o = (%s *)p;\n", ci.cname, ci.cname)
		for _, f := range scanFields {
			fmt.Fprintf(b, "    if (o->%s) { visit(o->%s); }\n", f.cname, f.cname)
		}
		for _, f := range ci.fields {
			if !g.isTupleC(f.ctype) {
				continue
			}
			for _, tr := range g.tupleRefPaths("o->"+f.cname, f.ctype) {
				if isClassPtr(tr.ctype) || g.isProtoC(tr.ctype) || g.isDataEnumC(tr.ctype) {
					fmt.Fprintf(b, "    if (%s) { visit(%s); }\n", tr.path, tr.path)
				}
			}
		}
		b.WriteString("}\n\n")
	}
	fmt.Fprintf(b, "static const rt_type %s = { %q, sizeof(%s), %s_deinit_hook, %s };\n\n",
		ci.typeVar, ci.decl.Name, ci.cname, ci.cname, scanName)

}

// ownFields 返回本类声明的字段（不含继承前置的父类字段）。
func (ci *classInfo) ownFields() []classField {
	if ci.base == nil {
		return ci.fields
	}
	return ci.fields[len(ci.base.fields):]
}

// initFnName 构造器初始化函数 C 名（在已分配对象上执行字段初值/构造体前段）。
func (ci *classInfo) initFnName(c *xfront.CtorDecl) string {
	if c == nil {
		return ci.cname + "_new_init"
	}
	return ci.ctorName[c] + "_init"
}

// ctorParamDecls 构造器参数声明串与作用域登记。
func (g *gen) ctorParamDecls(c *xfront.CtorDecl) ([]string, map[string]bool, map[string]string, error) {
	parts := []string{}
	pnames := map[string]bool{}
	locals := map[string]string{}
	if c == nil {
		return parts, pnames, locals, nil
	}
	for _, p := range c.Params {
		pc, err := g.cType(p.Type)
		if err != nil {
			return nil, nil, nil, err
		}
		parts = append(parts, pc+" xn_p_"+p.Name)
		pnames[p.Name] = true
		locals[p.Name] = pc
	}
	return parts, pnames, locals, nil
}

// superCtorStmt 识别构造器体内首条 `super(...)` 语句。
func superCtorStmt(body *xfront.Block) (*xfront.Call, bool) {
	if body == nil || len(body.Stmts) == 0 {
		return nil, false
	}
	es, ok := body.Stmts[0].(*xfront.ExprStmt)
	if !ok {
		return nil, false
	}
	call, ok := es.X.(*xfront.Call)
	if !ok {
		return nil, false
	}
	id, ok := call.Callee.(*xfront.IdentExpr)
	if !ok || id.Name != "super" {
		return nil, false
	}
	return call, true
}

// deinitCallsSuper 判断 deinit 体是否显式调用 super.deinit()。
func deinitCallsSuper(m *xfront.MethodDecl) bool {
	if m == nil || m.Body == nil {
		return false
	}
	for _, st := range m.Body.Stmts {
		es, ok := st.(*xfront.ExprStmt)
		if !ok {
			continue
		}
		call, ok := es.X.(*xfront.Call)
		if !ok {
			continue
		}
		mem, ok := call.Callee.(*xfront.Member)
		if !ok || mem.Name != "deinit" {
			continue
		}
		if id, ok := mem.X.(*xfront.IdentExpr); ok && id.Name == "super" {
			return true
		}
	}
	return false
}

// emitClassCtor 生成全部构造器（S2 §6.3/§6.5）：
// 分配清零 → 安装 vtable → 父类构造（显式 super(...) 或隐式无参）→ 本类字段初值
// （声明顺序）→ 主构造器参数绑定 → 构造器体（跳过 super 语句）。
// 同时为每个构造器生成 `<ctor>_init`（在既有对象上执行本类字段初值），供派生类复用。
func (g *gen) emitClassCtor(b *strings.Builder, ci *classInfo) error {
	saved := g.subst
	if len(ci.subst) > 0 {
		g.subst = mergeSubst(saved, ci.subst)
	}
	defer func() { g.subst = saved }()
	inits, err := g.classCtorInit(ci)
	if err != nil {
		return err
	}
	ctors := ci.ctorList()
	if len(ctors) == 0 {
		// 隐式无参构造器：init 承担父类初始化 + 本类字段初值。
		fmt.Fprintf(b, "static void %s(%s *o) {\n", ci.initFnName(nil), ci.cname)
		if ci.base != nil {
			baseLines, err := g.baseCtorCall(ci, &scope{g: g, locals: map[string]string{}}, nil, 0)
			if err != nil {
				return err
			}
			for _, l := range baseLines {
				b.WriteString("    " + l + "\n")
			}
		}
		for _, l := range inits {
			b.WriteString("    " + l + "\n")
		}
		b.WriteString("}\n\n")
		fmt.Fprintf(b, "static %s *%s_new(void) {\n", ci.cname, ci.cname)
		alloc := "rt_arc_new"
		if ci.isGC {
			alloc = "rt_gc_new"
		}
		fmt.Fprintf(b, "    %s *o = (%s *)%s(&%s);\n", ci.cname, ci.cname, alloc, ci.typeVar)
		fmt.Fprintf(b, "    memset((char *)o + sizeof(rt_header), 0, sizeof(%s) - sizeof(rt_header));\n", ci.cname)
		if ci.vptr {
			fmt.Fprintf(b, "    o->__vtable = xn_vt_%s;\n", ci.decl.Name)
		}
		fmt.Fprintf(b, "    %s(o);\n", ci.initFnName(nil))
		b.WriteString("    return o;\n}\n\n")
		return nil
	}
	for _, c := range ctors {
		parts, pnames, locals, err := g.ctorParamDecls(c)
		if err != nil {
			return err
		}
		// 初始化函数：父类构造（super(...) 或隐式）→ 本类字段初值 →
		// 主构造器参数绑定 → 构造器体（跳过 super 语句）。
		sc := &scope{g: g, retC: "void", params: pnames, locals: locals, self: newSelfCtx(ci)}
		sc.self.cvar = "o"
		if ci.base != nil {
			sc.superT = ci.base.cname + " *"
		}
		superCall, hasSuper := superCtorStmt(c.Body)
		var bodyStmts []xfront.Stmt
		if c.Body != nil {
			if hasSuper {
				bodyStmts = c.Body.Stmts[1:]
			} else {
				bodyStmts = c.Body.Stmts
			}
		}
		fmt.Fprintf(b, "static void %s(%s *o%s) {\n", ci.initFnName(c), ci.cname, prefixed(", ", parts))
		if ci.base != nil {
			argc := 0
			if hasSuper {
				argc = len(superCall.Args)
			}
			baseLines, err := g.baseCtorCall(ci, sc, superCall, argc)
			if err != nil {
				return err
			}
			for _, l := range baseLines {
				b.WriteString("    " + l + "\n")
			}
		}
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
		if len(bodyStmts) > 0 {
			g.curEscaped = escapeIdents(c.Body)
			body, err := sc.emitBlock(bodyStmts)
			g.curEscaped = nil
			if err != nil {
				return err
			}
			b.WriteString(body)
		}
		b.WriteString("}\n\n")

		fmt.Fprintf(b, "static %s *%s(%s) {\n", ci.cname, ci.ctorName[c], strings.Join(parts, ", "))
		alloc := "rt_arc_new"
		if ci.isGC {
			alloc = "rt_gc_new"
		}
		fmt.Fprintf(b, "    %s *o = (%s *)%s(&%s);\n", ci.cname, ci.cname, alloc, ci.typeVar)
		fmt.Fprintf(b, "    memset((char *)o + sizeof(rt_header), 0, sizeof(%s) - sizeof(rt_header));\n", ci.cname)
		if ci.vptr {
			fmt.Fprintf(b, "    o->__vtable = xn_vt_%s;\n", ci.decl.Name)
		}
		fmt.Fprintf(b, "    %s(o%s);\n", ci.initFnName(c), prefixed(", ", ctorArgNames(c)))
		b.WriteString("    return o;\n}\n\n")
	}
	return nil
}

// baseCtorCall 生成父类构造调用（显式 super(args) 或隐式无参）。
func (g *gen) baseCtorCall(ci *classInfo, sc *scope, superCall *xfront.Call, argc int) ([]string, error) {
	base := ci.base
	if base == nil {
		return nil, nil
	}
	var c *xfront.CtorDecl
	ctors := base.ctorList()
	if len(ctors) == 0 {
		if argc != 0 {
			return nil, fmt.Errorf("codegen：父类 %s 没有 %d 参数的构造器（S2 §6.3）", base.decl.Name, argc)
		}
		return []string{fmt.Sprintf("%s((%s *)o);", base.initFnName(nil), base.cname)}, nil
	}
	c = base.ctorByArity(argc)
	if c == nil {
		return nil, fmt.Errorf("codegen：父类 %s 没有 %d 参数的构造器（S2 §6.3）", base.decl.Name, argc)
	}
	args := []string{}
	var pre []string
	if superCall != nil {
		av, err := sc.callArgs(superCall.Args)
		if err != nil {
			return nil, err
		}
		args = av
		pre = append(pre, sc.pending...)
		sc.pending = nil
	}
	call := fmt.Sprintf("%s((%s *)o%s);", base.initFnName(c), base.cname, prefixed(", ", args))
	return append(pre, call), nil
}

// ctorArgNames 构造器参数在 C 侧的实参名。
func ctorArgNames(c *xfront.CtorDecl) []string {
	if c == nil {
		return nil
	}
	out := make([]string, 0, len(c.Params))
	for _, p := range c.Params {
		out = append(out, "xn_p_"+p.Name)
	}
	return out
}

// prefixed 将 sep 前缀拼接到列表（空列表返回空串）。
func prefixed(sep string, items []string) string {
	if len(items) == 0 {
		return ""
	}
	return sep + strings.Join(items, ", ")
}

// methodProto 生成方法前向声明。
func (g *gen) methodProto(ci *classInfo, m *classInfo_m) (string, error) {
	saved := g.subst
	if len(ci.subst) > 0 {
		g.subst = mergeSubst(saved, ci.subst)
	}
	defer func() { g.subst = saved }()
	retC := "void"
	if !m.decl.Void {
		c, err := g.cType(m.decl.Ret)
		if err != nil {
			return "", err
		}
		retC = c
	}
	var b strings.Builder
	parts := []string{}
	if !m.static {
		parts = append(parts, ci.cname+" *self")
	}
	for _, p := range m.decl.Params {
		pc, err := g.cType(p.Type)
		if err != nil {
			return "", err
		}
		parts = append(parts, pc+" xn_p_"+p.Name)
	}
	fmt.Fprintf(&b, "static %s %s(%s);", retC, m.cname, strings.Join(parts, ", "))
	return b.String(), nil
}

// genMethod 生成实例方法：self 指针首参，方法体内 self 直接可见。
func (g *gen) genMethod(ci *classInfo, m *classInfo_m) (string, error) {
	saved := g.subst
	if len(ci.subst) > 0 {
		g.subst = mergeSubst(saved, ci.subst)
	}
	defer func() { g.subst = saved }()
	retC := "void"
	if !m.decl.Void {
		c, err := g.cType(m.decl.Ret)
		if err != nil {
			return "", err
		}
		retC = c
	}
	var b strings.Builder
	parts := []string{}
	if !m.static {
		parts = append(parts, ci.cname+" *self")
	}
	for _, p := range m.decl.Params {
		pc, err := g.cType(p.Type)
		if err != nil {
			return "", err
		}
		parts = append(parts, pc+" xn_p_"+p.Name)
	}
	fmt.Fprintf(&b, "static %s %s(%s) {\n", retC, m.cname, strings.Join(parts, ", "))
	hasResult := strings.HasPrefix(retC, "xn_Result_")
	if hasResult {
		fmt.Fprintf(&b, "    %s xn_ret;\n", retC)
	}
	locals := map[string]string{}
	if !m.static {
		locals["self"] = ci.cname + " *"
	}
	pnames := map[string]bool{}
	for _, p := range m.decl.Params {
		pnames[p.Name] = true
		if pc, err := g.cType(p.Type); err == nil {
			locals[p.Name] = pc
		}
	}
	sc := &scope{g: g, retC: retC, hasResult: hasResult, params: pnames, locals: locals}
	if len(ci.staticFields) > 0 {
		sc.staticRefs = map[string]string{}
		sc.staticTypes = map[string]string{}
		for _, f := range ci.staticFields {
			sc.staticRefs[f.name] = "xn_static_" + ci.decl.Name + "_" + f.cname
			sc.staticTypes[f.name] = f.ctype
		}
	}
	if !m.static {
		sc.self = newSelfCtx(ci)
		if ci.base != nil {
			sc.superT = ci.base.cname + " *"
		}
	}
	g.curEscaped = escapeIdents(m.decl.Body)
	body, err := sc.emitBlock(m.decl.Body.Stmts)
	g.curEscaped = nil
	if err != nil {
		return "", err
	}
	b.WriteString(body)
	if hasResult && !sc.returned {
		fmt.Fprintf(&b, "    %s xn_zero = {0};\n", retC)
		b.WriteString("    xn_ret = xn_zero;\n")
		b.WriteString("    return xn_ret;\n")
	} else if retC != "void" && !hasResult {
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
	for i := range ci.ownFields() {
		f := ci.ownFields()[i]
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
		case f.isRefField():
			// 旧值为 memset 的 NULL，release 幂等（rt_release 对 NULL 直接返回）
			out = append(out, fmt.Sprintf("rt_release((void *)o->%s);", f.cname))
		}
		out = append(out, fmt.Sprintf("o->%s = %s;", f.cname, g.fieldStoreExpr(f, expr)))
	}
	return out, nil
}

// fieldInitValue 为单个字段初值生成 (语句, 右值表达式)。
func (g *gen) fieldInitValue(sc *scope, f classField, init xfront.Expr, cls string) ([]string, string, error) {
	switch {
	case strings.HasPrefix(f.ctype, "xn_opt_"):
		return sc.optExpr(init, f.ctype)
	case g.isStructC(f.ctype):
		return sc.structValue(init, f.ctype)
	case f.isAny:
		return sc.anyExpr(init)
	case f.isProto:
		lines, expr, _, err := sc.protoValue(init)
		if err != nil {
			return nil, "", err
		}
		return lines, expr, nil
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
	case g.isSimpleEnumC(f.ctype) || g.isDataEnumC(f.ctype):
		v, err := sc.intExpr(init)
		if err != nil {
			return nil, "", err
		}
		return nil, v, nil
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
		// 枚举项（Color.Green）是编译期常量，可作为字段初值（S2 §8.2）。
		if _, _, ok := g.enumItem(n); ok {
			return nil
		}
		return bad("访问了成员 `" + n.Name + "`（不能引用 self 或其他实例字段）")
	}
	return bad(fmt.Sprintf("形态 %T 不受支持", e))
}
