package sema

import (
	"fmt"
	"sort"

	"xnull.dev/xnull/internal/xfront"
)

// ---------- M2.5.2：内存策略判定输入（S2 §15.1） ----------
//
// 判定表输入全部来自源码结构：种类、字段类型图、引用环分析、deinit 存在性、
// self 捕获（§15.1）。逃逸分类是对象创建点分析（§15.2），不在类型级判定内；
// Strategy.Escape 为对象级提升预留接口，M4.1 逃逸分析填充。
//
// 本结构自 M2.5.2 起冻结，供 M3.2 判定表执行器（C 运行时）消费：
//   Policy          取值 "value" | "arc" | "gc" | "na-gc"
//   StackEligible   类型级栈候选（行 8）；对象级还需逃逸分类 none 且无 deinit/捕获
//   Rule            命中的 §15.1 判定行（1-9；struct 为 0）
// 确定性（DET-01）：同一 AST、同一实现版本产出逐字段相等的结果；
// 输出按键名排序，不依赖声明顺序与文件枚举顺序。

// Strategy 是单个类型声明的策略判定结果。
type Strategy struct {
	Decl          string `json:"decl"`
	Kind          string `json:"kind"`   // class/struct/enum/protocol
	DataEnum      bool   `json:"data"`   // 数据枚举
	Policy        string `json:"policy"` // value/arc/gc/na-gc
	StackEligible bool   `json:"stackEligible"`
	Deinit        bool   `json:"deinit"`
	SelfCaptured  bool   `json:"selfCaptured"`
	RefCycle      bool   `json:"refCycle"`
	Escape        string `json:"escape"` // 对象级逃逸分类（§15.2）：类型级判定为 "n/a"
	Rule          int    `json:"rule"`
}

// ComputeStrategies 对编译单元做策略判定；结果按声明名排序（确定性）。
func (a *analyzer) ComputeStrategies(u *xfront.CompilationUnit) []Strategy {
	out := []Strategy{}
	for _, d := range u.Decls {
		switch n := d.(type) {
		case *xfront.ClassDecl:
			out = append(out, a.strategyClass(n))
		case *xfront.StructDecl:
			out = append(out, Strategy{Decl: n.Name, Kind: "struct", Policy: "value", Escape: "n/a"})
		case *xfront.ProtocolDecl:
			out = append(out, Strategy{Decl: n.Name, Kind: "protocol", Policy: "na-gc", Escape: "n/a", Rule: 2})
		case *xfront.EnumDecl:
			if n.IsData {
				out = append(out, Strategy{Decl: n.Name, Kind: "enum", DataEnum: true, Policy: "gc", Escape: "n/a", Rule: 4})
			} else {
				out = append(out, Strategy{Decl: n.Name, Kind: "enum", Policy: "value", Escape: "n/a", Rule: 3})
			}
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Decl < out[j].Decl })
	return out
}

// fieldRef 分类：类强引用字段的引用类别（§15.1 行 5/6/9 的判定输入）。
//
//	"value"      值（标量/简单枚举/struct/值元组/可空值）
//	"gc"         直接触发行 5（Any/Object/协议/未单态化泛型/Result/含引用元组/函数类型）
//	"ref"        普通引用（内建引用类型、数据枚举），按行 9 ARC 管理
//	"class:Name" 具体类引用，参与环分析
func (a *analyzer) fieldRefClass(t xfront.TypeRef, inClass *xfront.ClassDecl) string {
	switch ty := t.(type) {
	case nil:
		return "ref"
	case *xfront.NamedType:
		name := ty.Qual[len(ty.Qual)-1]
		if len(ty.Args) > 0 {
			switch name {
			case "Any", "Object", "Result":
				return "gc" // 行 5（基名即命中；Result 为当前实现保守项）
			}
			// 泛型实例：实参含类型参数或未解析类型 → 未单态化 → 行 5
			for _, arg := range ty.Args {
				if a.fieldRefClass(arg, inClass) == "gc" || a.isTypeParam(arg, inClass) {
					return "gc"
				}
			}
			return "ref"
		}
		if scalarValueType(name) || name == "String" || name == "Text" ||
			name == "Bytes" || name == "StringBuilder" {
			return "value"
		}
		if info, ok := a.tc.types[name]; ok {
			switch info.kind {
			case "struct":
				return "value"
			case "enum":
				if info.enum.IsData {
					return "ref" // 数据枚举项是 GC 全局根（§8.3），宿主按 ARC 持引用
				}
				return "value"
			case "protocol":
				return "gc" // 行 5
			case "class":
				return "class:" + name
			}
		}
		switch name {
		case "Any", "Object", "Result":
			return "gc" // 行 5（Result 为当前实现保守项）
		}
		if a.isTypeParam(ty, inClass) {
			return "gc" // 未单态化（行 5）
		}
		return "ref"
	case *xfront.SuffixedType:
		for _, s := range ty.Suffixes {
			if s == "[]" {
				return "ref" // 数组：内建引用容器
			}
		}
		return a.fieldRefClass(ty.Base, inClass)
	case *xfront.TupleTypeRef:
		for _, el := range ty.Elems {
			c := a.fieldRefClass(el, inClass)
			if c == "gc" || c == "ref" || (len(c) > 6 && c[:6] == "class:") {
				return "gc" // 含引用元素的元组（行 5）
			}
		}
		return "value"
	case *xfront.FuncTypeRef:
		return "gc" // 函数类型保守按 GC（§15.1.1 不可分析归 GC）
	}
	return "ref"
}

