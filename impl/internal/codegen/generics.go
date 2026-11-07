// generics.go：泛型函数单态化（S1 §8.3）在代码生成侧的那一半。
//
// 分工（见 收件箱/CEO2/请求-GEN-01跨域支援-2026-11-07.md）：
//   - sema 负责：类型参数作用域、显式实参校验、推断/合一/冲突/未绑定、
//     重载解析、`T` 不可 void、`new T()` 拒绝，并**把推断结果写回
//     `Call.TypeArgs`**（本文件只消费该字段，不读 sema 内部）。
//   - 本文件负责：每个「类型实参列表」生成一个独立 C 函数实例、
//     实例名内部编码（不外露给源码）、实例内 `T` 的替换、递归展开上限。
//
// 因此本层对「显式实参」的调用已经可以独立工作；推断型调用要等 sema
// 写回 TypeArgs 之后自动生效，无需再改本文件。
package codegen

import (
	"fmt"
	"sort"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

// maxInstDepth 是单态化递归展开上限（§8.3：必须终止，超限必须产生诊断，
// 不得静默截断）。按「一轮新发现的实例」计数，而非全局实例数，
// 以免合法的大批实例被误判。
const maxInstDepth = 64

// instInfo 是一个单态化实例。
type instInfo struct {
	fn       *xfront.TopFunc
	typeArgs []xfront.TypeRef
	cname    string                    // C 函数名（xn_<name>_<编码>）
	subst    map[string]xfront.TypeRef // 类型参数 → 具体类型
	retC     string
}

// typeArgCode 把类型实参编码成实例名后缀（§8.3：实例名由编译器内部编码）。
func typeArgCode(t xfront.TypeRef) (string, error) {
	switch n := t.(type) {
	case *xfront.NamedType:
		nm := typeName(n)
		if len(n.Args) == 0 {
			switch nm {
			case "Int":
				return "i", nil
			case "Bool":
				return "b", nil
			case "String":
				return "s", nil
			case "void":
				return "", fmt.Errorf("codegen：类型参数不能是 void（§8.3）")
			}
			if nm == "" {
				return "", fmt.Errorf("codegen：类型实参缺少名字")
			}
			return "o_" + nm, nil
		}
		sub := make([]string, 0, len(n.Args))
		for _, a := range n.Args {
			c, err := typeArgCode(a)
			if err != nil {
				return "", err
			}
			sub = append(sub, c)
		}
		switch nm {
		case "List":
			return "L" + strings.Join(sub, "_"), nil
		case "Set":
			return "S" + strings.Join(sub, "_"), nil
		case "Map":
			return "M" + strings.Join(sub, "_"), nil
		case "Result":
			return "R" + strings.Join(sub, "_"), nil
		}
		return "o_" + nm + "_" + strings.Join(sub, "_"), nil
	case *xfront.SuffixedType:
		base, err := typeArgCode(n.Base)
		if err != nil {
			return "", err
		}
		if len(n.Suffixes) == 1 && n.Suffixes[0] == "[]" {
			return "A" + base, nil
		}
		return "", fmt.Errorf("codegen：类型实参后缀 %v 未支持（§8.3 单态化）", n.Suffixes)
	}
	return "", fmt.Errorf("codegen：类型实参 %T 未支持（§8.3 单态化）", t)
}

// substitute 把类型参数替换为具体类型（深替换，作用于整个 TypeRef 树）。
func (g *gen) substitute(t xfront.TypeRef) xfront.TypeRef {
	if len(g.subst) == 0 || t == nil {
		return t
	}
	switch n := t.(type) {
	case *xfront.NamedType:
		if len(n.Args) == 0 && len(n.Qual) == 1 {
			if rep, ok := g.subst[n.Qual[0]]; ok {
				return rep
			}
		}
		if len(n.Args) == 0 {
			return n
		}
		args := make([]xfront.TypeRef, len(n.Args))
		for i, a := range n.Args {
			args[i] = g.substitute(a)
		}
		return &xfront.NamedType{P: n.P, Qual: n.Qual, Args: args}
	case *xfront.SuffixedType:
		return &xfront.SuffixedType{P: n.P, Base: g.substitute(n.Base), Suffixes: n.Suffixes}
	}
	return t
}

// collectGenerics 登记带类型参数的顶层函数（不进入普通签名表）。
func (g *gen) collectGenerics(u *xfront.CompilationUnit) {
	for _, d := range u.Decls {
		if fn, ok := d.(*xfront.TopFunc); ok && len(fn.TypePars) > 0 {
			g.generics[fn.Name] = fn
		}
	}
}

// isGenericName 判断是否已知的泛型函数名。
func (g *gen) isGenericName(name string) bool {
	_, ok := g.generics[name]
	return ok
}

// callName 计算调用点的 C 函数名：带类型实参 → 实例名；否则普通名。
// 泛型函数缺少类型实参时显式报错（推断结果由 sema 写回 Call.TypeArgs）。
func (g *gen) callName(name string, typeArgs []xfront.TypeRef, argc int) (string, error) {
	typeArgs = g.substTypeArgs(typeArgs)
	if len(typeArgs) == 0 {
		// main 重载（§11.2）：非匹配签名的 main 是普通函数，按参数个数分派到独立 C 名。
		if name == "main" {
			if c, ok := g.mainCallName(argc); ok {
				return c, nil
			}
		}
		// 同名普通函数优先（§8.2 重载：无类型实参的非泛型调用）。
		if _, ok := g.fnRet[name]; ok {
			return "xn_" + name, nil
		}
		if g.isGenericName(name) {
			return "", fmt.Errorf("codegen：泛型函数 `%s` 调用缺少类型实参（推断结果应由 sema 写回 Call.TypeArgs，§8.2）", name)
		}
		return "xn_" + name, nil
	}
	inst, err := g.needInstance(name, typeArgs)
	if err != nil {
		return "", err
	}
	return inst.cname, nil
}

// mainCallName 按参数个数选择 main 的 C 名：入口优先，其后是非匹配重载。
// argc < 0 表示调用点未提供实参个数（仅类型推断路径），交给默认 xn_main。
func (g *gen) mainCallName(argc int) (string, bool) {
	if argc < 0 {
		return "", false
	}
	// 非入口重载优先（用户代码调用普通函数）；0 参只可能是入口。
	if argc > 0 {
		if c, ok := g.mainOverloads[argc]; ok {
			return c, true
		}
	}
	if g.entry != nil && len(g.entry.fn.Params) == argc {
		return "xn_main", true
	}
	if c, ok := g.mainOverloads[argc]; ok {
		return c, true
	}
	return "", false
}

// callErr 返回 callName 的失败原因（供 exprType 等处给出准确诊断）。
func (g *gen) callErr(name string, typeArgs []xfront.TypeRef) error {
	_, err := g.callName(name, typeArgs, -1)
	if err == nil {
		return fmt.Errorf("调用 `%s` 无法解析类型", name)
	}
	return err
}

// callRetC 计算调用点的返回 C 类型（实例按具体类型，普通函数查签名表）。
func (g *gen) callRetC(name string, typeArgs []xfront.TypeRef) (string, bool) {
	typeArgs = g.substTypeArgs(typeArgs)
	if len(typeArgs) == 0 {
		rc, ok := g.fnRet[name]
		return rc, ok
	}
	inst, err := g.needInstance(name, typeArgs)
	if err != nil {
		return "", false
	}
	return inst.retC, true
}

// substTypeArgs 把调用点的类型实参在当前实例替换表下求值。
// 关键：泛型函数内再调用泛型时，实参里可能含外层类型参数（如 grow<List<T>>），
// 必须先替换再编码，否则实例名会固化成 Lo_T 而无法展开/区分。
func (g *gen) substTypeArgs(typeArgs []xfront.TypeRef) []xfront.TypeRef {
	if len(typeArgs) == 0 || len(g.subst) == 0 {
		return typeArgs
	}
	out := make([]xfront.TypeRef, len(typeArgs))
	for i, a := range typeArgs {
		out[i] = g.substitute(a)
	}
	return out
}

// needInstance 登记（或复用）一个实例；不做生成，生成由 EmitC 的展开轮驱动。
func (g *gen) needInstance(name string, typeArgs []xfront.TypeRef) (*instInfo, error) {
	fn, ok := g.generics[name]
	if !ok {
		if len(typeArgs) > 0 {
			return nil, fmt.Errorf("codegen：`%s` 不是泛型函数，却给出了类型实参（§8.2）", name)
		}
		return nil, fmt.Errorf("codegen：未知函数 %s", name)
	}
	if len(typeArgs) != len(fn.TypePars) {
		return nil, fmt.Errorf("codegen：`%s` 需要 %d 个类型实参，实际 %d 个（§8.2）",
			name, len(fn.TypePars), len(typeArgs))
	}
	// 类型实参不能仍是本函数的类型参数（未解析），否则会生成 xn_f_T 这类未替换符号。
	for _, a := range typeArgs {
		if nt, ok := a.(*xfront.NamedType); ok && len(nt.Args) == 0 && len(nt.Qual) == 1 {
			for _, tp := range fn.TypePars {
				if nt.Qual[0] == tp {
					return nil, fmt.Errorf("codegen：`%s` 的类型实参仍是类型参数 `%s`（未解析，§8.2 推断未完成）", name, tp)
				}
			}
		}
	}
	codes := make([]string, 0, len(typeArgs))
	for _, a := range typeArgs {
		c, err := typeArgCode(a)
		if err != nil {
			return nil, err
		}
		codes = append(codes, c)
	}
	cname := "xn_" + name + "_" + strings.Join(codes, "_")
	if inst, ok := g.insts[cname]; ok {
		return inst, nil
	}
	subst := map[string]xfront.TypeRef{}
	for i, tp := range fn.TypePars {
		subst[tp] = typeArgs[i]
	}
	inst := &instInfo{fn: fn, typeArgs: typeArgs, cname: cname, subst: subst}
	// 返回类型在替换后求（Result<T,String> 之类必须替换后再判名）。
	saved := g.subst
	g.subst = subst
	rc, err := g.cType(fn.Ret)
	g.subst = saved
	if err != nil {
		return nil, err
	}
	if fn.Void {
		rc = "void"
	}
	inst.retC = rc
	g.insts[cname] = inst
	g.instOrder = append(g.instOrder, cname)
	return inst, nil
}

// genInstance 生成一个实例的函数体（临时替换 g.subst）。
func (g *gen) genInstance(inst *instInfo) (string, error) {
	saved := g.subst
	g.subst = inst.subst
	defer func() { g.subst = saved }()
	return g.genFuncNamed(inst.fn, inst.cname)
}

// expandInstances 反复试生成新发现的实例，直到不再增长（§8.3 递归单态化）。
// 超过 maxInstDepth 轮仍有新实例 → 诊断为无限展开，不静默截断。
func (g *gen) expandInstances() error {
	seen := map[string]bool{}
	for round := 0; ; round++ {
		var todo []string
		for _, cn := range g.instOrder {
			if !seen[cn] {
				todo = append(todo, cn)
			}
		}
		if len(todo) == 0 {
			return nil
		}
		if round >= maxInstDepth {
			sort.Strings(todo)
			return fmt.Errorf("codegen：泛型单态化展开超过上限 %d 轮（§8.3 无限展开诊断）：最近实例 %s；"+
				"检查泛型函数是否以自身类型实参递归调用", maxInstDepth, todo[0])
		}
		for _, cn := range todo {
			seen[cn] = true
			if _, err := g.genInstance(g.insts[cn]); err != nil {
				return err
			}
		}
	}
}

// instNames 返回确定顺序的实例名（DET-01）。
func (g *gen) instNames() []string {
	out := make([]string, 0, len(g.insts))
	for cn := range g.insts {
		out = append(out, cn)
	}
	sort.Strings(out)
	return out
}
