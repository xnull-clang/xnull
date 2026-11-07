package sema

import (
	"fmt"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

// ---------- M1 / GEN-01：泛型函数语义（S1 §8） ----------
//
// 分工（见 收件箱/CEO2/请求-GEN-01跨域支援-2026-11-07.md）：
//   - sema：类型参数作用域、显式实参校验、推断/合一/冲突/未绑定、
//     重载解析、`T` 不可 void、`new T()` 拒绝、无限展开诊断；
//     推断成功后把最终类型实参写回 `Call.TypeArgs`。
//   - codegen：按 `Call.TypeArgs` 生成单态化实例（本包不重复该工作）。
//
// 诊断码段位 GEN-1xx：
//   GEN-101 显式类型实参（数量/void/非泛型）
//   GEN-102 推断（冲突/未绑定/null）
//   GEN-103 重载（歧义/零候选）
//   GEN-104 类型参数作用域 / new T() / 无限展开

const (
	GenTypeArgs = "GEN-101"
	GenInfer    = "GEN-102"
	GenOverload = "GEN-103"
	GenScope    = "GEN-104"
)

// resolveUserCall 解析顶层函数调用（含泛型重载、推断与重载选择）。
func (e *tyenv) resolveUserCall(n *xfront.Call, name string) texpr {
	cands := e.funcs[name]
	if len(cands) == 0 {
		for _, a := range n.Args {
			e.infer(a)
		}
		return texpr{}
	}
	argTypes := make([]texpr, len(n.Args))
	oldQuiet := e.quietCtor
	e.quietCtor = true // 重载预推断：Ok/Err 无目标类型先不报错，选定候选后再按形参检查
	for i, a := range n.Args {
		argTypes[i] = e.infer(a)
	}
	e.quietCtor = oldQuiet
	if len(n.TypeArgs) > 0 {
		return e.resolveExplicit(n, name, cands, argTypes)
	}

	// 无显式实参：普通同名函数优先（§8.2 重载；codegen 的 callName 同口径）。
	var plain []*xfront.TopFunc
	for _, f := range cands {
		if len(f.TypePars) == 0 && len(f.Params) == len(n.Args) {
			plain = append(plain, f)
		}
	}
	if len(plain) == 1 {
		// 唯一普通候选且实参匹配：直接选中。
		if e.callArgsAssignable(argTypes, plain[0].Params, nil) {
			return e.finishCall(n, plain[0], argTypes, nil)
		}
		// 实参不匹配：若没有同元数泛型候选，仍由 finishCall 报 TY-101（既有口径）；
		// 若有泛型候选，继续走泛型解析（§8.2）。
		hasGen := false
		for _, f := range cands {
			if len(f.TypePars) > 0 && len(f.Params) == len(n.Args) {
				hasGen = true
				break
			}
		}
		if !hasGen {
			return e.finishCall(n, plain[0], argTypes, nil)
		}
	}
	var plainOK []*xfront.TopFunc
	for _, f := range plain {
		if e.callArgsAssignable(argTypes, f.Params, nil) {
			plainOK = append(plainOK, f)
		}
	}
	if len(plainOK) == 1 {
		return e.finishCall(n, plainOK[0], argTypes, nil)
	}
	if len(plainOK) > 1 {
		e.errf(n.P, GenOverload, "调用 `"+name+"` 存在多个适用候选，歧义（§8.2）", "显式消除重载或调整实参类型")
		return texpr{}
	}

	// 泛型候选：逐个做合一；成功者构成候选集。
	type genCand struct {
		f     *xfront.TopFunc
		subst map[string]string
	}
	var genOK []genCand
	var genArity []*xfront.TopFunc
	conflict, unbound := "", ""
	var inapplicable *xfront.TopFunc
	for _, f := range cands {
		if len(f.TypePars) == 0 || len(f.Params) != len(n.Args) {
			continue
		}
		genArity = append(genArity, f)
		subst, kind, msg := e.inferTypeArgs(f, argTypes)
		switch kind {
		case "":
			genOK = append(genOK, genCand{f, subst})
		case "conflict":
			if conflict == "" {
				conflict = msg
			}
		case "unbound":
			if unbound == "" {
				unbound = msg
			}
		case "inapplicable":
			if inapplicable == nil {
				inapplicable = f
			}
		}
	}
	if len(genOK) == 1 {
		return e.finishCall(n, genOK[0].f, argTypes, genOK[0].subst)
	}
	if len(genOK) > 1 {
		e.errf(n.P, GenOverload, "调用 `"+name+"` 存在多个适用的泛型候选，歧义（§8.2）", "显式写类型实参")
		return texpr{}
	}
	if conflict != "" {
		e.errf(n.P, GenInfer, conflict, "同一类型参数必须绑定到同一类型")
		return texpr{}
	}
	if unbound != "" {
		e.errf(n.P, GenInfer, unbound, "显式写类型实参，或让实参唯一确定类型参数")
		return texpr{}
	}
	if len(genArity) == 1 && inapplicable != nil {
		// 唯一泛型候选但实参不匹配：走 TY-101，保持“形参具体类型”口径。
		return e.finishCall(n, genArity[0], argTypes, map[string]string{})
	}
	e.errf(n.P, GenOverload,
		fmt.Sprintf("函数 `%s` 没有匹配的实参列表（实参 %d 个，§8.2）", name, len(n.Args)),
		"检查参数数量与类型，或显式写类型实参")
	return texpr{}
}

// resolveExplicit 处理带显式类型实参的调用。
func (e *tyenv) resolveExplicit(n *xfront.Call, name string, cands []*xfront.TopFunc, argTypes []texpr) texpr {
	var generic []*xfront.TopFunc
	for _, f := range cands {
		if len(f.TypePars) > 0 {
			generic = append(generic, f)
		}
	}
	if len(generic) == 0 {
		e.errf(n.P, GenTypeArgs, "`"+name+"` 不是泛型函数，不接受类型实参（§8.2）", "去掉 <...> 类型实参")
		return texpr{}
	}
	// 数量必须与某个候选一致；优先精确匹配。
	var byCount []*xfront.TopFunc
	for _, f := range generic {
		if len(f.TypePars) == len(n.TypeArgs) {
			byCount = append(byCount, f)
		}
	}
	if len(byCount) == 0 {
		f := generic[0]
		e.errf(n.P, GenTypeArgs,
			fmt.Sprintf("类型实参数量不符：`%s` 期望 %d 个，实际 %d 个（§8.2）", name, len(f.TypePars), len(n.TypeArgs)),
			"按声明补齐或删除类型实参")
		return texpr{}
	}
	for _, ta := range n.TypeArgs {
		e.checkTypeParamRef(ta, n.P)
		if typeKey(ta) == "void" {
			e.errf(n.P, GenTypeArgs, "类型实参不能是 void（§8.3）", "换用具体类型")
			return texpr{}
		}
	}
	var applicable []*xfront.TopFunc
	var firstSubst map[string]string
	for _, f := range byCount {
		if len(f.Params) != len(n.Args) {
			continue
		}
		subst := map[string]string{}
		for i, tp := range f.TypePars {
			subst[tp] = typeKey(n.TypeArgs[i])
		}
		if e.callArgsAssignable(argTypes, f.Params, subst) {
			applicable = append(applicable, f)
			if firstSubst == nil {
				firstSubst = subst
			}
		}
	}
	if len(applicable) == 1 {
		return e.finishCall(n, applicable[0], argTypes, firstSubst)
	}
	if len(applicable) > 1 {
		e.errf(n.P, GenOverload, "调用 `"+name+"` 的显式类型实参匹配多个候选，歧义（§8.2）", "消除重载或调整实参类型")
		return texpr{}
	}
	if len(byCount) == 1 {
		subst := map[string]string{}
		for i, tp := range byCount[0].TypePars {
			subst[tp] = typeKey(n.TypeArgs[i])
		}
		return e.finishCall(n, byCount[0], argTypes, subst)
	}
	e.errf(n.P, GenOverload, "函数 `"+name+"` 的实参与显式类型实参不匹配（实参 "+fmt.Sprint(len(n.Args))+" 个，§8.2）", "检查实参类型")
	return texpr{}
}

// inferTypeArgs 对一个泛型候选做类型实参推断（§8.2）。
func (e *tyenv) inferTypeArgs(f *xfront.TopFunc, argTypes []texpr) (map[string]string, string, string) {
	tps := map[string]bool{}
	for _, tp := range f.TypePars {
		tps[tp] = true
	}
	subst := map[string]string{}
	sawNull := false
	for i, p := range f.Params {
		ok, conflict, isNull := unifyType(p.Type, argTypes[i], tps, subst)
		if conflict {
			return nil, "conflict",
				"类型参数冲突绑定：`" + f.Name + "` 的同一类型参数得到不同实参类型（§8.2）"
		}
		if !ok {
			return subst, "inapplicable", ""
		}
		if isNull {
			sawNull = true
		}
	}
	for _, tp := range f.TypePars {
		if _, bound := subst[tp]; !bound {
			if sawNull {
				return nil, "unbound",
					"类型参数 `" + tp + "` 未绑定：null 实参不能让类型参数唯一确定（§8.2）"
			}
			return nil, "unbound", "类型参数 `" + tp + "` 未绑定（§8.2）"
		}
	}
	return subst, "", ""
}

// unifyType 把形参 TypeRef 与实参类型串合一；conflict 表示同一 T 绑定不同。
func unifyType(t xfront.TypeRef, arg texpr, tps map[string]bool, subst map[string]string) (ok, conflict, isNull bool) {
	argKey := arg.key
	if argKey == "" {
		return true, false, false // 未知实参类型：不绑定，交由未绑定检查
	}
	switch ty := t.(type) {
	case *xfront.NamedType:
		name := ty.Qual[len(ty.Qual)-1]
		if len(ty.Args) == 0 {
			if tps[name] {
				if arg.lit == 4 {
					return true, false, true
				}
				if prev, bound := subst[name]; bound {
					if arg.lit != 0 {
						// 字面量适配已绑定的 T（§8.2），例如 pick(1L, 2)；不适配即冲突。
						if assignable(arg, prev) {
							return true, false, false
						}
						return false, true, false
					}
					if prev != argKey {
						return false, true, false
					}
					return true, false, false
				}
				subst[name] = argKey
				return true, false, false
			}
			if name == argKey {
				return true, false, false
			}
			return assignable(arg, name), false, false
		}
		argBase, argArgs, okBase := splitNamedKey(argKey)
		if !okBase || argBase != name || len(argArgs) != len(ty.Args) {
			return false, false, false
		}
		for i, a := range ty.Args {
			o, c, n := unifyType(a, texpr{key: argArgs[i]}, tps, subst)
			if !o || c {
				return o, c, n
			}
		}
		return true, false, false
	case *xfront.SuffixedType:
		key := argKey
		for _, suf := range ty.Suffixes {
			if !strings.HasSuffix(key, suf) {
				return false, false, false
			}
			key = strings.TrimSuffix(key, suf)
		}
		return unifyType(ty.Base, texpr{key: key}, tps, subst)
	case *xfront.TupleTypeRef:
		if !strings.HasPrefix(argKey, "(") || !strings.HasSuffix(argKey, ")") {
			return false, false, false
		}
		parts := splitTypeArgs(argKey[1 : len(argKey)-1])
		if len(parts) != len(ty.Elems) {
			return false, false, false
		}
		for i, el := range ty.Elems {
			o, c, n := unifyType(el, texpr{key: parts[i]}, tps, subst)
			if !o || c {
				return o, c, n
			}
		}
		return true, false, false
	case *xfront.FuncTypeRef:
		ret, params, okf := funcTypeParts(argKey)
		if !okf {
			return false, false, false
		}
		o, c, _ := unifyType(ty.Ret, texpr{key: ret}, tps, subst)
		if !o || c {
			return o, c, false
		}
		if len(params) != len(ty.Params) {
			return false, false, false
		}
		for i, p := range ty.Params {
			o, c, _ := unifyType(p, texpr{key: params[i]}, tps, subst)
			if !o || c {
				return o, c, false
			}
		}
		return true, false, false
	}
	return false, false, false
}

// splitNamedKey 拆 "Name<A,B>"；非泛型返回 Name + nil。
func splitNamedKey(key string) (string, []string, bool) {
	i := strings.Index(key, "<")
	if i < 0 {
		if key == "" {
			return "", nil, false
		}
		return key, nil, true
	}
	if !strings.HasSuffix(key, ">") {
		return "", nil, false
	}
	return key[:i], splitTypeArgs(key[i+1 : len(key)-1]), true
}

// callArgsAssignable 判断实参是否可赋给（替换后的）形参。
func (e *tyenv) callArgsAssignable(argTypes []texpr, params []*xfront.Param, subst map[string]string) bool {
	if len(argTypes) != len(params) {
		return false
	}
	for i, p := range params {
		want := substKey(typeKey(p.Type), subst)
		if want == "" {
			continue
		}
		if !assignable(argTypes[i], want) {
			return false
		}
	}
	return true
}

// finishCall 完成候选收尾：写回 TypeArgs、检查实参、返回替换后的返回类型。
func (e *tyenv) finishCall(n *xfront.Call, f *xfront.TopFunc, argTypes []texpr, subst map[string]string) texpr {
	// 推断结果写回 AST（codegen 单态化的输入契约）。
	if len(n.TypeArgs) == 0 && len(f.TypePars) > 0 {
		refs := make([]xfront.TypeRef, len(f.TypePars))
		for i, tp := range f.TypePars {
			refs[i] = typeRefFromKey(subst[tp], n.P)
		}
		n.TypeArgs = refs
	}
	// 自递归且类型实参未推进 → 无限展开（§8.3；直接递归的最小判据）。
	if len(f.TypePars) > 0 && e.curFunc == f.Name {
		identity := true
		for i, tp := range f.TypePars {
			key := ""
			if len(n.TypeArgs) > i {
				key = typeKey(n.TypeArgs[i])
			}
			if key != tp {
				identity = false
				break
			}
		}
		if identity {
			e.errf(n.P, GenScope, "泛型实例无限展开：`"+f.Name+"` 的类型实参未收敛（§8.3）", "引入递归终止条件，或改写为非泛型")
		}
	}
	for i, p := range f.Params {
		want := substKey(typeKey(p.Type), subst)
		if want == "" || want == "void" {
			continue
		}
		at := argTypes[i]
		// Ok/Err 构造实参需要目标类型：选定候选后按形参类型重新推断。
		if isCtorCall(n.Args[i]) {
			at = e.inferExpected(n.Args[i], want)
		}
		if !assignable(at, want) {
			e.errf(n.Args[i].Pos(), TyAssignability,
				fmt.Sprintf("实参 %d 类型 %s 不能赋给形参 %s（§2.6）", i+1, describeKey(at), want),
				hintFor(at, want))
		}
	}
	if f.Void {
		return texpr{key: "void"}
	}
	return texpr{key: substKey(typeKey(f.Ret), subst)}
}

// substKey 在类型串中按完整标识符替换类型参数。
func substKey(key string, subst map[string]string) string {
	if len(subst) == 0 || key == "" {
		return key
	}
	var b strings.Builder
	for i := 0; i < len(key); {
		c := key[i]
		if c == '_' || c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' {
			j := i + 1
			for j < len(key) {
				d := key[j]
				if d == '_' || d >= 'a' && d <= 'z' || d >= 'A' && d <= 'Z' || d >= '0' && d <= '9' {
					j++
					continue
				}
				break
			}
			tok := key[i:j]
			if rep, ok := subst[tok]; ok && rep != "" {
				b.WriteString(rep)
			} else {
				b.WriteString(tok)
			}
			i = j
			continue
		}
		b.WriteByte(c)
		i++
	}
	return b.String()
}