// isTypeParam 判断命名类型是否为所在泛型类的类型参数（未单态化）。
func (a *analyzer) isTypeParam(t xfront.TypeRef, inClass *xfront.ClassDecl) bool {
	nt, ok := t.(*xfront.NamedType)
	if !ok || len(nt.Args) > 0 || len(nt.Qual) != 1 || inClass == nil {
		return false
	}
	for _, p := range inClass.TypePars {
		if p == nt.Qual[0] {
			return true
		}
	}
	return false
}

// strategyClass 按 §15.1 行 5-9 判定类策略。
func (a *analyzer) strategyClass(d *xfront.ClassDecl) Strategy {
	s := Strategy{Decl: d.Name, Kind: "class", Deinit: a.tc.hasDeinit[d.Name],
		SelfCaptured: a.tc.selfCaptured[d.Name], Escape: "n/a"}
	// 字段分类
	valueOnly := true
	hasRef := false
	for _, f := range d.Fields {
		c := a.fieldRefClass(f.Type, d)
		switch {
		case c == "value":
			// 值字段
		case c == "gc":
			valueOnly = false
			hasRef = true
			if s.Rule == 0 {
				s.Rule = 5
				s.Policy = "gc"
			}
		default: // "ref" 或 "class:Name"
			valueOnly = false
			hasRef = true
		}
	}
	// 行 6：强引用环（字段类型图 DFS）
	if s.Rule == 0 && hasRef && a.classRefCycle(d.Name, map[string]bool{}) {
		s.RefCycle = true
		s.Rule = 6
		s.Policy = "gc"
	}
	// 行 7：deinit 或 self 捕获 → ARC，不做栈分配
	if s.Rule == 0 && (s.Deinit || s.SelfCaptured) {
		s.Rule = 7
		s.Policy = "arc"
	}
	// 行 8：只有值字段 → 栈候选（逃逸后按 §14.2 提升）
	if s.Rule == 0 && valueOnly {
		s.Rule = 8
		s.Policy = "arc"
		s.StackEligible = true
	}
	// 行 9：其余无环类引用 → ARC
	if s.Rule == 0 {
		s.Rule = 9
		s.Policy = "arc"
	}
	return s
}

// classRefCycle 从 name 出发沿具体类引用字段可达 name（含自引用）。
func (a *analyzer) classRefCycle(name string, visiting map[string]bool) bool {
	if visiting[name] {
		return true
	}
	info, ok := a.tc.types[name]
	if !ok || info.kind != "class" {
		return false
	}
	visiting[name] = true
	for _, f := range info.class.Fields {
		if c := a.fieldRefClass(f.Type, info.class); len(c) > 6 && c[:6] == "class:" {
			if a.classRefCycle(c[6:], visiting) {
				return true
			}
		}
	}
	delete(visiting, name)
	return false
}

// scanSelfCapture 判断方法体是否在闭包中捕获 self（§15.1 判定输入）。
// 保守：闭包体内出现 self 标识符即视为捕获。
func scanSelfCapture(b *xfront.Block) bool {
	if b == nil {
		return false
	}
	return scanStmtsSelf(b.Stmts)
}

func scanStmtsSelf(stmts []xfront.Stmt) bool {
	return scanStmtsSelfIn(stmts, false)
}

func scanStmtsSelfIn(stmts []xfront.Stmt, inLambda bool) bool {
	for _, st := range stmts {
		if scanStmtSelfIn(st, inLambda) {
			return true
		}
	}
	return false
}

func scanStmtSelf(st xfront.Stmt) bool { return scanStmtSelfIn(st, false) }

