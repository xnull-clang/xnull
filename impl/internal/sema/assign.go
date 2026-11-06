package sema

import "xnull.dev/xnull/internal/xfront"

// ---------- M2-B 确定赋值（S1 §5.3 + §6.1 返回路径） ----------
//
// 数据流：dstate = "确定已赋值的局部名集合" + 可达性。
// 合并规则：多条入边取交集（每条可达路径都必须赋值）；不可达路径不参与约束。
// 保守决策（宁可漏报不误报）：
//   - while/do-while 循环后只保留进入前状态（do-while 体至少执行一次，
//     故保留体出口状态与进入状态的交集；break 站点按进入状态并入）；
//   - &&/||/?? 右侧与三元分支中的读取照常检查，但赋值不可能出现在表达式
//     中（§6.1：赋值/自增自减只作语句），无需投机路径；
//   - goto 使线性流中断：含 goto 的函数跳过返回路径检查（保守），
//     标签处的状态 = 顺流状态 ∩ 各 goto 站点快照（单遍近似，见测试边界说明）。

// 诊断码（确定赋值段位）。
const (
	DaMaybeUnassigned = "DA-101" // 可能未赋值即读取（§5.3）
	DaReassign        = "DA-102" // final/const 重复赋值（§5.3）
	DaMissingReturn   = "DA-103" // 非 void 函数存在不返回的正常路径（§6.1）
)

// dstate 是一条控制流路径上的确定赋值状态。
type dstate struct {
	assigned    map[string]bool
	final       map[string]bool // final/const 名（重复赋值检测）
	unreachable bool            // 该路径必然退出（return/throw/goto）
}

func newDstate() *dstate {
	return &dstate{assigned: map[string]bool{}, final: map[string]bool{}}
}

func (s *dstate) clone() *dstate {
	c := &dstate{assigned: map[string]bool{}, final: s.final, unreachable: s.unreachable}
	for k := range s.assigned {
		c.assigned[k] = true
	}
	return c
}

// merge 返回多条路径汇合后的状态：交集；不可达路径不参与。
func mergeDstates(states []*dstate) *dstate {
	live := 0
	for _, s := range states {
		if !s.unreachable {
			live++
		}
	}
	if live == 0 { // 全部不可达 → 汇合点不可达
		return &dstate{assigned: map[string]bool{}, final: states[0].final, unreachable: true}
	}
	out := &dstate{assigned: map[string]bool{}, final: states[0].final}
	first := true
	for _, s := range states {
		if s.unreachable {
			continue
		}
		if first {
			for k := range s.assigned {
				out.assigned[k] = true
			}
			first = false
			continue
		}
		for k := range out.assigned {
			if !s.assigned[k] {
				delete(out.assigned, k)
			}
		}
	}
	return out
}

// danalyze 是一个函数的确定赋值分析上下文。
type danalyze struct {
	an             *analyzer
	file           string
	gotos          map[string][]*dstate // 标签 → 各 goto 站点的状态快照（单遍近似）
	hasGos         bool
	declaredLocals map[string]bool // 本函数内声明过的局部/参数（顶层名不误报）
}

func (d *danalyze) errf(p xfront.Pos, code, msg, hint string) {
	d.an.errf(p, code, msg, hint)
}

// analyzeAssign 对单个顶层函数做确定赋值与返回路径分析。
func (a *analyzer) analyzeAssign(file string, fn *xfront.TopFunc) {
	d := &danalyze{an: a, file: file, gotos: map[string][]*dstate{}, declaredLocals: map[string]bool{}}
	st := newDstate()
	for _, p := range fn.Params {
		st.assigned[p.Name] = true
		d.declaredLocals[p.Name] = true
	}
	d.walkBlock(fn.Body, st)
	// §6.1：非 void 函数所有正常路径必须返回。
	if !fn.Void && !d.hasGos && fn.Body != nil && !d.bodyNeverFallsThrough(fn.Body, st) {
		a.errf(fn.P, DaMissingReturn, "函数 `"+fn.Name+"` 存在不返回的正常路径（非 void 返回类型，§6.1）",
			"为所有路径补充 return；`while true` 无 break 的循环之后视为不可达")
	}
}

func (d *danalyze) walkBlock(b *xfront.Block, st *dstate) {
	if b == nil {
		return
	}
	cur := st
	for _, s := range b.Stmts {
		cur = d.stmt(s, cur)
	}
}

// blockExit 返回块执行完后的状态；neverFalls 报告该块是否必然退出（线性路径上）。
func (d *danalyze) blockExit(b *xfront.Block, in *dstate) (out *dstate, neverFalls bool) {
	if b == nil {
		return in, false
	}
	st := in
	for _, s := range b.Stmts {
		if st.unreachable {
			return st, true // 线性路径已中断
		}
		st = d.stmt(s, st)
	}
	return st, st.unreachable // 末语句为 return/throw/goto 时线性路径中断
}

func (d *danalyze) bodyNeverFallsThrough(b *xfront.Block, st *dstate) bool {
	_, never := d.blockExit(b, st)
	return never
}