// typeRefFromKey 把规范化类型串还原为 TypeRef（供 Call.TypeArgs 写回）。
func typeRefFromKey(key string, p xfront.Pos) xfront.TypeRef {
	key = strings.TrimSpace(key)
	if key == "" {
		return nil
	}
	if strings.HasSuffix(key, "[]") {
		return &xfront.SuffixedType{P: p, Base: typeRefFromKey(strings.TrimSuffix(key, "[]"), p), Suffixes: []string{"[]"}}
	}
	if strings.HasSuffix(key, "?") {
		return &xfront.SuffixedType{P: p, Base: typeRefFromKey(strings.TrimSuffix(key, "?"), p), Suffixes: []string{"?"}}
	}
	if strings.HasPrefix(key, "(") && strings.HasSuffix(key, ")") {
		inner := key[1 : len(key)-1]
		var elems []xfront.TypeRef
		if strings.TrimSpace(inner) != "" {
			for _, part := range splitTypeArgs(inner) {
				elems = append(elems, typeRefFromKey(part, p))
			}
		}
		return &xfront.TupleTypeRef{P: p, Elems: elems}
	}
	if i := strings.Index(key, "("); i > 0 && strings.HasSuffix(key, ")") {
		ret := typeRefFromKey(key[:i], p)
		var params []xfront.TypeRef
		inner := key[i+1 : len(key)-1]
		if strings.TrimSpace(inner) != "" {
			for _, part := range splitTypeArgs(inner) {
				params = append(params, typeRefFromKey(part, p))
			}
		}
		return &xfront.FuncTypeRef{P: p, Ret: ret, Params: params}
	}
	if i := strings.Index(key, "<"); i > 0 && strings.HasSuffix(key, ">") {
		var args []xfront.TypeRef
		for _, part := range splitTypeArgs(key[i+1 : len(key)-1]) {
			args = append(args, typeRefFromKey(part, p))
		}
		return &xfront.NamedType{P: p, Qual: []string{key[:i]}, Args: args}
	}
	return &xfront.NamedType{P: p, Qual: []string{key}}
}

