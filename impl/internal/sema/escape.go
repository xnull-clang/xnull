package sema

import "xnull.dev/xnull/internal/xfront"

// ---------- S3-03：对象创建点逃逸分类（§6） ----------
//
// 分类口径（供 E4 栈发射 / E5 内存消费）：
//   none  对象不离开当前函数栈帧，可栈分配；
//   return 对象作为返回值离开当前函数，走 ARC；
//   other 存入字段/容器/参数传递/闭包捕获/策略非 ARC，走堆或 GC。
//
// 类型级前置（StackEligible/Deinit/SelfCaptured/RefCycle/Policy）不满足时一律 other。

type EscapeInfo struct {
	Class  string `json:"class"`
	Func   string `json:"func"`
	Escape string `json:"escape"` // none/return/other
	Reason string `json:"reason"`
	Line   int    `json:"line"`
	Col    int    `json:"col"`
}

// Escapes 返回编译单元内全部 `new` 创建点的逃逸分类，按源码位置排序（确定性）。
func (r *Result) Escapes(u *xfront.CompilationUnit) []EscapeInfo {
	w := &escapeWalker{a: r.a, out: []EscapeInfo{}}
	w.strats = map[string]Strategy{}
	for _, s := range r.a.ComputeStrategies(u) {
		w.strats[s.Decl] = s
	}
	for _, d := range u.Decls {
		switch n := d.(type) {
		case *xfront.TopFunc:
			w.fn = n.Name
			w.walkStmt(n.Body, "stmt", false)
		case *xfront.TopField:
			w.fn = "<global>"
			w.walkExpr(n.Init, "other", false)
		case *xfront.ClassDecl:
			for _, f := range n.Fields {
				w.fn = n.Name + "." + f.Name
				w.walkExpr(f.Init, "other", false)
			}
			for _, m := range n.Methods {
				w.fn = n.Name + "." + m.Name
				w.walkStmt(m.Body, "stmt", false)
			}
			for _, c := range n.Ctors {
				w.fn = n.Name + ".<ctor>"
				w.walkStmt(c.Body, "stmt", false)
			}
		}
	}
	return w.out
}

type escapeWalker struct {
	a      *analyzer
	strats map[string]Strategy
	fn     string
	out    []EscapeInfo
}

func (w *escapeWalker) add(class, escape, reason string, e xfront.Expr) {
	p := e.Pos()
	w.out = append(w.out, EscapeInfo{Class: class, Func: w.fn, Escape: escape, Reason: reason, Line: p.Line, Col: p.Col})
}

func (w *escapeWalker) walkStmt(s xfront.Stmt, ctx string, inLambda bool) {
	if s == nil {
		return
	}
	switch n := s.(type) {
	case *xfront.AssignStmt:
		c := "other"
		if _, ok := n.Target.(*xfront.IdentExpr); ok {
			c = "local"
		}
		w.walkExpr(n.Value, c, inLambda)
		w.walkExpr(n.Target, "other", inLambda)
	case *xfront.LocalDeclStmt:
		w.walkExpr(n.Init, "local", inLambda)
	case *xfront.ReturnStmt:
		w.walkExpr(n.Value, "return", inLambda)
	case *xfront.ThrowStmt:
		w.walkExpr(n.Value, "other", inLambda)
	case *xfront.ExprStmt:
		w.walkExpr(n.X, "other", inLambda)
	case *xfront.Block:
		for _, x := range n.Stmts {
			w.walkStmt(x, ctx, inLambda)
		}
	case *xfront.IfStmt:
		w.walkExpr(n.Cond, "other", inLambda)
		w.walkStmt(n.Then, "stmt", inLambda)
		w.walkStmt(n.Else, "stmt", inLambda)
	case *xfront.WhileStmt:
		w.walkExpr(n.Cond, "other", inLambda)
		w.walkStmt(n.Body, "stmt", inLambda)
	case *xfront.DoWhileStmt:
		w.walkStmt(n.Body, "stmt", inLambda)
		w.walkExpr(n.Cond, "other", inLambda)
	case *xfront.ForStmt:
		w.walkExpr(n.Src, "other", inLambda)
		w.walkStmt(n.Body, "stmt", inLambda)
	case *xfront.SwitchStmt:
		w.walkExpr(n.Value, "other", inLambda)
		for _, c := range n.Cases {
			w.walkExpr(c.Expr, "other", inLambda)
			for _, x := range c.Stmts {
				w.walkStmt(x, "stmt", inLambda)
			}
		}
		if n.Default != nil {
			for _, x := range n.Default.Stmts {
				w.walkStmt(x, "stmt", inLambda)
			}
		}
	case *xfront.DeferStmt:
		w.walkStmt(n.Block, "other", inLambda)
		w.walkStmt(n.Stmt, "other", inLambda)
	case *xfront.LabeledStmt:
		w.walkStmt(n.Stmt, ctx, inLambda)
	}
}

