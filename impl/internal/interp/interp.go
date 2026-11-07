// Package interp 是最小可运行闭环的 tree-walking 解释器。
//
// 范围：单个 XNull 文件 → 解析 → 执行 → 输出。
// 支持：顶层函数/字段、局部声明、赋值与复合赋值、自增/自减、if/while/do-while/
// for-in 区间、switch（无隐式贯穿）、break/continue、Result/Ok/Err/try 传播
// （S1 §10.1—10.2）、defer/errdefer LIFO（S1 §10.3）、throw fatal（§10.4）、
// 字符串插值、三元、??、逻辑短路。
//
// 内置函数 ≤ 3：print（当前仅 1 个）。Ok/Err 是语言构造器，不是内置函数。
//
// 类型系统：解释期不做静态类型检查（M1 语义分析在后续切片）；解释器按值
// 动态执行，语义对齐 S1 §7 运算符与 §10 错误处理。整数溢出、除零等 fatal
// 路径按 §10.4 终止进程（退出码 1）。
package interp

import (
	"fmt"
	"io"
	"strconv"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

// ---------- 值模型 ----------

type valKind int

const (
	vNull valKind = iota
	vBool
	vInt
	vFloat
	vChar
	vStr
	vResult
	vArr     // T[]（固定长度，§9.3）
	vList    // List<T>（§9.1）
	vMap     // Map<K,V>（§9.1，键序确定性见 mapv）
	vSet     // Set<T>（§9.1）
	vTuple   // (T1, T2, ...)（§2.11）
	vClosure // 闭包值（§7.7）
	vObj     // 类实例（M4.4b）
	vEnum    // 简单枚举值（S2 §8.2：名义类型 + 底层 Int）
	vStruct  // 结构体值（S2 §3：纯值类型）
)

// Value 是解释期运行值。
type Value struct {
	K   valKind
	B   bool
	I   int64
	F   float64
	C   rune
	S   string
	R   *resv
	A   []*Value // 数组/List/元组元素
	M   *mapv    // Map
	Set *setv    // Set
	Clo *clov    // 闭包
	O   *objv    // 类实例（M4.4b）
	E   string   // 枚举类型名（vEnum；S2 §8）
	St  *structv // 结构体值（vStruct；S2 §3）
}

// resv 是 Result 运行值（当前 E 限定为可打印值；泛型检查在语义层）。
type resv struct {
	ok bool
	v  *Value
	e  *Value
}

func (v *Value) isResult() bool { return v != nil && v.K == vResult }

func (v *Value) typeName() string {
	switch v.K {
	case vNull:
		return "null"
	case vBool:
		return "Bool"
	case vInt:
		return "Int"
	case vFloat:
		return "Float"
	case vChar:
		return "Char"
	case vStr:
		return "String"
	case vResult:
		return "Result"
	case vArr:
		return "Array"
	case vList:
		return "List"
	case vMap:
		return "Map"
	case vSet:
		return "Set"
	case vTuple:
		return "Tuple"
	case vClosure:
		return "Closure"
	case vObj:
		if v.O.enumName != "" {
			return v.O.enumName
		}
		return v.O.cls.Name
	case vEnum:
		return v.E
	case vStruct:
		return v.St.decl.Name
	}
	return "?"
}

// format 按打印与插值共用规则格式化（确定性：无 map 参与，输出可逐字节复现）。
func format(v *Value) string {
	switch v.K {
	case vNull:
		return "null"
	case vBool:
		if v.B {
			return "true"
		}
		return "false"
	case vInt:
		return strconv.FormatInt(v.I, 10)
	case vFloat:
		return strconv.FormatFloat(v.F, 'g', -1, 64)
	case vChar:
		return string(v.C)
	case vStr:
		return v.S
	case vResult:
		if v.R.ok {
			return "Ok(" + format(v.R.v) + ")"
		}
		return "Err(" + format(v.R.e) + ")"
	case vEnum:
		return v.S // S2 §8.2：简单枚举按项名格式化
	case vObj:
		if v.O.enumName != "" {
			return v.O.enumItem // S2 §8.5：数据枚举项默认按项名格式化
		}
		return formatContainer(v)
	case vArr, vList, vMap, vSet, vTuple, vClosure:
		return formatContainer(v)
	}
	return "?"
}

// ---------- 控制信号（Go panic/recover 承载结构化控制流） ----------

type ctrlReturn struct{ v *Value }

type ctrlBreak struct{ label string }

type ctrlContinue struct{ label string }

// ctrlErr 是 try 传播：携带 Err 运行值，穿过各层作用域时执行 defer+errdefer。
type ctrlErr struct{ r *resv }

// fatal 是 throw 与隐式 fatal 路径（§10.4：不执行 defer，终止进程）。
type fatal struct{ msg string }

// runtimeErr 是解释器不支持构造的诊断（明确失败，不静默）。
type runtimeErr struct{ msg string }

// ---------- 作用域 ----------

type scope struct {
	parent *scope
	vars   map[string]*Value
	types  map[string]xfront.TypeRef // 声明类型（容器赋值保持种类用）
}

func newScope(parent *scope) *scope {
	return &scope{parent: parent, vars: map[string]*Value{}, types: map[string]xfront.TypeRef{}}
}

func (s *scope) lookup(name string) (*Value, bool) {
	for c := s; c != nil; c = c.parent {
		if v, ok := c.vars[name]; ok {
			return v, true
		}
	}
	return nil, false
}

func (s *scope) define(name string, v *Value) { s.vars[name] = cloneTupleValue(v) }

// defineTyped 登记变量与声明类型；nil/未知类型只登记值。
func (s *scope) defineTyped(name string, t xfront.TypeRef, v *Value) {
	if t != nil {
		s.types[name] = t
		v = coerceByDecl(t, v)
	}
	s.vars[name] = cloneTupleValue(v) // §2.11：元组赋值按值复制
}

// assign 找到名字所在作用域并写入（遮蔽规则：最近声明优先，§5.2）。
// 有声明类型时按类型定向（§9.4/§9.6：容器赋值不得退化为数组）。
func (s *scope) assign(name string, v *Value) bool {
	for c := s; c != nil; c = c.parent {
		if _, ok := c.vars[name]; ok {
			if t, typed := c.types[name]; typed {
				v = coerceByDecl(t, v)
			}
			c.vars[name] = cloneTupleValue(v)
			return true
		}
	}
	return false
}

// ---------- 解释器 ----------

type Interp struct {
	out         io.Writer
	funcs       map[string][]*xfront.TopFunc
	classes     map[string]*xfront.ClassDecl
	globals     *scope
	label       string            // 当前执行的带标签循环的标签（break/continue label 匹配）
	strLit      map[string]*Value // 字符串字面量驻留（§2.8：字面量 === 按对象身份）
	enums       map[string]*xfront.EnumDecl
	enumVals    map[string]map[string]int64  // 简单枚举：项 → 底层值
	enumItems   map[string]map[string]*Value // 枚举项缓存（数据枚举惰性构造）
	protocols   map[string]*xfront.ProtocolDecl
	enumCls     map[string]*xfront.ClassDecl
	classOrder  []*xfront.ClassDecl          // 类声明顺序（静态字段初始化）
	staticVals  map[string]map[string]*Value // 类名 → 静态字段规范名 → 值
	staticCtx   *xfront.ClassDecl            // 当前静态方法/静态字段初始化上下文
	methodStack []*xfront.ClassDecl          // 实例方法声明类栈（super 起点，§5.4）
	structs     map[string]*xfront.StructDecl
}

// Run 执行一个编译单元：初始化顶层字段（§4.3 声明顺序），调用 main。
// 返回进程退出码与错误（S4 §7.2 退出码映射）：
// void main 正常返回 → 0；Int main 返回值原样作为退出码；
// 初始化或运行期 fatal（panic/throw）→ 134；解释器不支持构造 → 1。
// 确定性由"输出只经过 out、无随机源"保证。
// isStringArray 判断参数类型是否 String[]（入口第二形态，S1 §11.2）。
func isStringArray(t xfront.TypeRef) bool {
	st, ok := t.(*xfront.SuffixedType)
	if !ok {
		return false
	}
	for _, sfx := range st.Suffixes {
		if sfx != "[]" {
			return false
		}
	}
	nt, ok := st.Base.(*xfront.NamedType)
	return ok && lastQual(nt) == "String"
}

func Run(u *xfront.CompilationUnit, out io.Writer, progArgs []string) (code int, err error) {
	defer func() {
		if r := recover(); r != nil {
			switch sig := r.(type) {
			case fatal:
				code, err = 134, fmt.Errorf("fatal: %s", sig.msg)
			case runtimeErr:
				code, err = 1, fmt.Errorf("%s", sig.msg)
			default:
				panic(r)
			}
		}
	}()
	in := &Interp{
		out: out, funcs: map[string][]*xfront.TopFunc{}, classes: map[string]*xfront.ClassDecl{},
		globals: newScope(nil), strLit: map[string]*Value{},
		enums: map[string]*xfront.EnumDecl{}, enumVals: map[string]map[string]int64{},
		enumItems: map[string]map[string]*Value{}, protocols: map[string]*xfront.ProtocolDecl{},
		enumCls: map[string]*xfront.ClassDecl{}, staticVals: map[string]map[string]*Value{},
		structs: map[string]*xfront.StructDecl{},
	}
	// 第一遍：登记全部顶层函数/类，并为顶层字段预置零值（§4.3）。
	// 初始化式按声明顺序求值，读尚未初始化的字段得到零值，而不是“未定义”。
	var topFields []*xfront.TopField
	for _, d := range u.Decls {
		switch n := d.(type) {
		case *xfront.TopFunc:
			if n.Name == "<err>" {
				continue
			}
			in.funcs[n.Name] = append(in.funcs[n.Name], n)
		case *xfront.ClassDecl:
			in.classes[n.Name] = n
			in.classOrder = append(in.classOrder, n)
			in.registerStaticFields(n)
		case *xfront.StructDecl:
			in.structs[n.Name] = n
		case *xfront.ProtocolDecl:
			in.protocols[n.Name] = n
		case *xfront.EnumDecl:
			in.registerEnum(n)
		case *xfront.TopField:
			// BLD-01：登记声明类型并做容器定向；P1-INIT-FWD：先给零值。
			in.globals.defineTyped(n.Name, n.Type, in.zeroOf(n.Type))
			topFields = append(topFields, n)
		}
	}
	// 第二遍：按声明顺序求值顶层字段初始化式并写回（§4.3）。
	// assign 按第一遍登记的类型做容器定向（List/Set 字面量，BLD-01）。
	for _, n := range topFields {
		if n.Init != nil {
			in.globals.assign(n.Name, in.eval(n.Init, in.globals))
		}
	}
	// 静态字段初始化式：按类声明顺序（§7.1）。
	in.initStaticFields()
	mains := in.funcs["main"]
	if len(mains) == 0 {
		return 1, fmt.Errorf("找不到入口 main（缺失入口，§11.4）")
	}
	// §11.2：只有匹配入口签名的 main 才是入口；其余 main 重载是普通函数。
	var matched []*xfront.TopFunc
	for _, fn := range mains {
		if checkEntry(fn) == nil {
			matched = append(matched, fn)
		}
	}
	if len(matched) == 0 {
		return 1, checkEntry(mains[0])
	}
	if len(matched) > 1 {
		return 1, fmt.Errorf("重复入口 main（§11.4）：一个程序只能有一个匹配签名的入口")
	}
	main := matched[0]
	// 两种入口形态（S1 §11.2）：main() 与 main(args: String[])。
	var callArgs []*Value
	switch {
	case len(main.Params) == 0:
	case len(main.Params) == 1 && isStringArray(main.Params[0].Type):
		elems := make([]*Value, len(progArgs))
		for i, a := range progArgs {
			elems[i] = &Value{K: vStr, S: a}
		}
		callArgs = []*Value{{K: vArr, A: elems}}
	}
	v, err := in.call(main, callArgs)
	if err != nil {
		return 1, err
	}
	if v.K == vInt { // Int main 的返回值原样作为退出码（S4 §7.2）
		return int(v.I), nil
	}
	return 0, nil
}

// checkEntry 校验入口签名（§11.2）：顶层 static、公开、非泛型、返回 void/Int、参数为空或 String[]。
func checkEntry(fn *xfront.TopFunc) error {
	if !fn.Static {
		return fmt.Errorf("入口 main 的签名必须是 static void main(...) 或 static Int main(...)（§11.2）")
	}
	if fn.Private || fn.Protected || len(fn.TypePars) > 0 {
		return fmt.Errorf("入口 main 必须是公开的非泛型函数（§11.2）")
	}
	if !fn.Void {
		nt, ok := fn.Ret.(*xfront.NamedType)
		if !ok || lastQual(nt) != "Int" || len(nt.Args) > 0 {
			return fmt.Errorf("入口 main 的签名必须是 static void main(...) 或 static Int main(...)（§11.2）")
		}
	}
	switch {
	case len(fn.Params) == 0:
	case len(fn.Params) == 1 && isStringArray(fn.Params[0].Type):
	default:
		return fmt.Errorf("入口 main 的签名必须是 static void main(...) 或 static Int main(...)，参数只能是 String[]（§11.2）")
	}
	return nil
}

func zeroValue(t xfront.TypeRef) *Value {
	// §4.2 零值：数值 0、Bool false、Char '\0'、引用 null。
	// 当前按声明类型名近似判定；完整类型检查在语义层。
	if st, ok := t.(*xfront.SuffixedType); ok {
		for _, sfx := range st.Suffixes {
			if sfx == "?" {
				return &Value{K: vNull}
			}
		}
		return zeroValue(st.Base)
	}
	if tt, ok := t.(*xfront.TupleTypeRef); ok { // §2.11：值类型元组逐元素取零值
		elems := make([]*Value, len(tt.Elems))
		for i, e := range tt.Elems {
			elems[i] = zeroValue(e)
		}
		return &Value{K: vTuple, A: elems}
	}
	if nt, ok := t.(*xfront.NamedType); ok && len(nt.Qual) == 1 {
		switch nt.Qual[0] {
		case "Int", "Long", "Byte", "Short", "UByte", "UShort", "UInt", "ULong", "Int128", "UInt128":
			return &Value{K: vInt}
		case "Float", "Double":
			return &Value{K: vFloat}
		case "Bool":
			return &Value{K: vBool}
		case "Char":
			return &Value{K: vChar, C: 0}
		}
	}
	return &Value{K: vNull}
}

// call 调用顶层函数；恢复 ctrlReturn 等信号。
func (in *Interp) call(fn *xfront.TopFunc, args []*Value) (v *Value, err error) {
	defer func() {
		if r := recover(); r != nil {
			switch sig := r.(type) {
			case ctrlReturn:
				v, err = sig.v, nil
			case ctrlErr: // try 传播到函数边界：以 Err 返回（§10.2）
				v, err = &Value{K: vResult, R: sig.r}, nil
			case ctrlBreak, ctrlContinue:
				err = fmt.Errorf("break/continue 出现在循环或 switch 之外")
			default:
				panic(r)
			}
		}
	}()
	sc := newScope(in.globals)
	for i, p := range fn.Params {
		if i < len(args) {
			sc.defineTyped(p.Name, p.Type, args[i])
		} else {
			sc.defineTyped(p.Name, p.Type, &Value{K: vNull})
		}
	}
	in.execBlock(fn.Body, sc)
	return &Value{K: vNull}, nil // 无 return 的正常路径（void）
}

// execBlock 执行块：块级 defer 栈；信号穿过时按 §10.3 执行 defer/errdefer。
// ditem 是块级 defer 注册项。
type ditem struct {
	fn     func()
	errdef bool
}

func (in *Interp) execBlock(b *xfront.Block, sc *scope) {
	var defers []ditem
	run := func(errPath bool) {
		for i := len(defers) - 1; i >= 0; i-- { // LIFO（§10.3）
			if !defers[i].errdef || errPath {
				defers[i].fn()
			}
		}
	}
	defer func() {
		if r := recover(); r != nil {
			switch sig := r.(type) {
			case ctrlReturn:
				run(sig.v.isResult() && !sig.v.R.ok) // 返回 Err → errdefer 也执行
				panic(sig)
			case ctrlErr:
				run(true) // try 传播 = 错误路径
				panic(sig)
			case ctrlBreak, ctrlContinue:
				run(false) // 正常路径：只执行 defer
				panic(sig)
			default: // fatal / runtimeErr：不执行任何清理（§10.4）
				panic(r)
			}
		}
		run(false)
	}()
	for _, st := range b.Stmts {
		in.exec(st, sc, &defers)
	}
}

// runDeferBody 执行 defer 体（§10.3：体不得包含控制转移——解释器层面
// 出现即报错；控制体限制的静态检查在语义层）。
func (in *Interp) runDeferBody(d *xfront.DeferStmt, sc *scope) {
	defer func() {
		if r := recover(); r != nil {
			switch r.(type) {
			case ctrlReturn, ctrlBreak, ctrlContinue, ctrlErr:
				panic(runtimeErr{"defer/errdefer 体不得包含 return/break/continue/try（S1 §10.3）"})
			default:
				panic(r)
			}
		}
	}()
	if d.Block != nil {
		in.execBlock(d.Block, newScope(sc))
		return
	}
	in.exec(d.Stmt, sc, nil)
}

func (in *Interp) exec(st xfront.Stmt, sc *scope, defers *[]ditem) {
	switch n := st.(type) {
	case *xfront.EmptyStmt:
	case *xfront.ExprStmt:
		in.eval(n.X, sc)
	case *xfront.LocalDeclStmt:
		v := in.zeroOf(n.Type)
		if n.Init != nil {
			v = in.eval(n.Init, sc)
		}
		sc.defineTyped(n.Name, n.Type, v)
	case *xfront.AssignStmt:
		v := in.eval(n.Value, sc)
		if n.Op != "=" {
			cur := in.eval(n.Target, sc)
			v = arith(n.P, strings.TrimSuffix(n.Op, "="), cur, v)
		}
		in.assignTo(n.Target, v, sc)
	case *xfront.IncDecStmt:
		cur := in.eval(n.Target, sc)
		op := "+"
		if n.Op == "--" {
			op = "-"
		}
		in.assignTo(n.Target, arith(n.P, op, cur, &Value{K: vInt, I: 1}), sc)
	case *xfront.ReturnStmt:
		var v *Value = &Value{K: vNull}
		if n.Value != nil {
			v = in.eval(n.Value, sc)
		}
		panic(ctrlReturn{v})
	case *xfront.ThrowStmt:
		v := in.eval(n.Value, sc)
		panic(fatal{format(v)}) // §10.4：fatal 不执行 defer
	case *xfront.IfStmt:
		if truthy(in.eval(n.Cond, sc), n.P) {
			in.execBlock(n.Then, newScope(sc))
		} else if n.Else != nil {
			if eb, ok := n.Else.(*xfront.Block); ok {
				in.execBlock(eb, newScope(sc))
			} else {
				in.exec(n.Else, sc, defers)
			}
		}
	case *xfront.WhileStmt:
		lbl := in.label // 标签只属于紧随其后的这一层循环（§6.10）
		in.label = ""
		for truthy(in.eval(n.Cond, sc), n.P) {
			if in.loopBody(n.Body, sc, lbl) {
				break
			}
		}
	case *xfront.DoWhileStmt:
		lbl := in.label
		in.label = ""
		for {
			if in.loopBody(n.Body, sc, lbl) {
				break
			}
			if !truthy(in.eval(n.Cond, sc), n.P) {
				break
			}
		}
	case *xfront.ForStmt:
		// for-in（§6.7）：区间（a..<b 半开、a...b 闭）或容器源（T[]、List<T>、Set<T>；
		// Map 不能直接遍历，§9 必须先取 keys()/values()）。
		lbl := in.label
		in.label = ""
		if rg, ok := n.Src.(*xfront.Binary); ok && (rg.Op == "..<" || rg.Op == "...") {
			lo := in.eval(rg.L, sc)
			hi := in.eval(rg.R, sc)
			for i := lo.I; i < hi.I || (rg.Op == "..." && i == hi.I); i++ {
				body := newScope(sc)
				body.define(n.Var, &Value{K: vInt, I: i})
				if in.loopBody(n.Body, body, lbl) {
					break
				}
			}
			break
		}
		src := in.eval(n.Src, sc)
		switch src.K {
		case vArr, vList:
			for _, item := range src.A {
				body := newScope(sc)
				body.define(n.Var, item)
				if in.loopBody(n.Body, body, lbl) {
					break
				}
			}
		case vSet:
			for _, item := range src.Set.elements() {
				body := newScope(sc)
				body.define(n.Var, item)
				if in.loopBody(n.Body, body, lbl) {
					break
				}
			}
		case vMap:
			panic(runtimeErr{"Map 不能直接遍历（§9：先取 keys() 或 values()）"})
		default:
			panic(runtimeErr{"for-in 源必须是区间、T[]、List<T> 或 Set<T>：" + src.typeName()})
		}
	case *xfront.SwitchStmt:
		val := in.eval(n.Value, sc)
		execCase := func(c *xfront.SwitchCase) {
			defer func() {
				if r := recover(); r != nil {
					if br, ok := r.(ctrlBreak); ok && br.label == "" {
						return // break 退出 switch（§6.9）
					}
					panic(r)
				}
			}()
			in.execBlock(&xfront.Block{P: n.P, Stmts: c.Stmts}, newScope(sc))
		}
		for _, c := range n.Cases { // case 按源码顺序求值，直到首个匹配（§6.8）
			if valuesEqual(in.eval(c.Expr, sc), val) {
				execCase(c)
				return // 无隐式贯穿
			}
		}
		if n.Default != nil {
			execCase(n.Default)
		}
	case *xfront.BreakStmt:
		panic(ctrlBreak{n.Label})
	case *xfront.ContinueStmt:
		panic(ctrlContinue{n.Label})
	case *xfront.DeferStmt:
		if defers == nil {
			panic(runtimeErr{"defer 只能出现在函数体/控制体中（S1 §10.3）"})
		}
		d := n
		*defers = append(*defers, ditem{fn: func() { in.runDeferBody(d, sc) }, errdef: d.Errdefer})
	case *xfront.LabeledStmt:
		if n.Stmt == nil {
			return
		}
		prev := in.label
		in.label = n.Label
		defer func() { in.label = prev }()
		in.exec(n.Stmt, sc, defers)
	case *xfront.GotoStmt:
		panic(runtimeErr{"goto 在解释器中不支持（结构化控制流覆盖常规路径；goto 语义在后续切片）"})
	case *xfront.Block:
		in.execBlock(n, newScope(sc))
	default:
		panic(runtimeErr{"解释器不支持的语句：" + xfront.PrintStmt(st)})
	}
}

// loopBody 执行循环体一轮：捕获 break/continue（§6.9），defer 由块级处理。
// label 是本层循环的标签（可空）；带标签信号仅匹配同名层，无标签信号匹配最近层。
// 返回 true 表示收到匹配本层的 break，调用点必须立即退出循环；
// continue 仍在本函数内消化（返回 false，进入下一轮）；不匹配的信号继续向上传播。
func (in *Interp) loopBody(b *xfront.Block, sc *scope, label string) (broke bool) {
	defer func() {
		if r := recover(); r != nil {
			switch sig := r.(type) {
			case ctrlBreak:
				if sig.label == "" || sig.label == label {
					broke = true
					return
				}
				panic(r)
			case ctrlContinue:
				if sig.label == "" || sig.label == label {
					return // 消化信号，进入下一轮
				}
				panic(r)
			default:
				panic(r)
			}
		}
	}()
	in.execBlock(b, sc)
	return
}

// ---------- 表达式求值 ----------

func (in *Interp) eval(e xfront.Expr, sc *scope) *Value {
	switch n := e.(type) {
	case *xfront.IntLitExpr:
		clean := strings.ReplaceAll(strings.TrimRight(n.Text, "LlUu"), "_", "")
		v, err := strconv.ParseInt(clean, n.Base, 64)
		if err != nil {
			panic(runtimeErr{"整数字面量超 Int 范围：" + n.Text})
		}
		return &Value{K: vInt, I: v}
	case *xfront.FloatLitExpr:
		f, err := strconv.ParseFloat(strings.ReplaceAll(strings.TrimSuffix(n.Text, "f"), "_", ""), 64)
		if err != nil {
			panic(runtimeErr{"浮点字面量非法：" + n.Text})
		}
		return &Value{K: vFloat, F: f}
	case *xfront.CharLitExpr:
		return &Value{K: vChar, C: n.Rune}
	case *xfront.BoolLit:
		return &Value{K: vBool, B: n.V}
	case *xfront.NullLit:
		return &Value{K: vNull}
	case *xfront.StrLitExpr:
		var b strings.Builder
		dynamic := false
		for _, p := range n.Parts {
			if p.Expr != nil {
				dynamic = true
				b.WriteString(format(in.eval(p.Expr, sc)))
			} else {
				b.WriteString(p.Text)
			}
		}
		s := b.String()
		if dynamic { // 插值结果每次都是新对象
			return &Value{K: vStr, S: s}
		}
		// 纯字面量驻留：同源码字面量共享对象，使 === 按对象身份可观察（§2.8）。
		if in.strLit == nil {
			in.strLit = map[string]*Value{}
		}
		if v, ok := in.strLit[s]; ok {
			return v
		}
		v := &Value{K: vStr, S: s}
		in.strLit[s] = v
		return v
	case *xfront.Paren:
		return in.eval(n.X, sc)
	case *xfront.IdentExpr:
		switch n.Name {
		case "true":
			return &Value{K: vBool, B: true}
		case "false":
			return &Value{K: vBool, B: false}
		}
		if v, ok := sc.lookup(n.Name); ok {
			return v
		}
		// §5.8：方法/字段初值中的裸字段名按 self 字段解析（局部/参数优先）。
		if v, ok := in.selfField(sc, n.Name); ok {
			return v
		}
		if _, isFn := in.funcs[n.Name]; isFn {
			// 具名函数作为值（§7.7：apply(add, 1)）——包装为闭包值
			return &Value{K: vClosure, Clo: &clov{top: n.Name}}
		}
		// §7.1：静态字段初始化式/静态方法中的裸静态字段名。
		if in.staticCtx != nil {
			if v, ok := in.findStaticField(in.staticCtx, n.Name); ok {
				return v
			}
		}
		panic(runtimeErr{"未定义的名称：" + n.Name})
	case *xfront.Unary:
		switch n.Op {
		case "try":
			x := in.eval(n.X, sc) // §10.2
			if !x.isResult() {
				panic(runtimeErr{"try 只能作用于 Result（S1 §10.2）"})
			}
			if x.R.ok {
				return x.R.v
			}
			panic(ctrlErr{x.R}) // 失败：从当前函数返回 Err
		case "!":
			return &Value{K: vBool, B: !truthy(in.eval(n.X, sc), n.P)}
		case "-":
			v := in.eval(n.X, sc)
			if v.K == vInt {
				return &Value{K: vInt, I: -v.I}
			}
			return &Value{K: vFloat, F: -v.F}
		case "+":
			return in.eval(n.X, sc)
		case "~":
			v := in.eval(n.X, sc)
			return &Value{K: vInt, I: ^v.I}
		}
	case *xfront.Binary:
		return in.evalBinary(n, sc)
	case *xfront.Ternary:
		if truthy(in.eval(n.Cond, sc), n.P) {
			return in.eval(n.Then, sc)
		}
		return in.eval(n.Else, sc)
	case *xfront.Tuple:
		return in.evalTuple(n, sc)
	case *xfront.ArrayLit:
		return in.evalArrayLit(n, sc)
	case *xfront.MapLit:
		return in.evalMapLit(n, sc)
	case *xfront.Call:
		return in.evalCall(n, sc)
	case *xfront.Member:
		return in.evalMember(n, sc)
	case *xfront.Index:
		return in.evalIndex(n, sc)
	case *xfront.TupleMember:
		return in.evalTupleMember(n, sc)
	case *xfront.NewArray:
		return in.evalNewArray(n, sc)
	case *xfront.New:
		return in.evalNew(n, sc)
	case *xfront.Lambda:
		return in.evalLambda(n, sc)
	}
	panic(runtimeErr{"解释器不支持的表达式：" + xfront.PrintExpr(e)})
}

func (in *Interp) evalBinary(n *xfront.Binary, sc *scope) *Value {
	if _, isTypeAs := n.R.(*xfront.TypeAsExpr); isTypeAs {
		return in.evalTypeAs(n, sc) // is / as / as?（§7.7）
	}
	switch n.Op {
	case "&&": // 短路（EXPR-01）
		if !truthy(in.eval(n.L, sc), n.P) {
			return &Value{K: vBool, B: false}
		}
		return &Value{K: vBool, B: truthy(in.eval(n.R, sc), n.P)}
	case "||":
		if truthy(in.eval(n.L, sc), n.P) {
			return &Value{K: vBool, B: true}
		}
		return &Value{K: vBool, B: truthy(in.eval(n.R, sc), n.P)}
	case "??": // 仅左侧为 null 时求值右侧（EXPR-01）
		l := in.eval(n.L, sc)
		if l.K != vNull {
			return l
		}
		return in.eval(n.R, sc)
	}
	l := in.eval(n.L, sc)
	r := in.eval(n.R, sc)
	switch n.Op {
	case "..<", "...":
		// 区间值只允许出现在 for-in 源位置（附录 A）；此处不再求值
		panic(runtimeErr{"区间表达式只允许出现在 for-in 的源位置（S1 §6.7）"})
	case "==":
		return &Value{K: vBool, B: valuesEqual(l, r)}
	case "!=":
		return &Value{K: vBool, B: !valuesEqual(l, r)}
	case "===":
		return &Value{K: vBool, B: identical(l, r)}
	case "!==":
		return &Value{K: vBool, B: !identical(l, r)}
	case "+":
		if l.K == vStr || r.K == vStr { // String + String（§5.4 也允许常量域）
			return &Value{K: vStr, S: format(l) + format(r)}
		}
	case "is", "as", "as?":
		panic(runtimeErr{"解释器暂不支持类型运算 " + n.Op})
	}
	return arith(n.P, n.Op, l, r)
}

// arith 数值与比较运算（运算符语义 S1 §7.3；除零 fatal §10.4）。
func arith(p xfront.Pos, op string, l, r *Value) *Value {
	bothInt := l.K == vInt && r.K == vInt
	switch op {
	case "+", "-", "*", "/", "%":
		if !bothInt {
			if l.K == vFloat && r.K == vFloat {
				a, b := l.F, r.F
				switch op {
				case "+":
					return &Value{K: vFloat, F: a + b}
				case "-":
					return &Value{K: vFloat, F: a - b}
				case "*":
					return &Value{K: vFloat, F: a * b}
				case "/":
					if b == 0 {
						panic(fatal{"除零"})
					}
					return &Value{K: vFloat, F: a / b}
				}
			}
			panic(runtimeErr{fmt.Sprintf("运算 %s 的操作数类型不符：%s %s %s", op, l.typeName(), op, r.typeName())})
		}
		a, b := l.I, r.I
		switch op {
		case "+":
			return &Value{K: vInt, I: a + b}
		case "-":
			return &Value{K: vInt, I: a - b}
		case "*":
			return &Value{K: vInt, I: a * b}
		case "/":
			if b == 0 {
				panic(fatal{"除零"})
			}
			return &Value{K: vInt, I: a / b}
		case "%":
			if b == 0 {
				panic(fatal{"除零"})
			}
			return &Value{K: vInt, I: a % b}
		}
	case "<", ">", "<=", ">=":
		if l.K == vEnum && r.K == vEnum && l.E == r.E {
			return boolOf(op, intCmp(l.I, r.I)) // S2 §8.2：简单枚举按底层值顺序比较
		}
		if l.K == vStr && r.K == vStr {
			cmp := strings.Compare(l.S, r.S)
			return boolOf(op, cmp)
		}
		if bothInt {
			return boolOf(op, intCmp(l.I, r.I))
		}
		if l.K == vFloat && r.K == vFloat {
			return boolOf(op, floatCmp(l.F, r.F))
		}
	case "&", "|", "^", "<<", ">>":
		if bothInt {
			switch op {
			case "&":
				return &Value{K: vInt, I: l.I & r.I}
			case "|":
				return &Value{K: vInt, I: l.I | r.I}
			case "^":
				return &Value{K: vInt, I: l.I ^ r.I}
			case "<<":
				if r.I < 0 || r.I > 63 {
					panic(fatal{"移位越界"})
				}
				return &Value{K: vInt, I: l.I << uint(r.I)}
			case ">>":
				if r.I < 0 || r.I > 63 {
					panic(fatal{"移位越界"})
				}
				return &Value{K: vInt, I: l.I >> uint(r.I)}
			}
		}
	}
	panic(runtimeErr{fmt.Sprintf("运算 %s 的操作数类型不符：%s %s %s", op, l.typeName(), op, r.typeName())})
}

func intCmp(a, b int64) int {
	switch {
	case a < b:
		return -1
	case a > b:
		return 1
	}
	return 0
}

func floatCmp(a, b float64) int {
	switch {
	case a < b:
		return -1
	case a > b:
		return 1
	}
	return 0
}

func boolOf(op string, cmp int) *Value {
	switch op {
	case "<":
		return &Value{K: vBool, B: cmp < 0}
	case ">":
		return &Value{K: vBool, B: cmp > 0}
	case "<=":
		return &Value{K: vBool, B: cmp <= 0}
	case ">=":
		return &Value{K: vBool, B: cmp >= 0}
	}
	return &Value{K: vBool, B: false}
}

// valuesEqual 相等语义（§7.3：同类型比较；Result 无 ==，§10.1）。
func valuesEqual(l, r *Value) bool {
	if l.K == vNull || r.K == vNull {
		return l.K == vNull && r.K == vNull
	}
	if l.K != r.K {
		return false
	}
	switch l.K {
	case vBool:
		return l.B == r.B
	case vInt:
		return l.I == r.I
	case vFloat:
		return l.F == r.F
	case vChar:
		return l.C == r.C
	case vStr:
		return l.S == r.S
	case vTuple: // §2.11：逐元素使用元素类型的相等语义
		if len(l.A) != len(r.A) {
			return false
		}
		for i := range l.A {
			if !valuesEqual(l.A[i], r.A[i]) {
				return false
			}
		}
		return true
	case vEnum: // S2 §8.2：简单枚举按底层值比较（名义类型必须相同）
		return l.E == r.E && l.I == r.I
	case vStruct: // S2 §3.3：结构体没有对象身份，== 逐字段按值比较
		return structEqual(l.St, r.St)
	case vArr, vList, vMap, vSet, vClosure, vObj:
		return l == r // §2.8：引用类型 `==` 默认按对象身份
	}
	return false
}

// identical 严格同一性（§2.8、§2.11）：元组逐元素比较同一性；
// 引用类型比较引用身份，值类型比较值；null === null 为 true。
func identical(l, r *Value) bool {
	if l.K == vNull || r.K == vNull {
		return l.K == vNull && r.K == vNull
	}
	if l.K != r.K {
		return false
	}
	switch l.K {
	case vTuple:
		if len(l.A) != len(r.A) {
			return false
		}
		for i := range l.A {
			if !identical(l.A[i], r.A[i]) {
				return false
			}
		}
		return true
	case vEnum: // 简单枚举是值类型：=== 按底层值
		return l.E == r.E && l.I == r.I
	case vStruct: // S2 §3.3：=== 与 == 相同（逐字段）
		return structEqual(l.St, r.St)
	case vStr, vArr, vList, vMap, vSet, vClosure, vObj: // 引用类型：对象身份（§2.8：String === 按对象身份）
		return l == r
	}
	return valuesEqual(l, r)
}

// selectFunc 选择重载/泛型候选（§8.2）：显式类型实参只匹配类型参数个数相同的泛型候选；
// 无显式实参时优先非泛型（更具体），否则取首个参数个数相同的候选。
// 解释器是动态路径，不做静态类型合一；参数个数是可判定过滤条件（§4.4 既有口径）。
func (in *Interp) selectFunc(name string, fns []*xfront.TopFunc, typeArgs []xfront.TypeRef, argc int) *xfront.TopFunc {
	if len(typeArgs) > 0 {
		for _, f := range fns {
			if len(f.Params) == argc && len(f.TypePars) == len(typeArgs) {
				return f
			}
		}
		panic(runtimeErr{fmt.Sprintf("函数 %s 没有匹配 %d 个类型实参的重载（§8.2）", name, len(typeArgs))})
	}
	for _, f := range fns {
		if len(f.Params) == argc && len(f.TypePars) == 0 {
			return f
		}
	}
	for _, f := range fns {
		if len(f.Params) == argc {
			return f
		}
	}
	panic(runtimeErr{fmt.Sprintf("函数 %s 无 %d 参数的重载", name, argc)})
}

func (in *Interp) evalCall(n *xfront.Call, sc *scope) *Value {
	// Ok/Err 构造器（§10.1）。
	if id, ok := n.Callee.(*xfront.IdentExpr); ok && (id.Name == "Ok" || id.Name == "Err") {
		if id.Name == "Ok" {
			if len(n.Args) == 0 {
				return &Value{K: vResult, R: &resv{ok: true, v: &Value{K: vNull}}} // Result<void,E>
			}
			return &Value{K: vResult, R: &resv{ok: true, v: in.eval(n.Args[0], sc)}}
		}
		if len(n.Args) == 0 {
			panic(runtimeErr{"Err 必须带错误值（§10.1：E 不能是 void）"})
		}
		return &Value{K: vResult, R: &resv{ok: false, e: in.eval(n.Args[0], sc)}}
	}
	// 方法调用形态：recv.method(args)（§10.1 Result 成员全部为方法）。
	if mem, ok := n.Callee.(*xfront.Member); ok {
		// S2 §5.4：`super.m(...)` 从父类起点静态查找。
		if id, ok := mem.X.(*xfront.IdentExpr); ok && id.Name == "super" {
			self, found := sc.lookup("self")
			if !found || self.K != vObj {
				panic(runtimeErr{"super 只能在实例方法中使用（§5.4）"})
			}
			args := make([]*Value, len(n.Args))
			for i, a := range n.Args {
				args[i] = in.eval(a, sc)
			}
			v, err := in.callMethodFrom(in.superBase(), self.O, mem.Name, args, n.P)
			if err != nil {
				panic(runtimeErr{err.Error()})
			}
			return v
		}
		// S2 §7.2：`Class.staticMethod(...)`；类名不是运行期变量。
		if id, ok := mem.X.(*xfront.IdentExpr); ok {
			if cls, found := in.findClass(id.Name); found {
				if len(in.findStaticMethods(cls, mem.Name)) == 0 {
					panic(runtimeErr{"实例方法必须通过实例调用：" + id.Name + "." + mem.Name})
				}
				args := make([]*Value, len(n.Args))
				for i, a := range n.Args {
					args[i] = in.eval(a, sc)
				}
				v, err := in.callStatic(cls, mem.Name, args, n.P)
				if err != nil {
					panic(runtimeErr{err.Error()})
				}
				return v
			}
		}
		recv := in.eval(mem.X, sc)
		if mem.NullSafe && recv.K == vNull {
			return &Value{K: vNull}
		}
		if recv.K == vObj {
			args0 := make([]*Value, len(n.Args))
			for i, a := range n.Args {
				args0[i] = in.eval(a, sc)
			}
			v, err := in.dispatchCall(sc, mem.X, recv.O, mem.Name, args0, n.P)
			if err != nil {
				panic(runtimeErr{err.Error()})
			}
			return v
		}
		if recv.K == vStruct {
			args0 := make([]*Value, len(n.Args))
			for i, a := range n.Args {
				args0[i] = in.eval(a, sc)
			}
			v, err := in.callStructMethod(recv.St, mem.Name, args0, n.P)
			if err != nil {
				panic(runtimeErr{err.Error()})
			}
			return v
		}
		if !recv.isResult() {
			args0 := make([]*Value, len(n.Args))
			for i, a := range n.Args {
				args0[i] = in.eval(a, sc)
			}
			if v, hit := in.callValueMethod(recv, mem.Name, args0, n.P); hit {
				return v
			}
			panic(runtimeErr{"该类型没有成员方法 " + mem.Name + "：" + recv.typeName()})
		}
		args := make([]*Value, len(n.Args))
		for i, a := range n.Args {
			args[i] = in.eval(a, sc)
		}
		switch mem.Name {
		case "isOk":
			return &Value{K: vBool, B: recv.R.ok}
		case "isErr":
			return &Value{K: vBool, B: !recv.R.ok}
		case "value":
			if !recv.R.ok {
				panic(fatal{"Err 上读取 value（§10.1：运行时 panic）"})
			}
			return recv.R.v
		case "error":
			if recv.R.ok {
				panic(fatal{"Ok 上读取 error（§10.1：运行时 panic）"})
			}
			return recv.R.e
		case "unwrapOr":
			if recv.R.ok {
				return recv.R.v
			}
			if len(args) != 1 {
				panic(runtimeErr{"unwrapOr 恰好接受 1 个参数"})
			}
			return args[0]
		}
		panic(runtimeErr{"未知的 Result 成员：" + mem.Name})
	}
	if id, ok := n.Callee.(*xfront.IdentExpr); ok {
		if _, isFn := in.funcs[id.Name]; !isFn {
			if cv, found2 := sc.lookup(id.Name); found2 && cv.K == vClosure {
				args := make([]*Value, len(n.Args))
				for i, a := range n.Args {
					args[i] = in.eval(a, sc)
				}
				return in.callClosure(cv.Clo, args)
			}
		}
		if fns, found := in.funcs[id.Name]; found {
			args := make([]*Value, len(n.Args))
			for i, a := range n.Args {
				args[i] = in.eval(a, sc)
			}
			f := in.selectFunc(id.Name, fns, n.TypeArgs, len(args))
			v, err := in.call(f, args)
			if err != nil {
				panic(runtimeErr{err.Error()})
			}
			return v
		}
		// §7.2：静态方法内的裸静态方法名。
		if in.staticCtx != nil {
			if cands := in.findStaticMethods(in.staticCtx, id.Name); len(cands) > 0 {
				args := make([]*Value, len(n.Args))
				for i, a := range n.Args {
					args[i] = in.eval(a, sc)
				}
				v, err := in.callStatic(in.staticCtx, id.Name, args, n.P)
				if err != nil {
					panic(runtimeErr{err.Error()})
				}
				return v
			}
		}
		if id.Name == "print" || id.Name == "str" { // 内置函数（2/≤3）
			if len(n.Args) != 1 {
				panic(runtimeErr{id.Name + " 恰好接受 1 个参数"})
			}
			if id.Name == "print" {
				fmt.Fprintln(in.out, format(in.eval(n.Args[0], sc)))
				return &Value{K: vNull}
			}
			return &Value{K: vStr, S: format(in.eval(n.Args[0], sc))}
		}
		// §5.8：类内裸方法名解析到 self 的实例方法。
		// §3.4：结构体方法内裸方法名。
		if sv, ok := sc.lookup("self"); ok && sv.K == vStruct {
			if len(in.findStructMethod(sv.St.decl, id.Name)) > 0 {
				args := make([]*Value, len(n.Args))
				for i, a := range n.Args {
					args[i] = in.eval(a, sc)
				}
				v, err := in.callStructMethod(sv.St, id.Name, args, n.P)
				if err != nil {
					panic(runtimeErr{err.Error()})
				}
				return v
			}
		}
		if sv, ok := sc.lookup("self"); ok && sv.K == vObj {
			start := sv.O.cls
			if cur := in.currentClass(); cur != nil {
				start = cur // §5.6：self.method() 静态派发到当前声明类
			}
			if len(in.findMethodsFrom(start, id.Name)) > 0 {
				args := make([]*Value, len(n.Args))
				for i, a := range n.Args {
					args[i] = in.eval(a, sc)
				}
				v, err := in.callMethodFrom(start, sv.O, id.Name, args, n.P)
				if err != nil {
					panic(runtimeErr{err.Error()})
				}
				return v
			}
		}
		panic(runtimeErr{"未定义的函数：" + id.Name})
	}
	panic(runtimeErr{"解释器暂不支持非常量可调用表达式"})
}

func (in *Interp) evalMember(n *xfront.Member, sc *scope) *Value {
	if id, ok := n.X.(*xfront.IdentExpr); ok {
		// S2 §5.4：`super.field` 从父类链读字段。
		if id.Name == "super" {
			if f, obj, hit := in.superField(sc, n.Name); hit {
				return obj.fields[fieldKey(f)]
			}
			panic(runtimeErr{"父类没有字段 " + n.Name + "（§5.4）"})
		}
		// S2 §7.1：`Class.field` 静态字段。
		if cls, ok := in.findClass(id.Name); ok {
			if v, hit := in.findStaticField(cls, n.Name); hit {
				return v
			}
		}
		// S2 §8.4：`Enum.Item` 项访问（枚举类型名不是运行期变量）。
		if d, ok := in.enums[id.Name]; ok {
			return in.enumItem(d, n.Name, n.P)
		}
	}
	x := in.eval(n.X, sc)
	if n.NullSafe && x.K == vNull {
		return &Value{K: vNull} // ?. 空传播（§7.5）
	}
	if x.K == vObj {
		return in.readMember(x.O, n.Name, n.P) // 实例字段（§7.4）
	}
	if x.K == vStruct {
		return in.readStructMember(x.St, n.Name) // 结构体字段（§3）
	}
	panic(runtimeErr{"解释器不支持的裸成员访问（Result 成员是方法，须以 r.isOk() 形式调用）"})
}

// assignTo 把值写入可赋值位置（§6.4）。
func (in *Interp) assignTo(target xfront.Expr, v *Value, sc *scope) {
	switch t := target.(type) {
	case *xfront.IdentExpr:
		if !sc.assign(t.Name, v) {
			if !in.writeSelfField(sc, t.Name, v) {
				if in.staticCtx == nil || !in.writeStaticField(in.staticCtx, t.Name, v) {
					panic(runtimeErr{"向未定义的名称赋值：" + t.Name})
				}
			}
		}
		return
	case *xfront.Index:
		x := in.eval(t.X, sc)
		idx := in.eval(t.Idx, sc)
		switch x.K {
		case vArr:
			i := int(idx.I)
			if idx.K != vInt || i < 0 || i >= len(x.A) {
				panic(fatal{fmt.Sprintf("数组下标越界：len=%d, idx=%s", len(x.A), format(idx))})
			}
			x.A[i] = cloneTupleValue(v) // §2.11：存入容器复制整个元组
			return
		case vList:
			i := int(idx.I)
			if idx.K != vInt || i < 0 || i >= len(x.A) {
				panic(fatal{fmt.Sprintf("List 下标越界：len=%d, idx=%s", len(x.A), format(idx))})
			}
			x.A[i] = cloneTupleValue(v) // §2.11：存入容器复制整个元组
			return
		}
		panic(runtimeErr{"该类型不支持下标赋值：" + x.typeName()})
	case *xfront.TupleMember:
		recv := in.eval(t.X, sc)
		if recv.K != vTuple {
			panic(runtimeErr{"`.N` 元素赋值只用于元组：" + recv.typeName()})
		}
		if t.Index < 0 || t.Index >= len(recv.A) {
			panic(fatal{fmt.Sprintf("元组下标越界：len=%d, idx=%d（§2.11）", len(recv.A), t.Index)})
		}
		recv.A[t.Index] = cloneTupleValue(v)
		return
	case *xfront.Member:
		// S2 §5.4：`super.field = v` 写父类链字段。
		if id, ok := t.X.(*xfront.IdentExpr); ok && id.Name == "super" {
			if f, obj, hit := in.superField(sc, t.Name); hit {
				obj.fields[fieldKey(f)] = v
				return
			}
			panic(runtimeErr{"父类没有字段 " + t.Name + "（§5.4）"})
		}
		// S2 §7.1：`Class.staticField = v`。
		if id, ok := t.X.(*xfront.IdentExpr); ok {
			if cls, found := in.findClass(id.Name); found && in.writeStaticField(cls, t.Name, v) {
				return
			}
		}
		recv := in.eval(t.X, sc)
		if recv.K == vObj {
			in.writeMember(recv.O, t.Name, v)
			return
		}
		if recv.K == vStruct {
			in.writeStructMember(recv.St, t.Name, v)
			return
		}
		if recv.K == vNull {
			panic(fatal{"对 null 赋值成员（§10.1 运行时 panic）"})
		}
		panic(runtimeErr{"该类型不支持成员赋值：" + recv.typeName()})
	}
	panic(runtimeErr{"解释器只支持对局部/顶层变量/数组元素/实例字段赋值"})
}

func truthy(v *Value, p xfront.Pos) bool {
	if v.K != vBool {
		panic(runtimeErr{"条件必须是 Bool（S1 §6.12）"})
	}
	return v.B
}
