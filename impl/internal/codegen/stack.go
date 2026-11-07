// stack.go：逃逸分类消费与栈对象发射（S3-03 / MEM-05）。
//
// sema 的 Strategy.Escape 给出类级候选（none/return/other）：
//   - none   ：局部构造点优先栈分配（不经分配器、无 ARC/GC 记账）；
//   - return ：ARC 堆分配（本文件的栈对象在发布位置退回堆）；
//   - other  ：GC 堆分配（E5/BND-10 路径）。
//
// 栈对象是当前帧内的 C 结构体值（随块消亡），没有分配器调用；对象身份仍是
// 指针身份（&slot），与堆对象一致。为保证语义不变，若局部在函数体内被发布
// （作为实参、返回值、赋值右值/左值、别名初始化等），该局部退回堆分配。
package codegen

import (
	"fmt"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

// localEscaped 判断局部是否处于逃逸位置（当前函数体预扫描结果）。
func (s *scope) localEscaped(name string) bool {
	return s.g.curEscaped != nil && s.g.curEscaped[name]
}

// emitStackNew 为 `T name = new T(args)` 发射栈对象：零初始化槽 + 构造器初始化
// + 指针局部。构造器初始化函数与堆路径共用（字段初值/参数绑定/构造器体）。
func (s *scope) emitStackNew(nw *xfront.New, tc, name string) ([]string, error) {
	ci, ok := s.g.classOfC(tc)
	if !ok {
		return nil, fmt.Errorf("codegen：栈分配的类类型 %s 不可判定（S3-03）", tc)
	}
	var ctor *xfront.CtorDecl
	if len(nw.Args) > 0 {
		ctor = ci.ctorByArity(len(nw.Args))
		if ctor == nil {
			return nil, fmt.Errorf("codegen：类 %s 没有 %d 个参数的构造器（S2 §6.3）", ci.decl.Name, len(nw.Args))
		}
	}
	args, err := s.callArgs(nw.Args)
	if err != nil {
		return nil, err
	}
	lines := append([]string{}, s.pending...)
	s.pending = nil
	slot := s.tmp()
	out := lines
	// 栈槽：零值（无分配头/无 ARC 计数），随后由 init 函数执行字段初值与构造器体。
	out = append(out, ci.cname+" "+slot+";")
	out = append(out, fmt.Sprintf("memset((char *)&%s, 0, sizeof(%s));", slot, ci.cname))
	if ci.vptr {
		out = append(out, slot+".__vtable = xn_vt_"+ci.decl.Name+";")
	}
	call := ci.initFnName(ctor) + "(&" + slot
	if len(args) > 0 {
		call += ", " + strings.Join(args, ", ")
	}
	call += ");"
	out = append(out, call)
	out = append(out, tc+" "+name+" = &"+slot+";")
	return out, nil
}

// escapeIdents 预扫描函数体，收集处于「逃逸位置」的标识符（S3-03 安全校验）。
// 逃逸位置：调用实参、return/throw 值、赋值右值、赋值/自增目标、声明初始化式、
// 闭包体引用等。字段读写/方法调用的接收者、is/=== 比较不算逃逸。
func escapeIdents(body *xfront.Block) map[string]bool {
	out := map[string]bool{}
	walkBlockEsc(body, out)
	return out
}

func walkBlockEsc(b *xfront.Block, out map[string]bool) {
	if b == nil {
		return
	}
	for _, st := range b.Stmts {
		walkStmtEsc(st, out)
	}
}

func walkStmtEsc(st xfront.Stmt, out map[string]bool) {
	switch n := st.(type) {
	case *xfront.ReturnStmt:
		walkExprEsc(n.Value, true, out)
	case *xfront.ThrowStmt:
		walkExprEsc(n.Value, true, out)
	case *xfront.ExprStmt:
		walkExprEsc(n.X, true, out)
	case *xfront.LocalDeclStmt:
		walkExprEsc(n.Init, true, out)
	case *xfront.AssignStmt:
		walkExprEsc(n.Value, true, out)
		switch t := n.Target.(type) {
		case *xfront.IdentExpr:
			out[t.Name] = true
		case *xfront.Member:
			walkExprEsc(t.X, false, out) // 字段写入不发布接收者
		case *xfront.Index:
			walkExprEsc(t.X, true, out)
			walkExprEsc(t.Idx, true, out)
		}
	case *xfront.IncDecStmt:
		if id, ok := n.Target.(*xfront.IdentExpr); ok {
			out[id.Name] = true
		}
	case *xfront.IfStmt:
		walkExprEsc(n.Cond, true, out)
		walkBlockEsc(n.Then, out)
		if n.Else != nil {
			walkStmtEsc(n.Else, out)
		}
	case *xfront.WhileStmt:
		walkExprEsc(n.Cond, true, out)
		walkBlockEsc(n.Body, out)
	case *xfront.DoWhileStmt:
		walkBlockEsc(n.Body, out)
		walkExprEsc(n.Cond, true, out)
	case *xfront.ForStmt:
		walkExprEsc(n.Src, true, out)
		walkBlockEsc(n.Body, out)
	case *xfront.SwitchStmt:
		walkExprEsc(n.Value, true, out)
		for _, c := range n.Cases {
			walkExprEsc(c.Expr, true, out)
			for _, s := range c.Stmts {
				walkStmtEsc(s, out)
			}
		}
		if n.Default != nil {
			for _, s := range n.Default.Stmts {
				walkStmtEsc(s, out)
			}
		}
	case *xfront.DeferStmt:
		if n.Block != nil {
			walkBlockEsc(n.Block, out)
		} else if n.Stmt != nil {
			walkStmtEsc(n.Stmt, out)
		}
	case *xfront.LabeledStmt:
		walkStmtEsc(n.Stmt, out)
	}
}

func walkExprEsc(e xfront.Expr, mark bool, out map[string]bool) {
	switch n := e.(type) {
	case nil:
		return
	case *xfront.IdentExpr:
		if mark {
			out[n.Name] = true
		}
	case *xfront.StrLitExpr:
		for _, p := range n.Parts {
			walkExprEsc(p.Expr, mark, out)
		}
	case *xfront.Paren:
		walkExprEsc(n.X, mark, out)
	case *xfront.Tuple:
		for _, el := range n.Elems {
			walkExprEsc(el, mark, out)
		}
	case *xfront.ArrayLit:
		for _, el := range n.Elems {
			walkExprEsc(el, mark, out)
		}
	case *xfront.MapLit:
		for i := range n.Keys {
			walkExprEsc(n.Keys[i], mark, out)
			walkExprEsc(n.Vals[i], mark, out)
		}
	case *xfront.Unary:
		walkExprEsc(n.X, mark, out)
	case *xfront.Binary:
		// 纯读比较不发布操作数；其余运算照常递归。
		switch n.Op {
		case "is", "==", "!=", "===", "!==":
			walkExprEsc(n.L, false, out)
			walkExprEsc(n.R, false, out)
		default:
			walkExprEsc(n.L, mark, out)
			walkExprEsc(n.R, mark, out)
		}
	case *xfront.Ternary:
		walkExprEsc(n.Cond, mark, out)
		walkExprEsc(n.Then, mark, out)
		walkExprEsc(n.Else, mark, out)
	case *xfront.Member:
		walkExprEsc(n.X, false, out) // 接收者只在本次访问期间使用
	case *xfront.TupleMember:
		walkExprEsc(n.X, false, out)
	case *xfront.Call:
		for _, a := range n.Args {
			walkExprEsc(a, true, out) // 实参可被调用方保存
		}
		if m, ok := n.Callee.(*xfront.Member); ok {
			walkExprEsc(m.X, false, out)
		} else {
			walkExprEsc(n.Callee, true, out)
		}
	case *xfront.Index:
		walkExprEsc(n.X, true, out)
		walkExprEsc(n.Idx, true, out)
	case *xfront.New:
		for _, a := range n.Args {
			walkExprEsc(a, true, out)
		}
	case *xfront.NewArray:
		walkExprEsc(n.Count, true, out)
	case *xfront.Lambda:
		// 闭包可达帧外：体内引用的外部局部按逃逸处理（保守）。
		walkExprAll(n.ExprB, out)
		walkBlockAll(n.Block, out)
	}
}

// walkExprAll 标记表达式内出现的全部标识符（闭包捕获场景，保守）。
func walkExprAll(e xfront.Expr, out map[string]bool) {
	switch n := e.(type) {
	case nil:
		return
	case *xfront.IdentExpr:
		out[n.Name] = true
	case *xfront.StrLitExpr:
		for _, p := range n.Parts {
			walkExprAll(p.Expr, out)
		}
	case *xfront.Paren:
		walkExprAll(n.X, out)
	case *xfront.Tuple:
		for _, el := range n.Elems {
			walkExprAll(el, out)
		}
	case *xfront.ArrayLit:
		for _, el := range n.Elems {
			walkExprAll(el, out)
		}
	case *xfront.MapLit:
		for i := range n.Keys {
			walkExprAll(n.Keys[i], out)
			walkExprAll(n.Vals[i], out)
		}
	case *xfront.Unary:
		walkExprAll(n.X, out)
	case *xfront.Binary:
		walkExprAll(n.L, out)
		walkExprAll(n.R, out)
	case *xfront.Ternary:
		walkExprAll(n.Cond, out)
		walkExprAll(n.Then, out)
		walkExprAll(n.Else, out)
	case *xfront.Member:
		walkExprAll(n.X, out)
	case *xfront.TupleMember:
		walkExprAll(n.X, out)
	case *xfront.Call:
		walkExprAll(n.Callee, out)
		for _, a := range n.Args {
			walkExprAll(a, out)
		}
	case *xfront.Index:
		walkExprAll(n.X, out)
		walkExprAll(n.Idx, out)
	case *xfront.New:
		for _, a := range n.Args {
			walkExprAll(a, out)
		}
	case *xfront.NewArray:
		walkExprAll(n.Count, out)
	case *xfront.Lambda:
		walkExprAll(n.ExprB, out)
		walkBlockAll(n.Block, out)
	}
}

func walkBlockAll(b *xfront.Block, out map[string]bool) {
	if b == nil {
		return
	}
	for _, st := range b.Stmts {
		walkStmtAll(st, out)
	}
}

func walkStmtAll(st xfront.Stmt, out map[string]bool) {
	switch n := st.(type) {
	case *xfront.ReturnStmt:
		walkExprAll(n.Value, out)
	case *xfront.ThrowStmt:
		walkExprAll(n.Value, out)
	case *xfront.ExprStmt:
		walkExprAll(n.X, out)
	case *xfront.LocalDeclStmt:
		walkExprAll(n.Init, out)
	case *xfront.AssignStmt:
		walkExprAll(n.Target, out)
		walkExprAll(n.Value, out)
	case *xfront.IncDecStmt:
		walkExprAll(n.Target, out)
	case *xfront.IfStmt:
		walkExprAll(n.Cond, out)
		walkBlockAll(n.Then, out)
		if n.Else != nil {
			walkStmtAll(n.Else, out)
		}
	case *xfront.WhileStmt:
		walkExprAll(n.Cond, out)
		walkBlockAll(n.Body, out)
	case *xfront.DoWhileStmt:
		walkBlockAll(n.Body, out)
		walkExprAll(n.Cond, out)
	case *xfront.ForStmt:
		walkExprAll(n.Src, out)
		walkBlockAll(n.Body, out)
	case *xfront.SwitchStmt:
		walkExprAll(n.Value, out)
		for _, c := range n.Cases {
			walkExprAll(c.Expr, out)
			for _, s := range c.Stmts {
				walkStmtAll(s, out)
			}
		}
		if n.Default != nil {
			for _, s := range n.Default.Stmts {
				walkStmtAll(s, out)
			}
		}
	case *xfront.DeferStmt:
		if n.Block != nil {
			walkBlockAll(n.Block, out)
		} else if n.Stmt != nil {
			walkStmtAll(n.Stmt, out)
		}
	case *xfront.LabeledStmt:
		walkStmtAll(n.Stmt, out)
	}
}
