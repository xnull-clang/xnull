// extension.go：扩展方法发射（S2 §11 / BND-13 / EXT-01）。
//
// 扩展方法合入目标类型的静态方法集合（同包非泛型 class/struct/singleton/
// 数据 enum），生成独立 C 函数并参与正常静态派发；不进入 vtable、不能作为
// 协议实现。扩展不改变布局/内存策略。
package codegen

import (
	"fmt"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

type extensionInfo struct {
	decl   *xfront.ExtensionDecl
	target *classInfo
	method []*classInfo_m
}

// collectExtensions 登记扩展方法（重复/同签名/非法目标显式报错）。
func (g *gen) collectExtensions(u *xfront.CompilationUnit) error {
	for _, d := range u.Decls {
		ed, ok := d.(*xfront.ExtensionDecl)
		if !ok {
			continue
		}
		nt, ok := ed.Target.(*xfront.NamedType)
		if !ok {
			return fmt.Errorf("codegen：extension 目标必须是命名类型（S2 §11.1）")
		}
		if len(nt.Args) > 0 {
			return fmt.Errorf("codegen：extension 不能扩展泛型实例化 %s（S2 §11.1）", typeName(nt))
		}
		name := typeName(nt)
		ci, ok := g.extensionTarget(name)
		if !ok {
			return fmt.Errorf("codegen：extension 目标 %s 不是 class/struct/singleton/数据 enum（S2 §11.1）", name)
		}
		if decl, ok := g.classDecls[name]; ok && len(decl.TypePars) > 0 {
			return fmt.Errorf("codegen：extension 不能扩展泛型类型 %s（S2 §11.1）", name)
		}
		ei := &extensionInfo{decl: ed, target: ci}
		for _, m := range ed.Methods {
			if m.Mod.Static {
				return fmt.Errorf("codegen：extension 不能添加静态方法 %s（S2 §11.1）", m.Name)
			}
			if len(m.TypePars) > 0 {
				return fmt.Errorf("codegen：extension 不支持泛型方法 %s（S2 §11.4）", m.Name)
			}
			if m.IsDeinit {
				return fmt.Errorf("codegen：extension 不能添加 deinit（S2 §11.1）")
			}
			if _, dup := ci.methods[m.Name]; dup {
				return fmt.Errorf("codegen：扩展方法 %s.%s 与已有方法同名/同签名（S2 §11.4）", name, m.Name)
			}
			if ci.base != nil {
				if _, inherited := ci.base.methodOf(m.Name); inherited {
					return fmt.Errorf("codegen：扩展方法 %s.%s 与继承方法同名/同签名（S2 §11.4）", name, m.Name)
				}
			}
			cm := &classInfo_m{decl: m, cname: fmt.Sprintf("%s_ext_%s_%d", ci.cname, m.Name, len(m.Params)), owner: ci, ext: true}
			ci.methods[m.Name] = cm
			ei.method = append(ei.method, cm)
		}
		g.extensions = append(g.extensions, ei)
	}
	return nil
}

// extensionTarget 解析扩展目标（class/struct/singleton/数据 enum）。
func (g *gen) extensionTarget(name string) (*classInfo, bool) {
	if ci, ok := g.classOf(name); ok {
		return ci, true
	}
	if ci, ok := g.structs[name]; ok {
		return ci, true
	}
	if ci, ok := g.singletons[name]; ok {
		return ci, true
	}
	if ei, ok := g.enums[name]; ok && !ei.simple && ei.cls != nil {
		return ei.cls, true
	}
	return nil, false
}

// emitExtensionProtos 扩展方法原型（必须早于调用点）。
func (g *gen) emitExtensionProtos(b *strings.Builder) error {
	for _, ei := range g.extensions {
		for _, m := range ei.method {
			proto, err := g.methodProto(ei.target, m)
			if err != nil {
				return err
			}
			b.WriteString(proto + "\n")
		}
	}
	if len(g.extensions) > 0 {
		b.WriteString("\n")
	}
	return nil
}

// emitExtensions 扩展方法体（放在类/结构体方法之后、顶层函数之前）。
func (g *gen) emitExtensions(b *strings.Builder) error {
	for _, ei := range g.extensions {
		for _, m := range ei.method {
			body, err := g.genMethod(ei.target, m)
			if err != nil {
				return err
			}
			b.WriteString(body + "\n")
		}
	}
	return nil
}
