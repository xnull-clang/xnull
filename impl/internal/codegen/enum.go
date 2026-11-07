// enum.go：枚举发射面（S2 §8）。
//
// 简单枚举：typedef int64_t + 项值常量；不分配、可比较、插值输出项名。
// 数据枚举：与类相同的 ARC 对象（载荷头 + final 字段），项为启动期单例全局根；
// 方法/构造器复用类的发射路径。
package codegen

import (
	"fmt"
	"sort"
	"strconv"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

type enumItemInfo struct {
	name    string
	value   int64 // 简单枚举
	args    []xfront.Expr
	varName string // 数据枚举项全局变量
}

type enumInfo struct {
	name   string
	ctype  string // xn_Enum_<N>（简单） / xn_Enum_<N> *（数据）
	simple bool
	decl   *xfront.EnumDecl
	values map[string]int64 // 简单枚举项值
	items  []enumItemInfo
	cls    *classInfo // 数据枚举复用类结构
}

// collectEnums 收集枚举（简单值表 / 数据枚举类结构）。
func (g *gen) collectEnums(u *xfront.CompilationUnit) error {
	for _, d := range u.Decls {
		ed, ok := d.(*xfront.EnumDecl)
		if !ok {
			continue
		}
		ei := &enumInfo{name: ed.Name, decl: ed, values: map[string]int64{}}
		ei.simple = !ed.IsData
		ei.ctype = "xn_Enum_" + ed.Name
		if ei.simple {
			next := int64(0)
			for _, it := range ed.Items {
				v := next
				if it.Value != nil {
					iv, err := constIntValue(it.Value)
					if err != nil {
						return err
					}
					v = iv
				}
				ei.values[it.Name] = v
				ei.items = append(ei.items, enumItemInfo{name: it.Name, value: v})
				next = v + 1
			}
		} else {
			ei.ctype += " *"
			ci, err := g.collectDataEnum(ed, ei.ctype)
			if err != nil {
				return err
			}
			ei.cls = ci
			for _, it := range ed.Items {
				ei.items = append(ei.items, enumItemInfo{name: it.Name, args: it.Args, varName: "xn_enum_" + ed.Name + "_" + it.Name})
			}
		}
		g.enums[ed.Name] = ei
		g.enumOrder = append(g.enumOrder, ed.Name)
	}
	return nil
}

// constIntValue 求简单枚举项显式值（整数字面量，可带负号）。
func constIntValue(e xfront.Expr) (int64, error) {
	switch n := e.(type) {
	case *xfront.IntLitExpr:
		return strconv.ParseInt(n.Text, 10, 64)
	case *xfront.Unary:
		if n.Op == "-" {
			v, err := constIntValue(n.X)
			return -v, err
		}
	}
	return 0, fmt.Errorf("codegen：枚举项值必须是整数字面量（S2 §8.2）")
}

// collectDataEnum 把数据枚举装配成类结构（无继承、无协议）。
func (g *gen) collectDataEnum(d *xfront.EnumDecl, ctype string) (*classInfo, error) {
	syn := &xfront.ClassDecl{Name: d.Name, Fields: d.Fields, Methods: d.Methods, Ctors: d.Ctors}
	ci := &classInfo{decl: syn, cname: strings.TrimSuffix(ctype, " *"),
		typeVar: "RT_TYPE_XN_ENUM_" + d.Name, methods: map[string]*classInfo_m{},
		ctors: d.Ctors, ctorName: map[*xfront.CtorDecl]string{}}
	for _, f := range d.Fields {
		ct, err := g.cType(f.Type)
		if err != nil {
			return nil, err
		}
		ci.fields = append(ci.fields, classField{name: f.Name, cname: fieldCName(f), ctype: ct,
			isStr: ct == "rt_string *", isArr: isContainerC(ct), isCls: isClassPtr(ct),
			isHandle: isHandlePtr(ct), isBytes: ct == "xrt_bytes_obj *", isProto: g.isProtoC(ct), init: f.Init})
	}
	for i, c := range d.Ctors {
		name := ci.cname + "_new"
		if i > 0 {
			name = fmt.Sprintf("%s_new_%d", ci.cname, i)
		}
		ci.ctorName[c] = name
	}
	for _, m := range d.Methods {
		if m.IsDeinit {
			return nil, fmt.Errorf("codegen：数据枚举不能声明 deinit（S2 §8.3）")
		}
		if _, ok := ci.methods[m.Name]; ok {
			return nil, fmt.Errorf("codegen：数据枚举 %s 方法重名 %s", d.Name, m.Name)
		}
		ci.methods[m.Name] = &classInfo_m{decl: m, cname: ci.cname + "_" + m.Name, owner: ci, static: m.Mod.Static}
	}
	ci.collected = true
	return ci, nil
}

// isSimpleEnumC / isDataEnumC 判断枚举 C 类型。
func (g *gen) isSimpleEnumC(c string) bool {
	if !strings.HasPrefix(c, "xn_Enum_") || strings.HasSuffix(c, " *") {
		return false
	}
	ei, ok := g.enums[strings.TrimPrefix(c, "xn_Enum_")]
	return ok && ei.simple
}

func (g *gen) isDataEnumC(c string) bool {
	if !strings.HasPrefix(c, "xn_Enum_") || !strings.HasSuffix(c, " *") {
		return false
	}
	ei, ok := g.enums[strings.TrimSuffix(strings.TrimPrefix(c, "xn_Enum_"), " *")]
	return ok && !ei.simple
}

// enumNameHelper 简单枚举值 → 项名。
func (g *gen) enumNameFunc(c string) (string, bool) {
	ei, ok := g.enums[strings.TrimPrefix(strings.TrimSuffix(c, " *"), "xn_Enum_")]
	if !ok {
		return "", false
	}
	return "xn_enum_" + ei.name + "_name", true
}

// enumItem 解析 `Enum.Item` 项访问。
func (g *gen) enumItem(mem *xfront.Member) (*enumInfo, *enumItemInfo, bool) {
	id, ok := mem.X.(*xfront.IdentExpr)
	if !ok {
		return nil, nil, false
	}
	ei, ok := g.enums[id.Name]
	if !ok {
		return nil, nil, false
	}
	for i := range ei.items {
		if ei.items[i].name == mem.Name {
			return ei, &ei.items[i], true
		}
	}
	return nil, nil, false
}

// emitEnumTypes 输出枚举 typedef、数据枚举结构/构造器与项全局变量。
func (g *gen) emitEnumTypes(b *strings.Builder) error {
	if len(g.enumOrder) == 0 {
		return nil
	}
	for _, name := range g.enumOrder {
		ei := g.enums[name]
		if ei.simple {
			fmt.Fprintf(b, "typedef int64_t %s;\n", ei.ctype)
		}
	}
	// 简单枚举项名助手。
	for _, name := range g.enumOrder {
		ei := g.enums[name]
		if !ei.simple {
			continue
		}
		fmt.Fprintf(b, "static rt_string *%s(int64_t v) {\n", "xn_enum_"+ei.name+"_name")
		b.WriteString("    switch (v) {\n")
		for _, it := range ei.items {
			fmt.Fprintf(b, "    case %d: return rt_string_from_c(%q);\n", it.value, it.name)
		}
		b.WriteString("    default: return xn_str_int(v);\n    }\n}\n\n")
	}
	// 数据枚举：结构/类型去初始化 + 项全局。
	for _, name := range g.enumOrder {
		ei := g.enums[name]
		if ei.simple {
			continue
		}
		g.emitClassStruct(b, ei.cls)
		if err := g.emitClassCtor(b, ei.cls); err != nil {
			return err
		}
		for _, it := range ei.items {
			fmt.Fprintf(b, "static %s %s;\n", ei.ctype, it.varName)
		}
		fmt.Fprintf(b, "static rt_string *xn_enum_%s_name(%s v) {\n", ei.name, ei.ctype)
		for _, it := range ei.items {
			fmt.Fprintf(b, "    if (v == %s) { return rt_string_from_c(%q); }\n", it.varName, it.name)
		}
		b.WriteString("    return rt_string_from_c(\"null\");\n}\n\n")
	}
	return nil
}

// emitEnumBodies 输出数据枚举方法体（结构/构造器已由 emitEnumTypes 发射）。
func (g *gen) emitEnumBodies(b *strings.Builder) error {
	for _, name := range g.enumOrder {
		ei := g.enums[name]
		if ei.simple {
			continue
		}
		ci := ei.cls
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

// emitEnumInit 输出启动期数据枚举项构造。
func (g *gen) emitEnumInit(b *strings.Builder) error {
	if len(g.enumOrder) == 0 {
		return nil
	}
	b.WriteString("static void xn_init_enums(void) {\n")
	sc := &scope{g: g, locals: map[string]string{}}
	for _, name := range g.enumOrder {
		ei := g.enums[name]
		if ei.simple {
			continue
		}
		for _, it := range ei.items {
			c := ei.cls.ctorByArity(len(it.args))
			if c == nil {
				return fmt.Errorf("codegen：枚举 %s 的项 %s 参数个数没有匹配构造器（S2 §8.4）", ei.name, it.name)
			}
			args, err := sc.callArgs(it.args)
			if err != nil {
				return err
			}
			for _, l := range sc.pending {
				b.WriteString("    " + l + "\n")
			}
			sc.pending = nil
			fmt.Fprintf(b, "    %s = %s(%s);\n", it.varName, ei.cls.ctorName[c], strings.Join(args, ", "))
		}
	}
	b.WriteString("}\n\n")
	return nil
}

// sortedEnumNames 确定性遍历用（当前按声明序，保留占位）。
func sortedEnumNames(m map[string]*enumInfo) []string {
	names := make([]string, 0, len(m))
	for n := range m {
		names = append(names, n)
	}
	sort.Strings(names)
	return names
}
