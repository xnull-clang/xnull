// Package sema 是语义分析切片（M2）的入口。
//
// 子切片依赖顺序（详见 docs/m2-sema-plan.md）：
//   - M2-A 名称解析（S1 §3.3/§3.4/§3.5）——本文件，首批已交付；
//   - M2-B 确定赋值（S1 §5.3）——依赖名称解析；
//   - M2-C 类型检查（S1 §2.6）——依赖名称解析。
//
// 诊断码段位：RES-1xx（名称解析）。语法诊断（SYN-1xx/LEX-1xx）由 xfront 产生，
// sema 只追加语义诊断；两者都返回后工具链统一打印。
package sema

import (
	"xnull.dev/xnull/internal/diag"
	"xnull.dev/xnull/internal/xfront"
)

// 诊断码（名称解析段位）。
const (
	ResUndefined = "RES-101" // 未定义的名称（四级顺序解析后仍不可见，§3.3）
	ResRedecl    = "RES-102" // 同一作用域重复声明
)

// visibleBuiltins 是不经 §3.3 四级解析、直接可见的名称：
// 解释器内置函数（impl/README：print、str）与语言构造器（S1 §10.1：Ok、Err）。
var visibleBuiltins = map[string]bool{"print": true, "str": true, "Ok": true, "Err": true}

// analyzer 保存一次分析的上下文。
type analyzer struct {
	file      string
	diags     []diag.Diagnostic
	tops      map[string]bool // 当前包顶层声明名（函数/字段，§3.3 第 2 级）
	hasImp    bool            // 文件是否有 import
	imported  map[string]bool // 导入可见的简单名（§3.2/§3.5）
	ambiguous map[string]bool // 未消歧的简单名（使用时报 RES-104）
	tc        *typeCheckCtx   // 类型声明上下文（类字段访问检查用）
	seenTop   map[string]bool // 顶层重复声明检测
}

// Analyze 对编译单元做名称解析分析，返回语义诊断（不修改 AST）。
// 当前覆盖：§3.3 第 1/2 级（局部、当前包顶层）、遮蔽合法性、重复声明、
// 赋值目标可解析、顶层前向引用放行（§3.4）。
// 第 3 级（导入符号）与第 4 级（完全限定名）在包符号表切片接入——
// 含 import 的文件本轮跳过"未定义名称"诊断，避免误报。
func Analyze(file string, u *xfront.CompilationUnit) []diag.Diagnostic {
	_, diags := AnalyzeWith(file, u)
	return diags
}

// Result 是语义分析产物（供策略判定等后续遍消费）。
type Result struct{ a *analyzer }

// Strategies 返回内存策略判定（S2 §15.1；按声明名排序，确定性）。
func (r *Result) Strategies(u *xfront.CompilationUnit) []Strategy { return r.a.ComputeStrategies(u) }

// AnalyzeWith 执行语义分析并返回结果句柄。
func AnalyzeWith(file string, u *xfront.CompilationUnit) (*Result, []diag.Diagnostic) {
	a := &analyzer{file: file, tops: map[string]bool{}, seenTop: map[string]bool{},
		imported: map[string]bool{}, ambiguous: map[string]bool{}}
	a.analyzeImports(u)
	a.checkTypeDecls(u)
	for _, d := range u.Decls {
		switch n := d.(type) {
		case *xfront.TopFunc:
			a.collectTop(n.Name, n.P)
			for _, p := range n.Params {
				a.collectTopParam(p.Name)
			}
		case *xfront.TopField:
			a.collectTop(n.Name, n.P)
		}
	}
	for _, d := range u.Decls {
		if fn, ok := d.(*xfront.TopFunc); ok {
			sc := &nscope{parent: nil}
			for _, p := range fn.Params {
				sc.define(p.Name)
			}
			a.walkBlock(fn.Body, sc)
		}
	}
	// M2-B：确定赋值与返回路径（§5.3、§6.1）——名称解析之后。
	for _, d := range u.Decls {
		if fn, ok := d.(*xfront.TopFunc); ok {
			a.analyzeAssign(file, fn)
		}
	}
	// M2-C：类型检查（§2.6/§2.10/§6.1）——最后（依赖前两遍的环境）。
	a.analyzeTypes(file, u)
	return &Result{a: a}, a.diags
}

