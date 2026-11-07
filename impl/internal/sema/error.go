package sema

import (
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

// ---------- M1 / ERR-01：错误处理语义（S1 §10.1—§10.3） ----------
//
// 诊断码段位 ERR-2xx（错误处理）：
//   ERR-201 Result 是 @mustUse：裸表达式语句丢弃 Result（§10.1）
//   ERR-202 Result 构造/类型实参错误（Ok/Err 形参、E=void、无目标类型）
//   ERR-203 Result 成员误用（未知成员、arity、T/E=void、成员未调用）
//   ERR-204 try 上下文/错误类型不合法（§10.2）
//   ERR-205 defer/errdefer 清理体限制（§10.3）
//   ERR-206 errdefer 只能出现在返回 Result 的函数/闭包（§10.3）

// 诊断码。
const (
	ErResultMustUse   = "ERR-201"
	ErResultCtor      = "ERR-202"
	ErResultMember    = "ERR-203"
	ErTryContext      = "ERR-204"
	ErCleanupBody     = "ERR-205"
	ErErrdeferContext = "ERR-206"
)

// splitTypeArgs 按顶层逗号切分类型实参串，忽略 <> () [] 内的逗号。
func splitTypeArgs(s string) []string {
	var out []string
	depth, start := 0, 0
	for i, r := range s {
		switch r {
		case '<', '(', '[':
			depth++
		case '>', ')', ']':
			if depth > 0 {
				depth--
			}
		case ',':
			if depth == 0 {
				out = append(out, strings.TrimSpace(s[start:i]))
				start = i + 1
			}
		}
	}
	out = append(out, strings.TrimSpace(s[start:]))
	return out
}

// isResultKey 判断类型串是否 Result（裸 Result 视为 Result<Any,Any>）。
func isResultKey(key string) bool {
	return key == "Result" || (strings.HasPrefix(key, "Result<") && strings.HasSuffix(key, ">"))
}

// resultArgs 拆 Result<T,E>；裸 Result 返回 Any,Any。
func resultArgs(key string) (t, e string, ok bool) {
	if key == "Result" {
		return "Any", "Any", true
	}
	if !strings.HasPrefix(key, "Result<") || !strings.HasSuffix(key, ">") {
		return "", "", false
	}
	parts := splitTypeArgs(key[len("Result<") : len(key)-1])
	if len(parts) != 2 {
		return "", "", false
	}
	return parts[0], parts[1], true
}

// funcTypeParts 拆函数类型串 "Ret(P1,P2)"。
func funcTypeParts(key string) (ret string, params []string, ok bool) {
	i := strings.Index(key, "(")
	if i <= 0 || !strings.HasSuffix(key, ")") {
		return "", nil, false
	}
	ret = strings.TrimSpace(key[:i])
	if ret == "" {
		return "", nil, false
	}
	inner := key[i+1 : len(key)-1]
	if strings.TrimSpace(inner) == "" {
		return ret, nil, true
	}
	return ret, splitTypeArgs(inner), true
}

// elemWanted 从目标类型取容器元素类型（X[] / List<X> / Set<X>）。
func elemWanted(want string) (string, bool) {
	if strings.HasSuffix(want, "[]") {
		return strings.TrimSuffix(want, "[]"), true
	}
	for _, pre := range []string{"List<", "Set<"} {
		if strings.HasPrefix(want, pre) && strings.HasSuffix(want, ">") {
			parts := splitTypeArgs(want[len(pre) : len(want)-1])
			if len(parts) == 1 {
				return parts[0], true
			}
		}
	}
	return "", false
}

// mapWanted 从目标类型取 Map 的键/值类型。
func mapWanted(want string) (k, v string, ok bool) {
	if !strings.HasPrefix(want, "Map<") || !strings.HasSuffix(want, ">") {
		return "", "", false
	}
	parts := splitTypeArgs(want[len("Map<") : len(want)-1])
	if len(parts) != 2 {
		return "", "", false
	}
	return parts[0], parts[1], true
}

// assignableError 判断错误类型 from 能否赋给外层 E2（§10.2）。
func assignableError(from, to string) bool {
	if from == "" || to == "" || from == to {
		return true
	}
	if assignable(texpr{key: from}, to) {
		return true
	}
	if to == "Any" {
		return true
	}
	if to == "Object" && (isRefType(from) || from == "Any") {
		return true
	}
	return false
}

// checkResultType 校验类型位置上的 Result 形状：两个实参、E != void。
func (e *tyenv) checkResultType(t xfront.TypeRef, p xfront.Pos) {
	switch ty := t.(type) {
	case nil:
		return
	case *xfront.NamedType:
		name := ty.Qual[len(ty.Qual)-1]
		if name == "Result" {
			if len(ty.Args) == 0 {
				return // 裸 Result 按 Result<Any,Any>
			}
			if len(ty.Args) != 2 {
				e.errf(ty.P, ErResultCtor, "Result 需要恰好两个类型实参 Result<T,E>（§10.1）", "补全成功值类型与错误类型")
			}
			for _, a := range ty.Args {
				e.checkResultType(a, ty.P)
			}
			if len(ty.Args) == 2 && typeKey(ty.Args[1]) == "void" {
				e.errf(ty.P, ErResultCtor, "Result 的错误类型 E 不能是 void（§10.1）", "换用具体错误类型；只有 T 可以是 void")
			}
			if len(ty.Args) == 2 && strings.HasPrefix(typeKey(ty.Args[1]), "Result<") {
				e.errf(ty.P, ErResultCtor, "Result 的错误类型 E 不能是 Result（S4 §2.1：禁止嵌套）", "换用枚举/结构体/类错误类型")
			}
			return
		}
		for _, a := range ty.Args {
			e.checkResultType(a, ty.P)
		}
	case *xfront.SuffixedType:
		e.checkResultType(ty.Base, ty.P)
	case *xfront.FuncTypeRef:
		e.checkResultType(ty.Ret, ty.P)
		for _, a := range ty.Params {
			e.checkResultType(a, ty.P)
		}
	case *xfront.TupleTypeRef:
		for _, a := range ty.Elems {
			e.checkResultType(a, ty.P)
		}
	}
}

// inferExpected 按目标类型推断表达式；只对 Result 构造/容器/闭包做目标导向检查。
func (e *tyenv) inferExpected(x xfront.Expr, want string) texpr {
	switch n := x.(type) {
	case *xfront.Call:
		if id, ok := n.Callee.(*xfront.IdentExpr); ok && (id.Name == "Ok" || id.Name == "Err") {
			return e.inferResultCtor(n, id.Name, want)
		}
	case *xfront.Unary:
		if n.Op == "try" {
			return e.infer(n)
		}
	case *xfront.Lambda:
		if ret, params, ok := funcTypeParts(want); ok {
			e.checkLambda(n, ret, params)
			return texpr{key: want}
		}
	case *xfront.ArrayLit:
		if elem, ok := elemWanted(want); ok {
			for _, el := range n.Elems {
				at := e.inferExpected(el, elem)
				if !assignable(at, elem) {
					e.errf(el.Pos(), TyAssignability,
						"容器元素类型 "+describeKey(at)+" 不能赋给目标元素类型 "+elem+"（§2.6）", hintFor(at, elem))
				}
			}
			return texpr{key: want}
		}
	case *xfront.MapLit:
		if k, v, ok := mapWanted(want); ok {
			for i := range n.Keys {
				kt := e.inferExpected(n.Keys[i], k)
				if !assignable(kt, k) {
					e.errf(n.Keys[i].Pos(), TyAssignability, "Map 键类型 "+describeKey(kt)+" 不能赋给 "+k+"（§2.6）", hintFor(kt, k))
				}
				vt := e.inferExpected(n.Vals[i], v)
				if !assignable(vt, v) {
					e.errf(n.Vals[i].Pos(), TyAssignability, "Map 值类型 "+describeKey(vt)+" 不能赋给 "+v+"（§2.6）", hintFor(vt, v))
				}
			}
			return texpr{key: want}
		}
	case *xfront.Ternary:
		if want != "" {
			e.checkCond(n.Cond)
			e.inferExpected(n.Then, want)
			e.inferExpected(n.Else, want)
			return texpr{key: want}
		}
	}
	return e.infer(x)
}

// inferResultCtor 按目标类型检查 Ok/Err 构造（§10.1）。
func (e *tyenv) inferResultCtor(n *xfront.Call, kind, want string) texpr {
	t, en, ok := resultArgs(want)
	if !ok || t == "" || en == "" {
		if kind == "Ok" {
			if len(n.Args) > 1 {
				e.errf(n.P, ErResultCtor, "Ok 最多接受 1 个成功值（§10.1）", "")
			}
		} else if len(n.Args) != 1 {
			e.errf(n.P, ErResultCtor, "Err 必须且只能接受 1 个错误值（§10.1）", "")
		}
		for _, a := range n.Args {
			e.infer(a)
		}
		if !e.quietCtor {
			e.errf(n.P, ErResultCtor,
				"无法推断 Result 的另一侧类型：Ok/Err 需要目标类型或显式类型（§10.1）",
				"写成 Result<T,E> 目标类型，或使用类型注解")
		}
		return texpr{key: "Result<,>"}
	}
	if kind == "Ok" {
		switch len(n.Args) {
		case 0:
			if t != "void" {
				e.errf(n.P, ErResultCtor, "Result<"+t+","+en+"> 的 T 不是 void，Ok() 必须带成功值（§10.1）", "写 Ok(value)")
			}
		case 1:
			if t == "void" {
				e.errf(n.P, ErResultCtor, "Result<void,E> 的 Ok 不能带成功值（§10.1）", "写 Ok()")
				e.infer(n.Args[0])
			} else {
				at := e.inferExpected(n.Args[0], t)
				if !assignable(at, t) {
					e.errf(n.Args[0].Pos(), ErResultCtor,
						"Ok 成功值类型 "+describeKey(at)+" 不能赋给 T="+t+"（§10.1）", hintFor(at, t))
				}
			}
		default:
			e.errf(n.P, ErResultCtor, "Ok 最多接受 1 个成功值（§10.1）", "")
			for _, a := range n.Args {
				e.infer(a)
			}
		}
		return texpr{key: want}
	}
	// Err
	if len(n.Args) != 1 {
		e.errf(n.P, ErResultCtor, "Err 必须且只能接受 1 个错误值（§10.1）", "E 不能是 void")
		for _, a := range n.Args {
			e.infer(a)
		}
		return texpr{key: want}
	}
	at := e.inferExpected(n.Args[0], en)
	if !assignable(at, en) {
		e.errf(n.Args[0].Pos(), ErResultCtor,
			"Err 错误值类型 "+describeKey(at)+" 不能赋给 E="+en+"（§10.1）", hintFor(at, en))
	}
	return texpr{key: want}
}

// resultMember 检查 Result 成员调用（§10.1）。
func (e *tyenv) resultMember(rt texpr, mem *xfront.Member, args []xfront.Expr, p xfront.Pos) texpr {
	t, en, ok := resultArgs(rt.key)
	if !ok || t == "" || en == "" {
		e.errf(p, ErResultCtor, "Result 类型实参不完整：需要 Result<T,E>（§10.1）", "")
		for _, a := range args {
			e.infer(a)
		}
		return texpr{}
	}
	switch mem.Name {
	case "isOk", "isErr":
		if len(args) != 0 {
			e.errf(p, ErResultMember, mem.Name+"() 不接受参数（§10.1）", "去掉实参")
		}
		for _, a := range args {
			e.infer(a)
		}
		return texpr{key: "Bool"}
	case "value":
		if t == "void" {
			e.errf(p, ErResultMember, "Result<void,E> 没有 value()（§10.1）", "用 isOk()/isErr() 检查")
		}
		if len(args) != 0 {
			e.errf(p, ErResultMember, "value() 不接受参数（§10.1）", "去掉实参")
		}
		for _, a := range args {
			e.infer(a)
		}
		if t == "void" {
			return texpr{}
		}
		return texpr{key: t}
	case "error":
		if en == "void" {
			e.errf(p, ErResultMember, "Result<T,void> 没有 error()（§10.1）", "E 不能是 void")
		}
		if len(args) != 0 {
			e.errf(p, ErResultMember, "error() 不接受参数（§10.1）", "去掉实参")
		}
		for _, a := range args {
			e.infer(a)
		}
		if en == "void" {
			return texpr{}
		}
		return texpr{key: en}
	case "unwrapOr":
		if t == "void" {
			e.errf(p, ErResultMember, "Result<void,E> 没有 unwrapOr()（§10.1）", "")
		}
		if len(args) != 1 {
			e.errf(p, ErResultMember, "unwrapOr() 恰好接受 1 个参数（§10.1）", "写 unwrapOr(fallback)")
			for _, a := range args {
				e.infer(a)
			}
			return texpr{}
		}
		at := e.inferExpected(args[0], t)
		if t != "void" && !assignable(at, t) {
			e.errf(args[0].Pos(), ErResultMember,
				"unwrapOr 参数类型 "+describeKey(at)+" 不能赋给 T="+t+"（§10.1）", hintFor(at, t))
		}
		if t == "void" {
			return texpr{}
		}
		return texpr{key: t}
	default:
		e.errf(p, ErResultMember, "未知的 Result 成员 `"+mem.Name+"`（§10.1）", "可用：isOk/isErr/value/error/unwrapOr")
		for _, a := range args {
			e.infer(a)
		}
		return texpr{}
	}
}

// checkLambda 按目标函数类型检查闭包体（§10.2：闭包内 try 的目标返回类型必须是 Result）。
func (e *tyenv) checkLambda(n *xfront.Lambda, ret string, params []string) {
	savedVars, savedRet, savedKind, savedCleanup := e.vars, e.ret, e.fnKind, e.inCleanup
	inner := map[string]string{}
	for k, v := range savedVars {
		inner[k] = v
	}
	e.vars, e.ret, e.fnKind, e.inCleanup = inner, ret, "lambda", false
	if params != nil && len(n.Params) != len(params) {
		e.errf(n.P, TyAssignability, "闭包参数数量与目标函数类型不一致（§2.6）", "")
	}
	for i, p := range n.Params {
		e.checkResultType(p.Type, p.P)
		tk := typeKey(p.Type)
		if i < len(params) && params[i] != "" && tk != "" && tk != params[i] {
			e.errf(p.P, TyAssignability, "闭包参数类型 "+tk+" 与目标函数类型参数 "+params[i]+" 不一致（§2.6）", "")
		}
		e.vars[p.Name] = tk
	}
	if n.Block != nil {
		e.walkFunc(n.Block, ret)
	} else if n.ExprB != nil {
		at := e.inferExpected(n.ExprB, ret)
		if ret != "" && ret != "void" && !assignable(at, ret) {
			e.errf(n.ExprB.Pos(), assignDiag(at, ret),
				"闭包返回值类型 "+describeKey(at)+" 不能赋给目标返回类型 "+ret+"（§2.6）", hintFor(at, ret))
		}
	}
	e.vars, e.ret, e.fnKind, e.inCleanup = savedVars, savedRet, savedKind, savedCleanup
}

// checkCleanup 检查 defer/errdefer 清理体限制（§10.3）。
func (e *tyenv) checkCleanup(d *xfront.DeferStmt) {
	if d.Block != nil {
		for _, st := range d.Block.Stmts {
			e.scanCleanupStmt(st)
		}
		return
	}
	if d.Stmt != nil {
		if ld, ok := d.Stmt.(*xfront.LocalDeclStmt); ok {
			// LocalDeclStmt.P 是零位置；优先用类型节点定位（`defer Int x = 1` 指向 Int），
			// 类型缺失时回退到 defer/errdefer 关键字位置，保证诊断永不为 0:0。
			p := d.P
			if ld.Type != nil {
				if tp := ld.Type.Pos(); tp.Line != 0 {
					p = tp
				}
			}
			e.errf(p, ErCleanupBody,
				"defer/errdefer 的单条语句体不得是局部声明（§10.3）", "需要局部变量时改用花括号体")
		}
		e.scanCleanupStmt(d.Stmt)
	}
}

// scanCleanupStmt 递归扫描清理体中的禁用构造。
func (e *tyenv) scanCleanupStmt(st xfront.Stmt) {
	switch n := st.(type) {
	case nil:
		return
	case *xfront.ReturnStmt:
		e.errf(n.P, ErCleanupBody, "清理体不得包含 return（§10.3）", "清理必须非控制转移")
		e.scanCleanupExpr(n.Value)
	case *xfront.BreakStmt:
		e.errf(n.P, ErCleanupBody, "清理体不得包含 break（§10.3）", "清理必须非控制转移")
	case *xfront.ContinueStmt:
		e.errf(n.P, ErCleanupBody, "清理体不得包含 continue（§10.3）", "清理必须非控制转移")
	case *xfront.GotoStmt:
		e.errf(n.P, ErCleanupBody, "清理体不得包含 goto（§10.3）", "清理必须非控制转移")
	case *xfront.ThrowStmt:
		e.errf(n.P, ErCleanupBody, "清理体不得包含 throw（§10.3）", "清理必须非抛出")
		e.scanCleanupExpr(n.Value)
	case *xfront.DeferStmt:
		e.errf(n.P, ErCleanupBody, "清理体不得嵌套 defer/errdefer（§10.3）", "")
	case *xfront.ExprStmt:
		e.scanCleanupExpr(n.X)
	case *xfront.LocalDeclStmt:
		e.scanCleanupExpr(n.Init)
	case *xfront.AssignStmt:
		e.scanCleanupExpr(n.Target)
		e.scanCleanupExpr(n.Value)
	case *xfront.IncDecStmt:
		e.scanCleanupExpr(n.Target)
	case *xfront.IfStmt:
		e.scanCleanupExpr(n.Cond)
		e.scanCleanupBlock(n.Then)
		if eb, ok := n.Else.(*xfront.Block); ok {
			e.scanCleanupBlock(eb)
		} else if n.Else != nil {
			e.scanCleanupStmt(n.Else)
		}
	case *xfront.WhileStmt:
		e.scanCleanupExpr(n.Cond)
		e.scanCleanupBlock(n.Body)
	case *xfront.DoWhileStmt:
		e.scanCleanupBlock(n.Body)
		e.scanCleanupExpr(n.Cond)
	case *xfront.ForStmt:
		e.scanCleanupExpr(n.Src)
		e.scanCleanupBlock(n.Body)
	case *xfront.SwitchStmt:
		e.scanCleanupExpr(n.Value)
		for _, c := range n.Cases {
			e.scanCleanupExpr(c.Expr)
			for _, s := range c.Stmts {
				e.scanCleanupStmt(s)
			}
		}
		if n.Default != nil {
			for _, s := range n.Default.Stmts {
				e.scanCleanupStmt(s)
			}
		}
	case *xfront.LabeledStmt:
		e.scanCleanupStmt(n.Stmt)
	case *xfront.Block:
		e.scanCleanupBlock(n)
	}
}

func (e *tyenv) scanCleanupBlock(b *xfront.Block) {
	if b == nil {
		return
	}
	for _, st := range b.Stmts {
		e.scanCleanupStmt(st)
	}
}

// scanCleanupExpr 扫描清理体表达式中的 try 与闭包分配（§10.3）。
func (e *tyenv) scanCleanupExpr(x xfront.Expr) {
	switch n := x.(type) {
	case nil:
		return
	case *xfront.Unary:
		if n.Op == "try" {
			e.errf(n.P, ErCleanupBody, "清理体不得包含 try（§10.3）", "清理必须非抛出")
		}
		e.scanCleanupExpr(n.X)
	case *xfront.Lambda:
		e.errf(n.P, ErCleanupBody, "清理体不得分配闭包（§10.3）", "把清理逻辑写成具名函数")
	case *xfront.Paren:
		e.scanCleanupExpr(n.X)
	case *xfront.Binary:
		e.scanCleanupExpr(n.L)
		e.scanCleanupExpr(n.R)
	case *xfront.Ternary:
		e.scanCleanupExpr(n.Cond)
		e.scanCleanupExpr(n.Then)
		e.scanCleanupExpr(n.Else)
	case *xfront.StrLitExpr:
		for _, p := range n.Parts {
			e.scanCleanupExpr(p.Expr)
		}
	case *xfront.Call:
		e.scanCleanupExpr(n.Callee)
		for _, a := range n.Args {
			e.scanCleanupExpr(a)
		}
	case *xfront.Member:
		e.scanCleanupExpr(n.X)
	case *xfront.TupleMember:
		e.scanCleanupExpr(n.X)
	case *xfront.Index:
		e.scanCleanupExpr(n.X)
		e.scanCleanupExpr(n.Idx)
	case *xfront.Tuple:
		for _, el := range n.Elems {
			e.scanCleanupExpr(el)
		}
	case *xfront.ArrayLit:
		for _, el := range n.Elems {
			e.scanCleanupExpr(el)
		}
	case *xfront.MapLit:
		for i := range n.Keys {
			e.scanCleanupExpr(n.Keys[i])
			e.scanCleanupExpr(n.Vals[i])
		}
	case *xfront.New:
		for _, a := range n.Args {
			e.scanCleanupExpr(a)
		}
	case *xfront.NewArray:
		e.scanCleanupExpr(n.Count)
	}
}