func (w *escapeWalker) walkExpr(e xfront.Expr, ctx string, inLambda bool) {
	if e == nil {
		return
	}
	switch n := e.(type) {
	case *xfront.New:
		w.classifyNew(n, ctx, inLambda)
		for _, a := range n.Args {
			w.walkExpr(a, "other", inLambda)
		}
	case *xfront.Paren:
		w.walkExpr(n.X, ctx, inLambda)
	case *xfront.Unary:
		w.walkExpr(n.X, ctx, inLambda)
	case *xfront.Binary:
		w.walkExpr(n.L, "other", inLambda)
		w.walkExpr(n.R, "other", inLambda)
	case *xfront.Ternary:
		w.walkExpr(n.Cond, "other", inLambda)
		w.walkExpr(n.Then, ctx, inLambda)
		w.walkExpr(n.Else, ctx, inLambda)
	case *xfront.Call:
		w.walkExpr(n.Callee, "other", inLambda)
		for _, a := range n.Args {
			w.walkExpr(a, "other", inLambda)
		}
	case *xfront.Member:
		w.walkExpr(n.X, "other", inLambda)
	case *xfront.TupleMember:
		w.walkExpr(n.X, "other", inLambda)
	case *xfront.Index:
		w.walkExpr(n.X, "other", inLambda)
		w.walkExpr(n.Idx, "other", inLambda)
	case *xfront.Tuple:
		for _, el := range n.Elems {
			w.walkExpr(el, "other", inLambda)
		}
	case *xfront.ArrayLit:
		for _, el := range n.Elems {
			w.walkExpr(el, "other", inLambda)
		}
	case *xfront.MapLit:
		for i := range n.Keys {
			w.walkExpr(n.Keys[i], "other", inLambda)
			w.walkExpr(n.Vals[i], "other", inLambda)
		}
	case *xfront.NewArray:
		w.walkExpr(n.Count, "other", inLambda)
	case *xfront.Lambda:
		if n.Block != nil {
			w.walkStmt(n.Block, "stmt", true)
		}
		w.walkExpr(n.ExprB, "other", true)
	case *xfront.StrLitExpr:
		for _, p := range n.Parts {
			if p.Expr != nil {
				w.walkExpr(p.Expr, "other", inLambda)
			}
		}
	}
}

func (w *escapeWalker) classifyNew(n *xfront.New, ctx string, inLambda bool) {
	nt, ok := n.Type.(*xfront.NamedType)
	if !ok || len(nt.Qual) != 1 {
		return
	}
	name := nt.Qual[0]
	st, ok := w.strats[name]
	if !ok || st.Kind != "class" {
		return
	}
	if st.Policy != "arc" || !st.StackEligible || st.Deinit || st.SelfCaptured || st.RefCycle {
		w.add(name, "other", "类型策略非栈候选（policy/deinit/capture/cycle）", n)
		return
	}
	if inLambda {
		w.add(name, "other", "闭包捕获", n)
		return
	}
	switch ctx {
	case "local":
		w.add(name, "none", "局部变量持有", n)
	case "return":
		w.add(name, "return", "作为返回值离开函数", n)
	default:
		w.add(name, "other", "存入字段/容器/参数传递", n)
	}
}
