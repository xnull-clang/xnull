package xfront

// 表达式与类型 AST（S1 附录 A：Expression 至 InterpString、TypeRef）。
// AST 打印采用 S 表达式形式，供 --emit ast 与用例断言。

// Expr 是表达式节点。
type Expr interface {
	Pos() Pos
	exprNode()
}

// TypeRef 是类型引用节点。
type TypeRef interface {
	Pos() Pos
	typeNode()
}

// Stmt 是语句节点。4b 仅提供闭包体内需要的最小集，
// 完整语句文法在 4c（S1 附录 A：Statement）实现。
type Stmt interface {
	Pos() Pos
	stmtNode()
}

// ---------- 字面量与名称 ----------

// IdentExpr 是标识符引用；true/false/null 在主表达式位置按字面量解析（S1 §1.3）。
type IdentExpr struct {
	P    Pos
	Name string
}

// IntLitExpr 是整数字面量；Text 保留源文本（含进制前缀与后缀）。
type IntLitExpr struct {
	P      Pos
	Text   string
	Base   int
	Suffix string
}

// FloatLitExpr 是浮点字面量。
type FloatLitExpr struct {
	P          Pos
	Text       string
	HasSuffixF bool
}

// CharLitExpr 是字符字面量。
type CharLitExpr struct {
	P    Pos
	Rune rune
}

// BoolLit 是 true / false。
type BoolLit struct {
	P Pos
	V bool
}

// NullLit 是 null。
type NullLit struct{ P Pos }

// StrLitExpr 是字符串字面量。Interps 为插值串中按源码顺序解析出的子表达式；
// 静态文本片段与插值表达式交错（S1 §1.4.4、§7.8）。
type StrLitExpr struct {
	P     Pos
	Kind  StrKind
	Parts []StrPart // 按源码顺序
}

// StrPart 是插值串的一部分。
type StrPart struct {
	Text string // Text != "" 时为静态文本
	Expr Expr   // Expr != nil 时为插值表达式
}

// ---------- 复合字面量 ----------

// Paren 是括号表达式 `(e)`（不是元组，S1 附录 A 文法说明）。
type Paren struct {
	P Pos
	X Expr
}

// Tuple 是元组字面量，至少两个元素（S1 §7.1）。
type Tuple struct {
	P     Pos
	Elems []Expr
}

// ArrayLit 是数组/集合字面量 `[a, b, c]`。
type ArrayLit struct {
	P     Pos
	Elems []Expr
}

// MapLit 是 Map 字面量；空 Map 为 `[:]`。
type MapLit struct {
	P    Pos
	Keys []Expr
	Vals []Expr
}

// ---------- 运算 ----------

// Unary 是前缀运算：! - + ~ try（右结合，S1 §7.2）。
type Unary struct {
	P  Pos
	Op string
	X  Expr
}

// Binary 是二元运算。?? 的右结合由解析循环保证。
type Binary struct {
	P  Pos
	Op string
	L  Expr
	R  Expr
}

// Ternary 是三元运算 `c ? a : b`（右结合，S1 §7.2）。
type Ternary struct {
	P    Pos
	Cond Expr
	Then Expr
	Else Expr
}

// ---------- 后缀 ----------

// Member 是成员访问；NullSafe 为 true 表示 `?.`（S1 §7.5）。
type Member struct {
	P        Pos
	X        Expr
	Name     string
	NullSafe bool
}

// TupleMember 是元组元素访问 `pair.0`（S1 附录 A 文法说明）。
type TupleMember struct {
	P        Pos
	X        Expr
	Index    int
	NullSafe bool
}

// Call 是调用；TypeArgs 为显式泛型实参（可空）。
type Call struct {
	P        Pos
	Callee   Expr
	TypeArgs []TypeRef
	Args     []Expr
}

// Index 是下标访问 `a[i]`。
type Index struct {
	P   Pos
	X   Expr
	Idx Expr
}

// ---------- 构造与闭包 ----------

// New 是对象构造 `new T(args)`。
type New struct {
	P    Pos
	Type TypeRef
	Args []Expr
}

// NewArray 是固定数组创建 `new T[count]`（S1 §7.1）。
type NewArray struct {
	P     Pos
	Type  TypeRef
	Count Expr
}

// LambdaParam 是闭包参数（S1 §7.7：类型必须显式，可写 final）。
type LambdaParam struct {
	P     Pos
	Type  TypeRef
	Name  string
	Final bool
}

// Lambda 是闭包 `(参数) -> 体`；Single 为 true 表示单表达式体
// （`-> e` 是 `-> { return e; }` 的缩写，S1 §7.7）。
type Lambda struct {
	P      Pos
	Params []LambdaParam
	Block  *Block // Block 与 ExprBody 二选一
	ExprB  Expr
	Single bool
}

// Block 是语句块（4b 最小实现，仅闭包体；完整语句文法在 4c）。
type Block struct {
	P     Pos
	Stmts []Stmt
}