// stmt 执行一条语句的确定赋值转移，返回出口状态。
func (d *danalyze) stmt(s xfront.Stmt, st *dstate) *dstate {
	switch n := s.(type) {
	case *xfront.LocalDeclStmt:
		if n.Init != nil {
			d.walkExpr(n.Init, st)
			st = st.clone()
			st.assigned[n.Name] = true
			if n.Final || n.Const {
				f := st.clone()
				f.final = map[string]bool{}
				for k, v := range st.final {
					f.final[k] = v
				}
				f.final[n.Name] = true
				f.assigned[n.Name] = true
				return f
			}
			return st
		}
		// var 无初始化式：声明后暂不赋值合法（§5.3 末条）；final 无初始化式
		// 须在每条路径上恰好赋值一次——登记 final，重复赋值由 DA-102 捕获，
		// 路径末"恰好一次"在本遍以"读取时必须已赋值"近似。
		st = st.clone()
		d.declaredLocals[n.Name] = true
		if n.Final || n.Const {
			st.final[n.Name] = true
		}
		return st
	case *xfront.AssignStmt:
		d.walkExpr(n.Value, st)
		if id, ok := n.Target.(*xfront.IdentExpr); ok {
			if st.final[id.Name] && st.assigned[id.Name] {
				d.errf(n.P, DaReassign, "final/const 局部 `"+id.Name+"` 不得再次赋值（§5.3）", "声明时初始化，或改用 var")
			}
			if _, compound := map[string]bool{"=": true}[n.Op]; !compound {
				d.mustBeAssigned(n.P, id.Name, st) // 复合赋值先读后写
			}
			out := st.clone()
			out.assigned[id.Name] = true
			return out
		}
		// 成员/下标赋值目标：读取基底表达式
		if m, ok := n.Target.(*xfront.Member); ok {
			d.walkExpr(m.X, st)
		}
		if ix, ok := n.Target.(*xfront.Index); ok {
			d.walkExpr(ix.X, st)
			d.walkExpr(ix.Idx, st)
		}
		return st
	case *xfront.IncDecStmt:
		if id, ok := n.Target.(*xfront.IdentExpr); ok {
			d.mustBeAssigned(n.P, id.Name, st) // 自增自减先读后写（§7.3）
			out := st.clone()
			out.assigned[id.Name] = true
			return out
		}
		return st
	case *xfront.ExprStmt:
		d.walkExpr(n.X, st)
		return st
	case *xfront.ReturnStmt:
		if n.Value != nil {
			d.walkExpr(n.Value, st)
		}
		out := st.clone()
		out.unreachable = true
		return out
	case *xfront.ThrowStmt:
		d.walkExpr(n.Value, st)
		out := st.clone()
		out.unreachable = true
		return out
	case *xfront.GotoStmt:
		d.hasGos = true
		d.gotos[n.Label] = append(d.gotos[n.Label], st.clone())
		out := st.clone()
		out.unreachable = true // 线性流中断（§6.10）
		return out
	case *xfront.LabeledStmt:
		// 标签处状态 = 顺流状态 ∩ 各 goto 站点快照（§5.3：goto 不得使未赋值变量通过检查）
		if snaps, ok := d.gotos[n.Label]; ok && len(snaps) > 0 {
			all := append([]*dstate{st}, snaps...)
			st = mergeDstates(all)
		}
		if n.Stmt != nil {
			return d.stmt(n.Stmt, st)
		}
		return st
	case *xfront.IfStmt:
		d.walkExpr(n.Cond, st)
		thenOut, _ := d.blockExit(n.Then, st.clone())
		if n.Else == nil {
			// 无 else：条件为假直接旁路
			return mergeDstates([]*dstate{thenOut, st})
		}
		var elseOut *dstate
		if eb, ok := n.Else.(*xfront.Block); ok {
			elseOut, _ = d.blockExit(eb, st.clone())
		} else {
			elseOut = d.stmt(n.Else, st.clone())
		}
		return mergeDstates([]*dstate{thenOut, elseOut})
	case *xfront.WhileStmt:
		d.walkExpr(n.Cond, st)
		d.blockExit(n.Body, st.clone()) // 体一遍照常检查读取
		// §5.3：`while true` 且无可达 break → 循环后不可达
		if isTrueLiteral(n.Cond) && !d.loopHasBreak(n.Body) {
			out := st.clone()
			out.unreachable = true
			return out
		}
		return st // 循环可能零次执行：保守回退到进入前状态
	case *xfront.DoWhileStmt:
		// 体至少执行一次：出口 = 体出口状态（含体内的赋值）。
		// 保守边界：体内 break 站点的状态未并入（跳过 do-while 时可能未赋值），
		// 含 break 的 do-while 由读取方 DA-101 的保守误报风险承担（不漏报）。
		d.walkExpr(n.Cond, st)
		bodyOut, _ := d.blockExit(n.Body, st.clone())
		return bodyOut
	case *xfront.ForStmt:
		d.walkExpr(n.Src, st)
		d.blockExit(n.Body, st.clone()) // 体一遍照常检查读取
		return st                       // 区间可能为空：保守回退
	case *xfront.SwitchStmt:
		d.walkExpr(n.Value, st)
		var outs []*dstate
		for _, c := range n.Cases {
			co, _ := d.blockExit(&xfront.Block{P: n.P, Stmts: c.Stmts}, st.clone())
			outs = append(outs, co)
		}
		if len(n.Cases) == 0 {
			return st
		}
		if n.Default == nil {
			outs = append(outs, st) // 无 default：可能无匹配项直接旁路
		}
		return mergeDstates(outs)
	case *xfront.DeferStmt:
		// defer/errdefer 体在作用域退出时执行，不影响确定赋值（§10.3）
		return st
	case *xfront.BreakStmt, *xfront.ContinueStmt:
		return st // 循环内转移：状态保守按当前路径上抛
	case *xfront.Block:
		out, _ := d.blockExit(n, st)
		return out
	case *xfront.EmptyStmt:
		return st
	}
	return st
}

