// singleton.go：单例发射面（S2 §9 / BND-07）。
//
// 表示：与类相同的 ARC 对象，全局唯一实例 `xn_single_<Name>`；
// `Name.instance` 编译为全局变量。实例在顶层字段初始化之后、main 之前构造。
// 单例固定 GC 语义在运行时线；本层先按 ARC 对象发射，字段生命周期随进程。
package codegen

import (
	"fmt"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

// collectSingletons 收集单例声明（字段/方法/deinit；无构造器）。
func (g *gen) collectSingletons(u *xfront.CompilationUnit) error {
	for _, d := range u.Decls {
		sd, ok := d.(*xfront.SingletonDecl)
		if !ok {
			continue
		}
		if len(sd.Ctors) > 0 {
			return fmt.Errorf("codegen：单例不能声明构造器（S2 §9.1）")
		}
		syn := &xfront.ClassDecl{Name: sd.Name, Fields: sd.Fields, Methods: sd.Methods}
		ci := &classInfo{decl: syn, cname: "xn_Single_" + sd.Name,
			typeVar: "RT_TYPE_XN_SINGLE_" + sd.Name, methods: map[string]*classInfo_m{}, isGC: true}
		for _, f := range sd.Fields {
			ct, err := g.cType(f.Type)
			if err != nil {
				return err
			}
			cf := classField{name: f.Name, cname: fieldCName(f), ctype: g.slotCType(ct), semC: ct,
				isStr: ct == "rt_string *", isArr: isContainerC(ct), isCls: isClassPtr(ct),
				isHandle: isHandlePtr(ct), isBytes: ct == "xrt_bytes_obj *", isProto: g.isProtoC(ct), init: f.Init}
			if f.Mod.Static {
				ci.staticFields = append(ci.staticFields, cf)
			} else {
				ci.fields = append(ci.fields, cf)
			}
		}
		for _, m := range sd.Methods {
			if m.IsDeinit {
				ci.deinit = &classInfo_m{decl: m, cname: ci.cname + "_deinit", owner: ci}
				continue
			}
			if _, dup := ci.methods[m.Name]; dup {
				return fmt.Errorf("codegen：单例 %s 方法重名 %s", sd.Name, m.Name)
			}
			ci.methods[m.Name] = &classInfo_m{decl: m, cname: ci.cname + "_" + m.Name, owner: ci, static: m.Mod.Static}
		}
		ci.collected = true
		g.singletons[sd.Name] = ci
		g.singletonOrder = append(g.singletonOrder, sd.Name)
	}
	return nil
}

// isSingletonC 判断 C 类型是否单例对象指针。
func (g *gen) isSingletonC(c string) bool {
	if !strings.HasPrefix(c, "xn_Single_") || !strings.HasSuffix(c, " *") {
		return false
	}
	return true
}

// singletonOfC 反查单例信息。
func (g *gen) singletonOfC(c string) (*classInfo, bool) {
	name := strings.TrimSuffix(strings.TrimPrefix(c, "xn_Single_"), " *")
	ci, ok := g.singletons[name]
	return ci, ok
}

// singletonInstance 解析 `AppInfo.instance` 成员访问。
func (g *gen) singletonInstance(mem *xfront.Member) (*classInfo, string, bool) {
	id, ok := mem.X.(*xfront.IdentExpr)
	if !ok || mem.Name != "instance" {
		return nil, "", false
	}
	ci, ok := g.singletons[id.Name]
	if !ok {
		return nil, "", false
	}
	return ci, "xn_single_" + id.Name, true
}

// singletonStatic 解析 `Singleton.staticField` 访问。
func (g *gen) singletonStatic(mem *xfront.Member) (string, string, bool) {
	id, ok := mem.X.(*xfront.IdentExpr)
	if !ok {
		return "", "", false
	}
	ci, ok := g.singletons[id.Name]
	if !ok {
		return "", "", false
	}
	for _, f := range ci.staticFields {
		if f.name == mem.Name || f.cname == mem.Name {
			return "xn_static_" + ci.decl.Name + "_" + f.cname, f.ctype, true
		}
	}
	return "", "", false
}

// singletonVarOf 返回单例全局实例变量名。
func singletonVarName(name string) string { return "xn_single_" + name }

// emitSingletonForwards 输出单例前置声明与方法原型。
func (g *gen) emitSingletonForwards(b *strings.Builder) error {
	if len(g.singletonOrder) == 0 {
		return nil
	}
	for _, name := range g.singletonOrder {
		ci := g.singletons[name]
		fmt.Fprintf(b, "typedef struct %s %s;\n", ci.cname, ci.cname)
	}
	for _, name := range g.singletonOrder {
		ci := g.singletons[name]
		fmt.Fprintf(b, "static %s *%s;\n", ci.cname, singletonVarName(name))
		for _, f := range ci.staticFields {
			fmt.Fprintf(b, "static %s xn_static_%s_%s;\n", f.ctype, ci.decl.Name, f.cname)
		}
		for _, md := range ci.decl.Methods {
			if md.IsDeinit {
				continue
			}
			m := ci.methods[md.Name]
			proto, err := g.methodProto(ci, m)
			if err != nil {
				return err
			}
			b.WriteString(proto + "\n")
		}
	}
	b.WriteString("\n")
	return nil
}

// emitSingletons 输出单例结构/方法/实例初始化。
func (g *gen) emitSingletons(b *strings.Builder) error {
	if len(g.singletonOrder) == 0 {
		return nil
	}
	for _, name := range g.singletonOrder {
		ci := g.singletons[name]
		g.emitClassStruct(b, ci)
		for _, md := range ci.decl.Methods {
			if md.IsDeinit {
				// 用户 deinit 体由类型钩子调用。
				mc, err := g.genMethod(ci, ci.deinit)
				if err != nil {
					return err
				}
				b.WriteString(mc + "\n")
				continue
			}
			mc, err := g.genMethod(ci, ci.methods[md.Name])
			if err != nil {
				return err
			}
			b.WriteString(mc + "\n")
		}
		// 实例构造：字段置零 → 字段初始化式 → 全局变量。
		fmt.Fprintf(b, "static void %s_init(void) {\n", ci.cname)
		alloc := "rt_arc_new"
		if ci.isGC {
			alloc = "rt_gc_new"
		}
		fmt.Fprintf(b, "    %s *o = (%s *)%s(&%s);\n", ci.cname, ci.cname, alloc, ci.typeVar)
		fmt.Fprintf(b, "    memset((char *)o + sizeof(rt_header), 0, sizeof(%s) - sizeof(rt_header));\n", ci.cname)
		var refs = map[string]string{}
		var types = map[string]string{}
		for _, name2 := range g.singletonOrder {
			c2 := g.singletons[name2]
			for _, f := range c2.staticFields {
				refs[f.name] = "xn_static_" + c2.decl.Name + "_" + f.cname
				types[f.name] = f.ctype
			}
		}
		inits, err := g.singletonInstanceInit(ci, refs, types)
		if err != nil {
			return err
		}
		for _, l := range inits {
			b.WriteString("    " + l + "\n")
		}
		fmt.Fprintf(b, "    %s = o;\n", singletonVarName(name))
		// 单例实例固定 GC 语义，登记为全局根（S2 §9.3；BND-10）。
		fmt.Fprintf(b, "    rt_gc_root_add(%s);\n}\n\n", singletonVarName(name))
	}
	b.WriteString("static void xn_init_singletons(void) {\n")
	// 静态字段先于单例实例初始化（S2 §9.2），按声明顺序；可引用前面的静态/单例。
	refs := map[string]string{}
	types := map[string]string{}
	for _, name := range g.singletonOrder {
		ci := g.singletons[name]
		for _, f := range ci.staticFields {
			refs[f.name] = "xn_static_" + ci.decl.Name + "_" + f.cname
			types[f.name] = f.ctype
		}
		lines, err := g.singletonStaticInit(ci, refs, types)
		if err != nil {
			return err
		}
		for _, l := range lines {
			b.WriteString("    " + l + "\n")
		}
	}
	for _, name := range g.singletonOrder {
		fmt.Fprintf(b, "    %s_init();\n", g.singletons[name].cname)
	}
	b.WriteString("}\n\n")
	return nil
}

// singletonStaticInit 生成单例静态字段初始化（引用前面静态/单例）。
func (g *gen) singletonStaticInit(ci *classInfo, refs, types map[string]string) ([]string, error) {
	var out []string
	sc := &scope{g: g, locals: map[string]string{}, staticRefs: refs, staticTypes: types}
	for _, f := range ci.staticFields {
		if f.init == nil {
			continue
		}
		lines, expr, err := g.fieldInitValue(sc, f, f.init, ci.decl.Name)
		if err != nil {
			return nil, err
		}
		out = append(out, lines...)
		out = append(out, sc.pending...)
		sc.pending = nil
		out = append(out, "xn_static_"+ci.decl.Name+"_"+f.cname+" = "+expr+";")
		if g.isGCTypeC(f.ctype) {
			out = append(out, "rt_gc_root_add(xn_static_"+ci.decl.Name+"_"+f.cname+");")
		}
	}
	return out, nil
}

// singletonInstanceInit 生成单例实例字段初始化（不走类字段初始值校验，允许引用前序单例）。
func (g *gen) singletonInstanceInit(ci *classInfo, refs, types map[string]string) ([]string, error) {
	var out []string
	sc := &scope{g: g, locals: map[string]string{}, staticRefs: refs, staticTypes: types}
	for _, f := range ci.fields {
		if f.init == nil {
			continue
		}
		lines, expr, err := g.fieldInitValue(sc, f, f.init, ci.decl.Name)
		if err != nil {
			return nil, err
		}
		out = append(out, lines...)
		out = append(out, sc.pending...)
		sc.pending = nil
		out = append(out, "o->"+f.cname+" = "+expr+";")
	}
	return out, nil
}