// ReturnStmt 是 `return [表达式] [;]`。
type ReturnStmt struct {
	P     Pos
	Value Expr // 可空
}

// ExprStmt 是表达式语句 `表达式 [;]`。
type ExprStmt struct {
	P Pos
	X Expr
}

// ---------- 语句（S1 §5—§6、附录 A Statement） ----------

// LocalDeclStmt 是局部声明（S1 §5.1，一条语句只声明一个变量）：
// `Type name [= e];` / `final Type name [= e];` / `const Type name = e;` /
// `var name = e;`（var 与 const 必有初始化式，语义层检查）。
type LocalDeclStmt struct {
	P     Pos
	Final bool
	Const bool
	Var   bool
	Type  TypeRef // Var 形态为 nil
	Name  string
	Init  Expr // 可空（确定赋值之后补）
}

// AssignStmt 是赋值语句（S1 §6.4，不是表达式，不得串联）。
// Op ∈ = += -= *= /= %= &= |= ^= <<= >>=。
type AssignStmt struct {
	P      Pos
	Target Expr // Identifier | MemberExpr | IndexExpr（附录 A Assignable）
	Op     string
	Value  Expr
}

// IncDecStmt 是自增/自减语句（只作为语句，S1 §6.1）。
type IncDecStmt struct {
	P      Pos
	Target Expr
	Op     string // "++" / "--"
	Prefix bool
}

// IfStmt 是 `if cond { } [else …]`；条件不写括号，体必须是花括号体（S1 §6.5）。
type IfStmt struct {
	P    Pos
	Cond Expr
	Then *Block
	Else Stmt // IfStmt 或 *Block，可空
}

// WhileStmt 是 `while cond { }`（S1 §6.6）。
type WhileStmt struct {
	P    Pos
	Cond Expr
	Body *Block
}

// DoWhileStmt 是 `do { } while cond [;]`（S1 §6.6）。
type DoWhileStmt struct {
	P    Pos
	Body *Block
	Cond Expr
}

// ForStmt 是 `for name in src { }`（S1 §6.7：数组/List/Set 与区间）。
type ForStmt struct {
	P    Pos
	Var  string
	Src  Expr // 区间表达式只允许在此位置（语义层检查，附录 A 文法说明末条）
	Body *Block
}

// SwitchCase 是一个 case/default 子句（独立作用域，S1 §6.8）。
type SwitchCase struct {
	Expr    Expr // Default 时为 nil
	Stmts   []Stmt
	Default bool
}

// SwitchStmt 是 `switch value { case v: … default: … }`；无隐式贯穿（S1 §6.8）。
type SwitchStmt struct {
	P       Pos
	Value   Expr
	Cases   []*SwitchCase
	Default *SwitchCase
}

// DeferStmt 是 `defer Body` / `errdefer Body`；Body = Block | Statement（附录 A）。
type DeferStmt struct {
	P        Pos
	Errdefer bool
	Block    *Block // Block 与 Stmt 二选一
	Stmt     Stmt
}

// BreakStmt / ContinueStmt / GotoStmt 带可选标签（S1 §6.9、§6.10）。
type BreakStmt struct {
	P     Pos
	Label string
}

type ContinueStmt struct {
	P     Pos
	Label string
}

type GotoStmt struct {
	P     Pos
	Label string
}

// LabeledStmt 是 `name: Statement`（S1 §6.10：标签后跟一条语句，可为空语句）。
type LabeledStmt struct {
	P     Pos
	Label string
	Stmt  Stmt
}

// ThrowStmt 是 `throw value`（S1 §6.9：fatal/panic，不是可恢复错误）。
type ThrowStmt struct {
	P     Pos
	Value Expr
}

// EmptyStmt 是 `;`（S1 §6.11）。
type EmptyStmt struct{ P Pos }

// ---------- 类型引用 ----------

// NamedType 是（限定）命名类型 `pkg.Type<Args>`；void 以 NamedType 表示。
type NamedType struct {
	P    Pos
	Qual []string
	Args []TypeRef
}

// SuffixedType 是带后缀的类型；后缀按源码顺序为 "[]" 或 "?"
// （T?[] 与 T[]? 不同，S1 附录 A 文法说明）。
type SuffixedType struct {
	P        Pos
	Base     TypeRef
	Suffixes []string
}

// FuncTypeRef 是函数类型 `Ret(参数...)`；参数是裸 TypeRef（S1 附录 A）。
type FuncTypeRef struct {
	P      Pos
	Ret    TypeRef
	Params []TypeRef
}

// TupleTypeRef 是元组类型，至少两个元素（S1 附录 A 文法说明）。
type TupleTypeRef struct {
	P     Pos
	Elems []TypeRef
}

// ---------- 接口实现 ----------

