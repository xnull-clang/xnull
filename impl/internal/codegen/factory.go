// factory.go：工厂发射面（S2 §10 / BND-08）。
//
// 工厂不是类型、不分配对象：每个 `static` 工厂方法发射为顶层 C 函数
// `xn_Factory_<F>_<method>`；泛型方法走既有单态化（显式类型实参）。
// 工厂与 Target 的成员可见性/私有构造访问由 sema 负责；本层只发射调用。
package codegen

import (
	"fmt"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

type factoryInfo struct {
	decl     *xfront.FactoryDecl
	methods  map[string][]*xfront.MethodDecl // 方法名 → 重载集合
	cname    map[*xfront.MethodDecl]string   // 非泛型方法 C 名
	retC     map[*xfront.MethodDecl]string
	synFuncs []*xfront.TopFunc // 非泛型方法对应的顶层函数（发射体用）
}

// collectFactories 登记工厂声明与方法（泛型方法注册到 g.generics 单态化表）。
func (g *gen) collectFactories(u *xfront.CompilationUnit) error {
	for _, d := range u.Decls {
		fd, ok := d.(*xfront.FactoryDecl)
		if !ok {
			continue
		}
		fi := &factoryInfo{decl: fd, methods: map[string][]*xfront.MethodDecl{},
			cname: map[*xfront.MethodDecl]string{}, retC: map[*xfront.MethodDecl]string{}}
		for _, m := range fd.Methods {
			if !m.Mod.Static {
				return fmt.Errorf("codegen：工厂方法 %s.%s 必须 static（S2 §10.2）", fd.Name, m.Name)
			}
			if m.Void {
				return fmt.Errorf("codegen：工厂方法 %s.%s 不能返回 void（S2 §10.2）", fd.Name, m.Name)
			}
			synName := "Factory_" + fd.Name + "_" + m.Name
			tf := &xfront.TopFunc{P: m.P, Name: synName, Static: true, TypePars: m.TypePars,
				Void: m.Void, Ret: m.Ret, Params: m.Params, Body: m.Body}
			if len(m.TypePars) > 0 {
				g.generics[synName] = tf
				fi.cname[m] = "" // 由实例化决定
			} else {
				cn := "xn_" + synName
				fi.cname[m] = cn
				rc, err := g.cType(m.Ret)
				if err != nil {
					return err
				}
				fi.retC[m] = rc
				fi.synFuncs = append(fi.synFuncs, tf)
			}
			fi.methods[m.Name] = append(fi.methods[m.Name], m)
		}
		g.factories[fd.Name] = fi
		g.factoryOrder = append(g.factoryOrder, fd.Name)
	}
	return nil
}

// factoryMethod 解析 `Factory.method`。
func (g *gen) factoryMethod(mem *xfront.Member, argc int) (*factoryInfo, *xfront.MethodDecl, bool) {
	id, ok := mem.X.(*xfront.IdentExpr)
	if !ok {
		return nil, nil, false
	}
	fi, ok := g.factories[id.Name]
	if !ok {
		return nil, nil, false
	}
	list := fi.methods[mem.Name]
	for _, m := range list {
		if len(m.Params) == argc {
			return fi, m, true
		}
	}
	return nil, nil, false
}

// factoryCall 生成工厂方法调用表达式。
func (s *scope) factoryCall(mem *xfront.Member, call *xfront.Call) (string, string, error) {
	fi, m, ok := s.g.factoryMethod(mem, len(call.Args))
	if !ok {
		return "", "", fmt.Errorf("codegen：未定义的工厂方法 %s", mem.Name)
	}
	args, err := s.callArgs(call.Args)
	if err != nil {
		return "", "", err
	}
	if len(m.TypePars) > 0 {
		key := "Factory_" + fi.decl.Name + "_" + m.Name
		if len(call.TypeArgs) != len(m.TypePars) {
			return "", "", fmt.Errorf("codegen：工厂方法 %s.%s 需要 %d 个类型实参（§10.2）", fi.decl.Name, m.Name, len(m.TypePars))
		}
		inst, err := s.g.needInstance(key, call.TypeArgs)
		if err != nil {
			return "", "", err
		}
		return inst.cname + "(" + strings.Join(args, ", ") + ")", inst.retC, nil
	}
	return fi.cname[m] + "(" + strings.Join(args, ", ") + ")", fi.retC[m], nil
}

// emitFactories 发射非泛型工厂方法体（泛型实例由 expandInstances 发射）。
func (g *gen) emitFactories(b *strings.Builder) error {
	for _, name := range g.factoryOrder {
		fi := g.factories[name]
		for _, tf := range fi.synFuncs {
			// 找回对应 MethodDecl 的 C 名。
			var cn string
			for m, c := range fi.cname {
				if "Factory_"+fi.decl.Name+"_"+m.Name == tf.Name {
					cn = c
					break
				}
			}
			if cn == "" {
				continue
			}
			body, err := g.genFuncNamed(tf, cn)
			if err != nil {
				return err
			}
			b.WriteString(body + "\n")
		}
	}
	return nil
}

// tryFactoryCall 若 Member 是工厂方法则生成调用。
func (s *scope) tryFactoryCall(mem *xfront.Member, call *xfront.Call) (string, string, bool, error) {
	if _, _, ok := s.g.factoryMethod(mem, len(call.Args)); !ok {
		return "", "", false, nil
	}
	expr, retC, err := s.factoryCall(mem, call)
	return expr, retC, true, err
}