// checkTypeParamRef 检查类型位置上的类型参数是否在当前作用域（§8.1）。
func (e *tyenv) checkTypeParamRef(t xfront.TypeRef, p xfront.Pos) {
	switch ty := t.(type) {
	case nil:
		return
	case *xfront.NamedType:
		name := ty.Qual[len(ty.Qual)-1]
		if e.a.tc != nil {
			e.a.tc.checkSyncTypeRef(ty)
		}
		if len(ty.Args) == 0 {
			if e.a.tc != nil {
				if info, ok := e.a.tc.types[name]; ok && info.kind == "factory" {
					e.errf(ty.P, TyFactory, "factory `"+name+"` 不是类型，不能用于类型位置（§10.4）", "改用 Target 类型或工厂方法返回类型")
					return
				}
				if info, ok := e.a.tc.types[name]; ok && info.kind == "annotation" {
					e.errf(ty.P, TyAnnotation, "注解 `"+name+"` 不是类型，不能用于类型位置（§12.1）", "")
					return
				}
			}
			if e.a.typeParamNames[name] && !e.typePars[name] && !e.typeDeclared(name) {
				e.errf(ty.P, ResUndefined,
					"类型参数 `"+name+"` 未定义：类型参数只在声明它的函数/类型内可见（§8.1）", "在函数名后声明 <"+name+">，或改用具体类型")
				return
			}
			// 签名/字段/局部类型位置的未知单段类型名：按 §3.3/§8.1 报未定义。
			// 限定名（pkg.Type）交由导入/XDK 诊断处理，避免误伤跨包类型。
			if len(ty.Qual) == 1 && name != "<err>" && !e.typePars[name] && !e.typeDeclared(name) && !xdkSymbolKnown(name) {
				e.errf(ty.P, ResUndefined, "未定义的类型 `"+name+"`（§3.3/§8.1）", "检查拼写，或先声明/导入该类型")
				return
			}
		}
		for _, a := range ty.Args {
			e.checkTypeParamRef(a, ty.P)
		}
	case *xfront.SuffixedType:
		e.checkTypeParamRef(ty.Base, ty.P)
	case *xfront.FuncTypeRef:
		e.checkTypeParamRef(ty.Ret, ty.P)
		for _, a := range ty.Params {
			e.checkTypeParamRef(a, ty.P)
		}
	case *xfront.TupleTypeRef:
		for _, a := range ty.Elems {
			e.checkTypeParamRef(a, ty.P)
		}
	}
}