func (n *IdentExpr) Pos() Pos    { return n.P }
func (n *IntLitExpr) Pos() Pos   { return n.P }
func (n *FloatLitExpr) Pos() Pos { return n.P }
func (n *CharLitExpr) Pos() Pos  { return n.P }
func (n *BoolLit) Pos() Pos      { return n.P }
func (n *NullLit) Pos() Pos      { return n.P }
func (n *StrLitExpr) Pos() Pos   { return n.P }
func (n *Paren) Pos() Pos        { return n.P }
func (n *Tuple) Pos() Pos        { return n.P }
func (n *ArrayLit) Pos() Pos     { return n.P }
func (n *MapLit) Pos() Pos       { return n.P }
func (n *Unary) Pos() Pos        { return n.P }
func (n *Binary) Pos() Pos       { return n.P }
func (n *Ternary) Pos() Pos      { return n.P }
func (n *Member) Pos() Pos       { return n.P }
func (n *TupleMember) Pos() Pos  { return n.P }
func (n *Call) Pos() Pos         { return n.P }
func (n *Index) Pos() Pos        { return n.P }
func (n *New) Pos() Pos          { return n.P }
func (n *NewArray) Pos() Pos     { return n.P }
func (n *Lambda) Pos() Pos       { return n.P }

func (*IdentExpr) exprNode()    {}
func (*IntLitExpr) exprNode()   {}
func (*FloatLitExpr) exprNode() {}
func (*CharLitExpr) exprNode()  {}
func (*BoolLit) exprNode()      {}
func (*NullLit) exprNode()      {}
func (*StrLitExpr) exprNode()   {}
func (*Paren) exprNode()        {}
func (*Tuple) exprNode()        {}
func (*ArrayLit) exprNode()     {}
func (*MapLit) exprNode()       {}
func (*Unary) exprNode()        {}
func (*Binary) exprNode()       {}
func (*Ternary) exprNode()      {}
func (*Member) exprNode()       {}
func (*TupleMember) exprNode()  {}
func (*Call) exprNode()         {}
func (*Index) exprNode()        {}
func (*New) exprNode()          {}
func (*NewArray) exprNode()     {}
func (*Lambda) exprNode()       {}

func (n *NamedType) Pos() Pos    { return n.P }
func (n *SuffixedType) Pos() Pos { return n.P }
func (n *FuncTypeRef) Pos() Pos  { return n.P }
func (n *TupleTypeRef) Pos() Pos { return n.P }

func (*NamedType) typeNode()    {}
func (*SuffixedType) typeNode() {}
func (*FuncTypeRef) typeNode()  {}
func (*TupleTypeRef) typeNode() {}

func (*ReturnStmt) Pos() Pos    { return Pos{} }
func (*ExprStmt) Pos() Pos      { return Pos{} }
func (*LocalDeclStmt) Pos() Pos { return Pos{} }
func (*AssignStmt) Pos() Pos    { return Pos{} }
func (*IncDecStmt) Pos() Pos    { return Pos{} }
func (*IfStmt) Pos() Pos        { return Pos{} }
func (*WhileStmt) Pos() Pos     { return Pos{} }
func (*DoWhileStmt) Pos() Pos   { return Pos{} }
func (*ForStmt) Pos() Pos       { return Pos{} }
func (*SwitchStmt) Pos() Pos    { return Pos{} }
func (*SwitchCase) Pos() Pos    { return Pos{} }
func (*DeferStmt) Pos() Pos     { return Pos{} }
func (*BreakStmt) Pos() Pos     { return Pos{} }
func (*ContinueStmt) Pos() Pos  { return Pos{} }
func (*GotoStmt) Pos() Pos      { return Pos{} }
func (*LabeledStmt) Pos() Pos   { return Pos{} }
func (*ThrowStmt) Pos() Pos     { return Pos{} }
func (*EmptyStmt) Pos() Pos     { return Pos{} }

func (*ReturnStmt) stmtNode()    {}
func (*ExprStmt) stmtNode()      {}
func (*LocalDeclStmt) stmtNode() {}
func (*AssignStmt) stmtNode()    {}
func (*IncDecStmt) stmtNode()    {}
func (*IfStmt) stmtNode()        {}
func (*WhileStmt) stmtNode()     {}
func (*DoWhileStmt) stmtNode()   {}
func (*ForStmt) stmtNode()       {}
func (*SwitchStmt) stmtNode()    {}
func (*SwitchCase) stmtNode()    {}
func (*DeferStmt) stmtNode()     {}
func (*BreakStmt) stmtNode()     {}
func (*ContinueStmt) stmtNode()  {}
func (*GotoStmt) stmtNode()      {}
func (*LabeledStmt) stmtNode()   {}
func (*ThrowStmt) stmtNode()     {}
func (*EmptyStmt) stmtNode()     {}

// Block 可作为语句出现在 else 分支与 defer 单语句体（附录 A Body = Block | Statement）。
func (n *Block) Pos() Pos { return n.P }
func (*Block) stmtNode()  {}