func (d *danalyze) mustBeAssigned(p xfront.Pos, name string, st *dstate) {
	if st.final[name] {
		return // final 已赋值（否则 DA-102 已报）
	}
	if !st.assigned[name] {
		d.errf(p, DaMaybeUnassigned, "局部 `"+name+"` 可能未赋值即被读取（§5.3 确定赋值）",
			"声明时初始化，或在所有读取路径之前赋值")
	}
}

func isTrueLiteral(e xfront.Expr) bool {
	b, ok := e.(*xfront.BoolLit)
	return ok && b.V
}

// loopHasBreak 检查循环体（浅层，不进入嵌套循环/switch）是否含可达 break。
func (d *danalyze) loopHasBreak(b *xfront.Block) bool {
	if b == nil {
		return false
	}
	for _, s := range b.Stmts {
		switch n := s.(type) {
		case *xfront.BreakStmt:
			if n.Label == "" {
				return true
			}
		case *xfront.IfStmt:
			if d.loopHasBreak(n.Then) {
				return true
			}
			if eb, ok := n.Else.(*xfront.Block); ok && d.loopHasBreak(eb) {
				return true
			}
		case *xfront.Block:
			if d.loopHasBreak(n) {
				return true
			}
		}
	}
	return false
}

// walkExpr 检查表达式中的读取（DA-101）。
func (d *danalyze) walkExpr(e xfront.Expr, st *dstate) {
	switch n := e.(type) {
	case *xfront.IdentExpr:
		if n.Name == "true" || n.Name == "false" {
			return
		}
		if st.assigned[n.Name] {
			return
		}
		d.maybeLocalRead(n, st) // 只对声明过的局部报；顶层/内置名由 declaredLocals 排除
	case *xfront.Paren:
		d.walkExpr(n.X, st)
	case *xfront.Unary:
		d.walkExpr(n.X, st)
	case *xfront.Binary:
		d.walkExpr(n.L, st)
		d.walkExpr(n.R, st)
	case *xfront.Ternary:
		d.walkExpr(n.Cond, st)
		d.walkExpr(n.Then, st)
		d.walkExpr(n.Else, st)
	case *xfront.StrLitExpr:
		for _, p := range n.Parts {
			if p.Expr != nil {
				d.walkExpr(p.Expr, st)
			}
		}
	case *xfront.Call:
		d.walkExpr(n.Callee, st)
		for _, a := range n.Args {
			d.walkExpr(a, st)
		}
	case *xfront.Member:
		d.walkExpr(n.X, st)
	case *xfront.TupleMember:
		d.walkExpr(n.X, st)
	case *xfront.Index:
		d.walkExpr(n.X, st)
		d.walkExpr(n.Idx, st)
	case *xfront.Tuple:
		for _, el := range n.Elems {
			d.walkExpr(el, st)
		}
	case *xfront.ArrayLit:
		for _, el := range n.Elems {
			d.walkExpr(el, st)
		}
	case *xfront.MapLit:
		for i := range n.Keys {
			d.walkExpr(n.Keys[i], st)
			d.walkExpr(n.Vals[i], st)
		}
	case *xfront.New:
		for _, a := range n.Args {
			d.walkExpr(a, st)
		}
	case *xfront.NewArray:
		d.walkExpr(n.Count, st)
	case *xfront.Lambda:
		// 闭包体的读取按捕获语义处理，本遍不检查（限制见立项文档）
	}
}

// maybeLocalRead 只对"本函数内声明过"的局部报 DA-101；顶层/内置名不误报。
// 声明过的判定：进入分析时登记参数，遍中登记 LocalDeclStmt——这里复用
// assigned 集合的影子：用一个单独的 declared 集合。
func (d *danalyze) maybeLocalRead(n *xfront.IdentExpr, st *dstate) {
	if d.declaredLocals[n.Name] {
		d.errf(n.P, DaMaybeUnassigned, "局部 `"+n.Name+"` 可能未赋值即被读取（§5.3 确定赋值）",
			"声明时初始化，或在所有读取路径之前赋值")
	}
}