func (a *analyzer) collectTop(name string, p xfront.Pos) {
	if name == "" || name == "<err>" {
		return
	}
	if a.seenTop[name] {
		// 顶层函数允许重载（§4.4，同名不同参）；同名字段与函数的冲突在类型检查切片判定，
		// 此处不报，避免把合法重载误伤。
		return
	}
	a.seenTop[name] = true
	a.tops[name] = true
}

func (a *analyzer) collectTopParam(string) {} // 参数不进顶层名字空间

func (a *analyzer) errf(p xfront.Pos, code, msg, hint string) {
	a.diags = append(a.diags, diag.Diagnostic{
		File: a.file, Line: p.Line, Col: p.Col, Code: code, Message: msg, Hint: hint,
	})
}

// nscope 是名称解析作用域（§3.3 第 1 级：局部变量、参数、类型参数）。
type nscope struct {
	parent *nscope
	names  map[string]bool
}

func (s *nscope) define(name string) {
	if s.names == nil {
		s.names = map[string]bool{}
	}
	s.names[name] = true
}

func (s *nscope) declared(name string) bool {
	for c := s; c != nil; c = c.parent {
		if c.names[name] {
			return true
		}
	}
	return false
}

// declaredHere 只查当前作用域层（重复声明检测用）。
func (s *nscope) declaredHere(name string) bool { return s.names[name] }

func (a *analyzer) walkBlock(b *xfront.Block, sc *nscope) {
	if b == nil {
		return
	}
	for _, st := range b.Stmts {
		a.walkStmt(st, sc)
	}
}

func (a *analyzer) walkStmt(st xfront.Stmt, sc *nscope) {
	switch n := st.(type) {
	case *xfront.LocalDeclStmt:
		a.checkTypeXdkUse(n.Type)
		if n.Init != nil {
			a.walkExpr(n.Init, sc)
		}
		if sc.declaredHere(n.Name) { // 同一作用域重复声明
			a.errf(n.P, ResRedecl, "名称 `"+n.Name+"` 在同一作用域重复声明", "遮蔽需要进入新作用域（块）；改名或删除多余声明")
		}
		sc.define(n.Name)
	case *xfront.AssignStmt:
		a.walkExpr(n.Value, sc)
		if id, ok := n.Target.(*xfront.IdentExpr); ok {
			if !sc.declared(id.Name) && !a.tops[id.Name] && !a.hasImp {
				a.errf(n.P, ResUndefined, "未定义的名称 `"+id.Name+"`（§3.3 四级顺序解析后不可见）", "声明后再赋值；或检查拼写")
			}
		}
		// 成员/下标赋值目标在类型检查切片处理
	case *xfront.IncDecStmt:
		if id, ok := n.Target.(*xfront.IdentExpr); ok {
			if !sc.declared(id.Name) && !a.tops[id.Name] && !a.hasImp {
				a.errf(n.P, ResUndefined, "未定义的名称 `"+id.Name+"`", "自增/自减的目标必须是已声明的变量")
			}
		}
	case *xfront.ExprStmt:
		a.walkExpr(n.X, sc)
	case *xfront.ReturnStmt:
		if n.Value != nil {
			a.walkExpr(n.Value, sc)
		}
	case *xfront.ThrowStmt:
		a.walkExpr(n.Value, sc)
	case *xfront.IfStmt:
		a.walkExpr(n.Cond, sc)
		a.walkBlock(n.Then, &nscope{parent: sc})
		if n.Else != nil {
			if eb, ok := n.Else.(*xfront.Block); ok {
				a.walkBlock(eb, &nscope{parent: sc})
			} else {
				a.walkStmt(n.Else, sc)
			}
		}
	case *xfront.WhileStmt:
		a.walkExpr(n.Cond, sc)
		a.walkBlock(n.Body, &nscope{parent: sc})
	case *xfront.DoWhileStmt:
		a.walkBlock(n.Body, &nscope{parent: sc})
		a.walkExpr(n.Cond, sc)
	case *xfront.ForStmt:
		a.walkExpr(n.Src, sc)
		inner := &nscope{parent: sc}
		inner.define(n.Var) // 循环变量在体作用域（§6.7）
		a.walkBlock(n.Body, inner)
	case *xfront.SwitchStmt:
		a.walkExpr(n.Value, sc)
		for _, c := range n.Cases { // 每个 case 是独立作用域（§6.8）
			inner := &nscope{parent: sc}
			if c.Expr != nil {
				a.walkExpr(c.Expr, sc)
			}
			a.walkBlock(&xfront.Block{P: n.P, Stmts: c.Stmts}, inner)
		}
	case *xfront.DeferStmt:
		inner := &nscope{parent: sc}
		if n.Block != nil {
			a.walkBlock(n.Block, inner)
		} else if n.Stmt != nil {
			a.walkStmt(n.Stmt, inner)
		}
	case *xfront.LabeledStmt:
		if n.Stmt != nil {
			a.walkStmt(n.Stmt, sc)
		}
	case *xfront.Block:
		a.walkBlock(n, &nscope{parent: sc})
	case *xfront.BreakStmt, *xfront.ContinueStmt, *xfront.GotoStmt, *xfront.EmptyStmt:
	}
}

