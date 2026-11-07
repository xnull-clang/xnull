// generic_class.go：泛型类单态化（BND-12 / S1 §8.3）。
//
// 每个 `Box<Int>` 生成独立的 C 结构体/构造器/方法实例；实例名内部编码
// （xn_Cls_Box_i），字段与方法签名中的类型参数由 g.subst 深度替换。
// 与 sema 的接口：本层只消费 NamedType.Args（显式实参）；实参个数/形状校验
// 由 E2 sema 负责（本层对缺参/多参仍显式报错，不静默）。
package codegen

import (
	"fmt"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

// ensureClassInstance 取得（或创建）泛型类实例。args 已经过外层替换。
func (g *gen) ensureClassInstance(name string, args []xfront.TypeRef) (*classInfo, error) {
	decl := g.classDecls[name]
	if decl == nil || len(decl.TypePars) == 0 {
		return nil, fmt.Errorf("codegen：`%s` 不是泛型类（BND-12）", name)
	}
	args = g.substTypeArgs(args)
	if len(args) != len(decl.TypePars) {
		return nil, fmt.Errorf("codegen：泛型类 `%s` 需要 %d 个类型实参，实际 %d 个（§8.3）", name, len(decl.TypePars), len(args))
	}
	codes := make([]string, 0, len(args))
	for _, a := range args {
		c, err := typeArgCode(a)
		if err != nil {
			return nil, err
		}
		codes = append(codes, c)
	}
	key := name + "_" + strings.Join(codes, "_")
	cname := "xn_Cls_" + key
	if ci, ok := g.classInsts[cname]; ok {
		return ci, nil
	}
	if decl.Base != nil || len(decl.Protocols) > 0 {
		return nil, fmt.Errorf("codegen：泛型类 `%s` 的继承/协议单态化暂未支持（BND-12 边界）", name)
	}
	subst := map[string]xfront.TypeRef{}
	for i, tp := range decl.TypePars {
		subst[tp] = args[i]
	}
	ci := &classInfo{decl: decl, cname: cname, typeVar: "RT_TYPE_XN_" + key,
		methods: map[string]*classInfo_m{}, subst: subst, ctors: decl.Ctors,
		primary: decl.Primary, ctorName: map[*xfront.CtorDecl]string{}}
	// 实例化期间的类型生成统一走替换表。
	saved := g.subst
	g.subst = mergeSubst(saved, subst)
	defer func() { g.subst = saved }()

	declared := map[string]bool{}
	for _, f := range decl.Fields {
		declared[f.Name] = true
	}
	if decl.Primary != nil {
		for _, p := range decl.Primary.Params {
			if declared[p.Name] {
				continue
			}
			ct, err := g.cType(p.Type)
			if err != nil {
				return nil, err
			}
			ci.fields = append(ci.fields, classField{name: p.Name, cname: p.Name, ctype: g.slotCType(ct), semC: ct,
				isStr: ct == "rt_string *", isArr: isContainerC(ct), isCls: isClassPtr(ct),
				isHandle: isHandlePtr(ct), isBytes: ct == "xrt_bytes_obj *", isProto: g.isProtoC(ct)})
		}
	}
	for _, f := range decl.Fields {
		ct, err := g.cType(f.Type)
		if err != nil {
			return nil, err
		}
		ci.fields = append(ci.fields, classField{name: f.Name, cname: fieldCName(f), ctype: g.slotCType(ct), semC: ct,
			isStr: ct == "rt_string *", isArr: isContainerC(ct), isCls: isClassPtr(ct),
			isHandle: isHandlePtr(ct), isBytes: ct == "xrt_bytes_obj *", isProto: g.isProtoC(ct), init: f.Init})
	}
	var ctorList []*xfront.CtorDecl
	if decl.Primary != nil {
		ctorList = append(ctorList, decl.Primary)
	}
	ctorList = append(ctorList, decl.Ctors...)
	for i, c := range ctorList {
		n := ci.cname + "_new"
		if i > 0 {
			n = fmt.Sprintf("%s_new_%d", ci.cname, i)
		}
		ci.ctorName[c] = n
	}
	for _, m := range decl.Methods {
		if m.IsDeinit {
			ci.deinit = &classInfo_m{decl: m, cname: ci.cname + "_deinit", owner: ci}
			continue
		}
		if _, ok := ci.methods[m.Name]; ok {
			return nil, fmt.Errorf("codegen：泛型类 %s 方法重名 %s", name, m.Name)
		}
		ci.methods[m.Name] = &classInfo_m{decl: m, cname: ci.cname + "_" + m.Name, owner: ci, static: m.Mod.Static}
	}
	ci.collected = true
	g.classInsts[cname] = ci
	g.classInstKeys = append(g.classInstKeys, cname)
	g.classes[key] = ci // classOfC 反查（xn_Cls_<key>）
	return ci, nil
}

// emitClassInstance 发射一个泛型类实例（结构/构造器/方法）。
func (g *gen) emitClassInstance(b *strings.Builder, ci *classInfo) error {
	return g.withSubst(ci, func() error {
		g.emitClassStruct(b, ci)
		if err := g.emitClassCtor(b, ci); err != nil {
			return err
		}
		for _, md := range ci.decl.Methods {
			m := ci.methods[md.Name]
			if md.IsDeinit {
				m = ci.deinit
			}
			if m == nil {
				return fmt.Errorf("codegen：泛型实例 %s 的成员 %s 未登记", ci.cname, md.Name)
			}
			proto, err := g.methodProto(ci, m)
			if err != nil {
				return err
			}
			b.WriteString(proto + "\n")
		}
		b.WriteString("\n")
		for _, md := range ci.decl.Methods {
			if md.IsDeinit {
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
		return nil
	})
}

// mergeSubst 合并替换表（外层 + 本实例）。
func mergeSubst(base, add map[string]xfront.TypeRef) map[string]xfront.TypeRef {
	out := map[string]xfront.TypeRef{}
	for k, v := range base {
		out[k] = v
	}
	for k, v := range add {
		out[k] = v
	}
	return out
}

// withSubst 在实例替换表下执行 fn。
func (g *gen) withSubst(ci *classInfo, fn func() error) error {
	saved := g.subst
	if ci != nil && len(ci.subst) > 0 {
		g.subst = mergeSubst(saved, ci.subst)
	}
	err := fn()
	g.subst = saved
	return err
}