func scanStmtSelfIn(st xfront.Stmt, inLambda bool) bool {
	switch n := st.(type) {
	case nil:
		return false
	case *xfront.ExprStmt:
		return scanExprSelfIn(n.X, inLambda)
	case *xfront.ReturnStmt:
		return scanExprSelfIn(n.Value, inLambda)
	case *xfront.LocalDeclStmt:
		return scanExprSelfIn(n.Init, inLambda)
	case *xfront.AssignStmt:
		return scanExprSelfIn(n.Target, inLambda) || scanExprSelfIn(n.Value, inLambda)
	case *xfront.IncDecStmt:
		return scanExprSelfIn(n.Target, inLambda)
	case *xfront.IfStmt:
		return scanExprSelfIn(n.Cond, inLambda) || scanStmtsSelfIn(n.Then.Stmts, inLambda) ||
			(n.Else != nil && scanStmtSelfIn(n.Else, inLambda))
	case *xfront.WhileStmt:
		return scanExprSelfIn(n.Cond, inLambda) || scanStmtsSelfIn(n.Body.Stmts, inLambda)
	case *xfront.DoWhileStmt:
		return scanStmtsSelfIn(n.Body.Stmts, inLambda) || scanExprSelfIn(n.Cond, inLambda)
	case *xfront.ForStmt:
		return scanExprSelfIn(n.Src, inLambda) || scanStmtsSelfIn(n.Body.Stmts, inLambda)
	case *xfront.SwitchStmt:
		if scanExprSelfIn(n.Value, inLambda) {
			return true
		}
		for _, c := range n.Cases {
			if scanExprSelfIn(c.Expr, inLambda) || scanStmtsSelfIn(c.Stmts, inLambda) {
				return true
			}
		}
	case *xfront.DeferStmt:
		if n.Block != nil {
			return scanStmtsSelfIn(n.Block.Stmts, inLambda)
		}
		return scanStmtSelfIn(n.Stmt, inLambda)
	case *xfront.LabeledStmt:
		return scanStmtSelfIn(n.Stmt, inLambda)
	case *xfront.ThrowStmt:
		return scanExprSelfIn(n.Value, inLambda)
	}
	return false
}

// scanExprSelf 遍历表达式：只有进入 Lambda 体后才认 self 为捕获；
// 非 Lambda 位置的 self 由 §5.8 成员解析处理，不计捕获。
func scanExprSelf(e xfront.Expr) bool { return scanExprSelfIn(e, false) }

// scanExprSelfIn 只有 inLambda=true 时才把 self 标识符计为捕获。
func scanExprSelfIn(e xfront.Expr, inLambda bool) bool {
	switch n := e.(type) {
	case nil:
		return false
	case *xfront.IdentExpr:
		return inLambda && n.Name == "self"
	case *xfront.Lambda:
		if n.Block != nil {
			return scanStmtsSelfIn(n.Block.Stmts, true)
		}
		return scanExprSelfIn(n.ExprB, true)
	case *xfront.Paren:
		return scanExprSelfIn(n.X, inLambda)
	case *xfront.Tuple:
		for _, el := range n.Elems {
			if scanExprSelfIn(el, inLambda) {
				return true
			}
		}
	case *xfront.ArrayLit:
		for _, el := range n.Elems {
			if scanExprSelfIn(el, inLambda) {
				return true
			}
		}
	case *xfront.MapLit:
		for i := range n.Keys {
			if scanExprSelf(n.Keys[i]) || scanExprSelf(n.Vals[i]) {
				return true
			}
		}
	case *xfront.Unary:
		return scanExprSelfIn(n.X, inLambda)
	case *xfront.Binary:
		return scanExprSelfIn(n.L, inLambda) || scanExprSelfIn(n.R, inLambda)
	case *xfront.Ternary:
		return scanExprSelfIn(n.Cond, inLambda) || scanExprSelfIn(n.Then, inLambda) || scanExprSelfIn(n.Else, inLambda)
	case *xfront.Member:
		return scanExprSelfIn(n.X, inLambda)
	case *xfront.Call:
		if scanExprSelfIn(n.Callee, inLambda) {
			return true
		}
		for _, a := range n.Args {
			if scanExprSelfIn(a, inLambda) {
				return true
			}
		}
	case *xfront.Index:
		return scanExprSelfIn(n.X, inLambda) || scanExprSelfIn(n.Idx, inLambda)
	case *xfront.New:
		for _, a := range n.Args {
			if scanExprSelfIn(a, inLambda) {
				return true
			}
		}
	case *xfront.NewArray:
		return scanExprSelfIn(n.Count, inLambda)
	}
	return false
}

// fmtStrategyRow 供 CLI 表格输出。
func fmtStrategyRow(s Strategy) string {
	return fmt.Sprintf("%-14s %-9s policy=%-6s rule=%d stack=%v deinit=%v capture=%v cycle=%v",
		s.Decl, s.Kind, s.Policy, s.Rule, s.StackEligible, s.Deinit, s.SelfCaptured, s.RefCycle)
}