func (a *analyzer) walkExpr(e xfront.Expr, sc *nscope) {
	switch n := e.(type) {
	case *xfront.IdentExpr:
		// true/false 是关键字面量，不进入名称解析
		if n.Name == "true" || n.Name == "false" {
			return
		}
		if !sc.declared(n.Name) && !a.tops[n.Name] && !visibleBuiltins[n.Name] && !a.imported[n.Name] {
			a.checkXdkUse(n.P, n.Name)
			if !xdkSymbolKnown(n.Name) {
				a.errf(n.P, ResUndefined, "未定义的名称 `"+n.Name+"`（§3.3 四级顺序解析后不可见）", "局部/参数/顶层声明、导入符号或完全限定名之一")
			}
		}
	case *xfront.Paren:
		a.walkExpr(n.X, sc)
	case *xfront.Unary:
		a.walkExpr(n.X, sc)
	case *xfront.Binary:
		a.walkExpr(n.L, sc)
		a.walkExpr(n.R, sc)
	case *xfront.Ternary:
		a.walkExpr(n.Cond, sc)
		a.walkExpr(n.Then, sc)
		a.walkExpr(n.Else, sc)
	case *xfront.StrLitExpr:
		for _, p := range n.Parts {
			if p.Expr != nil {
				a.walkExpr(p.Expr, sc)
			}
		}
	case *xfront.Call:
		a.walkExpr(n.Callee, sc)
		for _, arg := range n.Args {
			a.walkExpr(arg, sc)
		}
	case *xfront.Member:
		a.walkExpr(n.X, sc) // 成员名在类型检查切片解析（S2 §5.8）
	case *xfront.TupleMember:
		a.walkExpr(n.X, sc)
	case *xfront.Index:
		a.walkExpr(n.X, sc)
		a.walkExpr(n.Idx, sc)
	case *xfront.Tuple:
		for _, el := range n.Elems {
			a.walkExpr(el, sc)
		}
	case *xfront.ArrayLit:
		for _, el := range n.Elems {
			a.walkExpr(el, sc)
		}
	case *xfront.MapLit:
		for i := range n.Keys {
			a.walkExpr(n.Keys[i], sc)
			a.walkExpr(n.Vals[i], sc)
		}
	case *xfront.New:
		for _, arg := range n.Args {
			a.walkExpr(arg, sc)
		}
	case *xfront.NewArray:
		a.walkExpr(n.Count, sc)
	case *xfront.Lambda:
		inner := &nscope{parent: sc}
		for _, p := range n.Params {
			inner.define(p.Name)
		}
		if n.Block != nil {
			a.walkBlock(n.Block, inner)
		} else if n.ExprB != nil {
			a.walkExpr(n.ExprB, inner)
		}
	case *xfront.IntLitExpr, *xfront.FloatLitExpr, *xfront.CharLitExpr, *xfront.BoolLit, *xfront.NullLit:
	}
}