// externalTypes 是绑定层（FFI）注入的不透明类型名（File/Dir 等）。
// 这些类型不在源码包内声明，但 P-09 注入的签名与局部声明必须能解析；
// 由构建入口在 Analyze 前登记（codegen.Build）。
var externalTypes = map[string]bool{}

// RegisterExternalTypes 登记绑定层注入的类型名（幂等；只在类型可见性检查中放行）。
func RegisterExternalTypes(names ...string) {
	for _, n := range names {
		if n != "" {
			externalTypes[n] = true
		}
	}
}

// typeDeclared 判断名字是否是已声明/预定义/已导入的可用类型（非类型参数）。
func (e *tyenv) typeDeclared(name string) bool {
	if name == "void" || builtinTypeNames[name] {
		return true
	}
	if externalTypes[name] {
		return true
	}
	if e.a.imported[name] {
		return true
	}
	if e.a.tc != nil {
		if _, ok := e.a.tc.types[name]; ok {
			return true
		}
	}
	return false
}

// isCtorCall 判断调用表达式是否为 Ok/Err 构造器（需要目标类型）。
func isCtorCall(x xfront.Expr) bool {
	c, ok := x.(*xfront.Call)
	if !ok {
		return false
	}
	id, ok := c.Callee.(*xfront.IdentExpr)
	return ok && (id.Name == "Ok" || id.Name == "Err")
}
