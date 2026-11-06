package interp

import (
	"fmt"
	"sort"
	"strconv"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

// ---------- M2.4 解释器全量化：容器 / 元组 / 闭包 / is / as ----------

// mapv 是 Map 运行值。存储与迭代顺序解耦（§9.8：查找/插入/删除平均 O(1)）：
//   - vals/disp 是哈希索引（Go map），put/get/remove 均摊 O(1)；
//   - 输出顺序仍是**规范化键升序**（DET-01 与既有用例要求），但不维护有序数组，
//     改为惰性快照：sorted 是上次排序结果，dirty 是新增键，stale 标记有删除。
//     keys()/values() 时做一次「过滤 + 排序 + 归并」，复杂度 O(n + k log k)，
//     不把排序成本摊到每次 put 上。
type mapv struct {
	vals   map[string]*Value
	disp   map[string]*Value // 原始键值（keys() 返回用）
	sorted []string          // 上次升序快照（可能含已删除键，读时按 vals 过滤）
	dirty  []string          // 快照后新增的键（未排序）
	stale  bool              // 快照后发生过删除
}

func newMapv() *mapv {
	return &mapv{vals: map[string]*Value{}, disp: map[string]*Value{}}
}

func (m *mapv) len() int { return len(m.vals) }

// canonKey 规范化键：带类别标记避免 `1` 与 `"1"` 与 `'1'` 撞键。
func canonKey(v *Value) (string, bool) {
	switch v.K {
	case vInt:
		return "i:" + strconv.FormatInt(v.I, 10), true
	case vStr:
		return "s:" + v.S, true
	case vBool:
		if v.B {
			return "b:true", true
		}
		return "b:false", true
	case vChar:
		return "c:" + strconv.FormatInt(int64(v.C), 10), true
	}
	return "", false
}

func (m *mapv) set(k, val *Value) {
	ck, ok := canonKey(k)
	if !ok {
		panic(runtimeErr{"Map 键只能是 Int / String / Bool / Char"})
	}
	if _, exists := m.vals[ck]; !exists {
		m.dirty = append(m.dirty, ck)
	}
	m.vals[ck] = val
	m.disp[ck] = k
}

func (m *mapv) get(k *Value) (*Value, bool) {
	ck, ok := canonKey(k)
	if !ok {
		panic(runtimeErr{"Map 键只能是 Int / String / Bool / Char"})
	}
	v, exists := m.vals[ck]
	return v, exists
}

func (m *mapv) remove(k *Value) bool {
	ck, ok := canonKey(k)
	if !ok {
		panic(runtimeErr{"Map 键只能是 Int / String / Bool / Char"})
	}
	if _, exists := m.vals[ck]; !exists {
		return false
	}
	delete(m.vals, ck)
	delete(m.disp, ck)
	m.stale = true
	return true
}

// keysSorted 返回存活键的升序快照（O(n + k log k)；不改 vals）。
func (m *mapv) keysSorted() []string {
	if len(m.dirty) == 0 && !m.stale {
		return m.sorted
	}
	base := m.sorted
	if m.stale {
		kept := make([]string, 0, len(base))
		for _, ck := range base {
			if _, ok := m.vals[ck]; ok {
				kept = append(kept, ck)
			}
		}
		base = kept
		m.stale = false
	}
	// dirty 里可能有新增后又删除的键，统一按 vals 过滤。
	dirty := make([]string, 0, len(m.dirty))
	for _, ck := range m.dirty {
		if _, ok := m.vals[ck]; ok {
			dirty = append(dirty, ck)
		}
	}
	m.dirty = nil
	sort.Strings(dirty)
	if len(dirty) == 0 {
		m.sorted = base
		return m.sorted
	}
	merged := make([]string, 0, len(base)+len(dirty))
	i, j := 0, 0
	for i < len(base) && j < len(dirty) {
		switch {
		case base[i] < dirty[j]:
			merged = append(merged, base[i])
			i++
		case base[i] > dirty[j]:
			merged = append(merged, dirty[j])
			j++
		default: // 键同时出现在快照与新增（删除后重加）：只保留一份
			merged = append(merged, base[i])
			i++
			j++
		}
	}
	merged = append(merged, base[i:]...)
	merged = append(merged, dirty[j:]...)
	m.sorted = merged
	return m.sorted
}

// setv 是 Set 运行值：哈希索引 + 插入序（§9.6/§9.8）。
//   - idx/pos 提供平均 O(1) 的 add/has/remove；
//   - ord 保持插入序（删除置 nil 墓碑），at/for-in 按序读并跳过墓碑；
//   - 墓碑过多时 compact（均摊 O(1)）。
type setv struct {
	idx  map[string]*Value
	pos  map[string]int
	ord  []*Value
	live int
}

func newSetv() *setv {
	return &setv{idx: map[string]*Value{}, pos: map[string]int{}}
}

// elemKey 取 Set 元素的规范化键；不支持的类型运行时拒绝（静态限制在 sema）。
func elemKey(v *Value) string {
	ck, ok := canonKey(v)
	if !ok {
		panic(runtimeErr{"Set 元素只能是 Int / String / Bool / Char"})
	}
	return ck
}

func (s *setv) add(v *Value) bool {
	ck := elemKey(v)
	if _, exists := s.idx[ck]; exists {
		return false
	}
	s.pos[ck] = len(s.ord)
	s.ord = append(s.ord, v)
	s.idx[ck] = v
	s.live++
	return true
}

func (s *setv) has(v *Value) bool {
	_, ok := s.idx[elemKey(v)]
	return ok
}

func (s *setv) remove(v *Value) bool {
	ck := elemKey(v)
	if _, exists := s.idx[ck]; !exists {
		return false
	}
	s.ord[s.pos[ck]] = nil
	delete(s.pos, ck)
	delete(s.idx, ck)
	s.live--
	s.maybeCompact()
	return true
}

func (s *setv) at(i int) *Value {
	if i < 0 || i >= s.live {
		panic(fatal{"Set.at 越界"})
	}
	n := 0
	for _, e := range s.ord {
		if e == nil {
			continue
		}
		if n == i {
			return e
		}
		n++
	}
	panic(fatal{"Set.at 越界"})
}

// elements 返回插入序的存活元素（O(n)；墓碑过多时先 compact）。
func (s *setv) elements() []*Value {
	s.maybeCompact()
	out := make([]*Value, 0, s.live)
	for _, e := range s.ord {
		if e != nil {
			out = append(out, e)
		}
	}
	return out
}

func (s *setv) maybeCompact() {
	if len(s.ord) <= 2*s.live+8 {
		return
	}
	out := make([]*Value, 0, s.live)
	for _, e := range s.ord {
		if e == nil {
			continue
		}
		s.pos[elemKey(e)] = len(out)
		out = append(out, e)
	}
	s.ord = out
}

// clov 是闭包运行值（§7.7：参数类型显式；捕获创建时作用域）。
// top 非空表示包装的顶层函数名（`apply(add, 1)` 把具名函数当值传递，§7.7 示例）。
type clov struct {
	params []xfront.LambdaParam
	block  *xfront.Block
	exprB  xfront.Expr
	env    *scope
	top    string
}

// evalArrayLit 求值数组字面量（§9.3：[...] 创建固定长度 T[]）。
func (in *Interp) evalArrayLit(n *xfront.ArrayLit, sc *scope) *Value {
	elems := make([]*Value, len(n.Elems))
	for i, e := range n.Elems {
		elems[i] = in.eval(e, sc)
	}
	return &Value{K: vArr, A: elems}
}

// evalMapLit 求值 Map 字面量（空 Map 为 `[:]`）。
func (in *Interp) evalMapLit(n *xfront.MapLit, sc *scope) *Value {
	m := newMapv()
	for i := range n.Keys {
		k := in.eval(n.Keys[i], sc)
		v := in.eval(n.Vals[i], sc)
		m.set(k, v)
	}
	return &Value{K: vMap, M: m}
}

// evalTuple 求值元组字面量（§2.11：值类型，至少两元素）。
func (in *Interp) evalTuple(n *xfront.Tuple, sc *scope) *Value {
	elems := make([]*Value, len(n.Elems))
	for i, e := range n.Elems {
		elems[i] = in.eval(e, sc)
	}
	return &Value{K: vTuple, A: elems}
}

// evalLambda 求值闭包（捕获创建时的作用域）。
func (in *Interp) evalLambda(n *xfront.Lambda, sc *scope) *Value {
	return &Value{K: vClosure, Clo: &clov{params: n.Params, block: n.Block, exprB: n.ExprB, env: sc}}
}

// evalIndex 下标读取：T[]、List<T>、Map<K,V>（§9.1）。String 不支持下标（§9.2）。
func (in *Interp) evalIndex(n *xfront.Index, sc *scope) *Value {
	x := in.eval(n.X, sc)
	idx := in.eval(n.Idx, sc)
	switch x.K {
	case vArr:
		i := int(idx.I)
		if idx.K != vInt || i < 0 || i >= len(x.A) {
			panic(fatal{fmt.Sprintf("数组下标越界：len=%d, idx=%s（§7.4 越界即 fatal）", len(x.A), format(idx))})
		}
		return x.A[i]
	case vList:
		i := int(idx.I)
		if idx.K != vInt || i < 0 || i >= len(x.A) {
			panic(fatal{fmt.Sprintf("List 下标越界：len=%d, idx=%s", len(x.A), format(idx))})
		}
		return x.A[i]
	case vMap:
		v, ok := x.M.get(idx)
		if !ok {
			panic(fatal{"Map 中不存在键：" + format(idx) + "（用 getOr 提供缺省）"})
		}
		return v
	}
	panic(runtimeErr{"该类型不支持下标读取：" + x.typeName()})
}

// evalTupleMember 元组元素访问 `.N`（§2.11；越界解析层拒绝部分由这里兜底 fatal）。
func (in *Interp) evalTupleMember(n *xfront.TupleMember, sc *scope) *Value {
	x := in.eval(n.X, sc)
	if x.K != vTuple {
		panic(runtimeErr{".N 元素访问只用于元组：" + x.typeName()})
	}
	if n.Index < 0 || n.Index >= len(x.A) {
		panic(fatal{fmt.Sprintf("元组下标越界：len=%d, idx=%d（§2.11 越界选择器被拒绝）", len(x.A), n.Index)})
	}
	return x.A[n.Index]
}

// evalNewArray `new T[n]`：零值填充（Int→0、Bool→false、引用→null）。
func (in *Interp) evalNewArray(n *xfront.NewArray, sc *scope) *Value {
	cnt := in.eval(n.Count, sc)
	if cnt.K != vInt || cnt.I < 0 {
		// §9.3：count 必须是 Int；负数或分配失败是 panic。
		panic(fatal{"数组长度必须是非负 Int（§9.3：负数即 panic）"})
	}
	z := zeroValue(n.Type)
	elems := make([]*Value, cnt.I)
	for i := range elems {
		elems[i] = z
	}
	return &Value{K: vArr, A: elems}
}

func lastQual(t *xfront.NamedType) string {
	if len(t.Qual) == 0 {
		return ""
	}
	return t.Qual[len(t.Qual)-1]
}

// evalTypeAs 求值 `x is T` / `x as T` / `x as? T`（§7.7）。
// is → Bool；as → 失败 fatal；as? → 失败 null。
func (in *Interp) evalTypeAs(n *xfront.Binary, sc *scope) *Value {
	ta := n.R.(*xfront.TypeAsExpr)
	x := in.eval(n.L, sc)
	if ta.Is { // is
		return &Value{K: vBool, B: typeMatches(ta.Type, x)}
	}
	if typeMatches(ta.Type, x) {
		return x
	}
	if n.Op == "as?" {
		return &Value{K: vNull}
	}
	panic(fatal{"as 转换失败：" + x.typeName() + " 不能转换为目标类型（§7.7 运行时检查）"})
}

// typeMatches 判断运行值是否匹配 TypeRef（is/as 的运行时判定）。
// 泛型实参不检查（单态化在语义层，M2-C 接管）。
func typeMatches(t xfront.TypeRef, v *Value) bool {
	if v == nil {
		return false
	}
	switch ty := t.(type) {
	case *xfront.NamedType:
		name := lastQual(ty)
		switch name {
		case "Int", "Long", "Byte", "Short", "UByte", "UShort", "UInt", "ULong", "Int128", "UInt128":
			return v.K == vInt
		case "Float", "Double":
			return v.K == vFloat
		case "Bool":
			return v.K == vBool
		case "Char":
			return v.K == vChar
		case "String":
			return v.K == vStr
		case "Result":
			return v.K == vResult
		case "List":
			return v.K == vList
		case "Map":
			return v.K == vMap
		case "Set":
			return v.K == vSet
		case "Any", "Object":
			return v.K != vNull // Any/Object 装箱一切非 null 值
		}
		return false
	case *xfront.SuffixedType:
		for _, s := range ty.Suffixes {
			if s == "?" && v.K == vNull {
				return true // T? 接受 null
			}
		}
		if v.K == vNull {
			return false
		}
		base := ty.Base
		for _, s := range ty.Suffixes {
			if s == "[]" {
				return v.K == vArr
			}
		}
		return typeMatches(base, v)
	case *xfront.TupleTypeRef:
		return v.K == vTuple
	case *xfront.FuncTypeRef:
		return v.K == vClosure
	}
	return false
}

// callValueMethod 对非 Result 接收者做方法分派：String（§9.2）、T[]（§9.3）、
// List/Map/Set（§9.1，xdk.collections）。返回 (值, 是否命中)。
func (in *Interp) callValueMethod(recv *Value, name string, args []*Value, p xfront.Pos) (*Value, bool) {
	need := func(k int) {
		if len(args) != k {
			panic(runtimeErr{fmt.Sprintf("%s.%s 恰好接受 %d 个参数", recv.typeName(), name, k)})
		}
	}
	switch recv.K {
	case vStr:
		switch name {
		case "length":
			need(0)
			return &Value{K: vInt, I: int64(len(recv.S))}, true // UTF-8 字节数（§9.2）
		case "substring":
			need(2)
			start := int(clampIdx(args[0], int64(len(recv.S))))
			length := int(clampIdx(args[1], int64(len(recv.S)-start)))
			if args[0].I < 0 {
				start = 0
			}
			if length < 0 {
				length = 0
			}
			end := start + length
			if end > len(recv.S) {
				end = len(recv.S)
			}
			return &Value{K: vStr, S: recv.S[start:end]}, true
		case "indexOf":
			need(1)
			return &Value{K: vInt, I: int64(strings.Index(recv.S, args[0].S))}, true
		case "trim":
			need(0)
			return &Value{K: vStr, S: strings.Trim(recv.S, "\t\n\v\f\r ")}, true
		case "split":
			need(1)
			if args[0].S == "" {
				return &Value{K: vArr, A: []*Value{{K: vStr, S: recv.S}}}, true
			}
			parts := strings.Split(recv.S, args[0].S)
			elems := make([]*Value, len(parts))
			for i, s := range parts {
				elems[i] = &Value{K: vStr, S: s}
			}
			return &Value{K: vArr, A: elems}, true
		case "replace":
			need(2)
			if args[0].S == "" {
				return recv, true
			}
			return &Value{K: vStr, S: strings.ReplaceAll(recv.S, args[0].S, args[1].S)}, true
		case "toUpper":
			need(0)
			return &Value{K: vStr, S: asciiUpper(recv.S)}, true // §9.2：只转 ASCII 字母
		case "toLower":
			need(0)
			return &Value{K: vStr, S: asciiLower(recv.S)}, true // §9.2：只转 ASCII 字母
		case "startsWith":
			need(1)
			return &Value{K: vBool, B: strings.HasPrefix(recv.S, args[0].S)}, true
		case "endsWith":
			need(1)
			return &Value{K: vBool, B: strings.HasSuffix(recv.S, args[0].S)}, true
		}
	case vArr:
		switch name {
		case "length":
			need(0)
			return &Value{K: vInt, I: int64(len(recv.A))}, true
		case "join":
			need(1)
			parts := make([]string, len(recv.A))
			for i, e := range recv.A {
				parts[i] = format(e)
			}
			return &Value{K: vStr, S: strings.Join(parts, args[0].S)}, true
		}
	case vList:
		switch name {
		case "length":
			need(0)
			return &Value{K: vInt, I: int64(len(recv.A))}, true
		case "push":
			need(1)
			recv.A = append(recv.A, args[0])
			return &Value{K: vNull}, true
		case "insert":
			need(2)
			// §9.4：insert 只在 0..length 合法，越界 panic（不钳制）。
			if args[0].K != vInt || args[0].I < 0 || args[0].I > int64(len(recv.A)) {
				panic(fatal{fmt.Sprintf("List.insert 下标越界：len=%d, idx=%s（§9.4 合法范围 0..length）", len(recv.A), format(args[0]))})
			}
			i := int(args[0].I)
			recv.A = append(recv.A, nil)
			copy(recv.A[i+1:], recv.A[i:])
			recv.A[i] = args[1]
			return &Value{K: vNull}, true
		case "set":
			need(2)
			i := int(args[0].I)
			if i < 0 || i >= len(recv.A) {
				panic(fatal{"List.set 下标越界"})
			}
			recv.A[i] = args[1]
			return &Value{K: vNull}, true
		case "get":
			need(1)
			i := int(args[0].I)
			if i < 0 || i >= len(recv.A) {
				panic(fatal{"List.get 下标越界"})
			}
			return recv.A[i], true
		case "remove":
			need(1)
			i := int(args[0].I)
			if args[0].K != vInt || i < 0 || i >= len(recv.A) {
				panic(fatal{"List.remove 下标越界"})
			}
			removed := recv.A[i]
			recv.A = append(recv.A[:i], recv.A[i+1:]...)
			return removed, true // §9.4：删除并返回被删元素
		case "clear":
			need(0)
			recv.A = nil
			return &Value{K: vNull}, true
		}
	case vMap:
		switch name {
		case "length":
			need(0)
			return &Value{K: vInt, I: int64(recv.M.len())}, true
		case "put":
			need(2)
			recv.M.set(args[0], args[1])
			return &Value{K: vNull}, true
		case "get":
			need(1)
			// §9.5：get 返回 V?，缺失键返回 null，不 panic。
			v, ok := recv.M.get(args[0])
			if !ok {
				return &Value{K: vNull}, true
			}
			return v, true
		case "getOr":
			need(2)
			if v, ok := recv.M.get(args[0]); ok {
				return v, true
			}
			return args[1], true
		case "has":
			need(1)
			_, ok := recv.M.get(args[0])
			return &Value{K: vBool, B: ok}, true
		case "remove":
			need(1)
			return &Value{K: vBool, B: recv.M.remove(args[0])}, true
		case "clear":
			need(0)
			recv.M = newMapv()
			return &Value{K: vNull}, true
		case "keys":
			need(0)
			ks := recv.M.keysSorted()
			elems := make([]*Value, len(ks))
			for i, k := range ks {
				elems[i] = recv.M.disp[k]
			}
			return &Value{K: vArr, A: elems}, true // 按键排序（DET-01）
		case "values":
			need(0)
			ks := recv.M.keysSorted()
			elems := make([]*Value, len(ks))
			for i, k := range ks {
				elems[i] = recv.M.vals[k]
			}
			return &Value{K: vArr, A: elems}, true // 按键排序（DET-01）
		}
	case vSet:
		switch name {
		case "length":
			need(0)
			return &Value{K: vInt, I: int64(recv.Set.live)}, true
		case "add":
			need(1)
			return &Value{K: vBool, B: recv.Set.add(args[0])}, true
		case "has":
			need(1)
			return &Value{K: vBool, B: recv.Set.has(args[0])}, true
		case "at":
			need(1)
			if args[0].K != vInt {
				panic(runtimeErr{"Set.at 下标必须是 Int"})
			}
			return recv.Set.at(int(args[0].I)), true
		case "remove":
			need(1)
			return &Value{K: vBool, B: recv.Set.remove(args[0])}, true
		case "clear":
			need(0)
			recv.Set = newSetv()
			return &Value{K: vNull}, true
		}
	}
	return nil, false
}

// asciiUpper / asciiLower 只转换 ASCII 字母（§9.2）；其余字节原样保留。
func asciiUpper(s string) string {
	b := []byte(s)
	for i := range b {
		if b[i] >= 'a' && b[i] <= 'z' {
			b[i] -= 'a' - 'A'
		}
	}
	return string(b)
}

func asciiLower(s string) string {
	b := []byte(s)
	for i := range b {
		if b[i] >= 'A' && b[i] <= 'Z' {
			b[i] += 'a' - 'A'
		}
	}
	return string(b)
}

// clampIdx 下标参数钳制（substring 的负数/越界按 §9.2 收敛）。
func clampIdx(v *Value, max int64) int64 {
	if v.K != vInt {
		panic(runtimeErr{"下标参数必须是 Int"})
	}
	if v.I < 0 {
		return 0
	}
	if v.I > max {
		return max
	}
	return v.I
}

// valueEqual 容器元素同一性比较（Set 用）；标量按 §7.6 相等。
func valueEqual(a, b *Value) bool {
	switch a.K {
	case vInt:
		return b.K == vInt && a.I == b.I
	case vStr:
		return b.K == vStr && a.S == b.S
	case vBool:
		return b.K == vBool && a.B == b.B
	case vChar:
		return b.K == vChar && a.C == b.C
	case vNull:
		return b.K == vNull
	}
	return false // 容器/闭包不做值相等（同一性由引用决定，语义层约束）
}

// coerceByDecl 按声明类型定向初始化式（M2-C 类型检查前的最小定向）：
// List<T>/Set<T> 的 `[...]` 字面量求值为数组，这里转为对应容器。
func coerceByDecl(t xfront.TypeRef, v *Value) *Value {
	nt, ok := t.(*xfront.NamedType)
	if !ok || v == nil || v.K != vArr {
		return v
	}
	switch lastQual(nt) {
	case "List":
		return &Value{K: vList, A: v.A}
	case "Set":
		s := newSetv()
		for _, e := range v.A {
			s.add(e) // 去重且保持首次出现顺序（§9.6）
		}
		return &Value{K: vSet, Set: s}
	}
	return v
}

// callClosure 调用闭包值：新作用域挂在捕获环境上（§7.7）；
// return 信号转返回值，try/Err 信号穿出（由外层函数边界接管）。
func (in *Interp) callClosure(c *clov, args []*Value) (v *Value) {
	if c.top != "" { // 顶层函数按参数数量分派（§4.4 重载）
		fns, ok := in.funcs[c.top]
		if !ok {
			panic(runtimeErr{"未定义的函数：" + c.top})
		}
		for _, f := range fns {
			if len(f.Params) == len(args) {
				v2, err := in.call(f, args)
				if err != nil {
					panic(runtimeErr{err.Error()})
				}
				return v2
			}
		}
		panic(runtimeErr{fmt.Sprintf("函数 %s 没有接受 %d 个参数的重载", c.top, len(args))})
	}
	if len(args) != len(c.params) {
		panic(runtimeErr{fmt.Sprintf("闭包期望 %d 个参数，收到 %d", len(c.params), len(args))})
	}
	defer func() {
		if r := recover(); r != nil {
			if sig, ok := r.(ctrlReturn); ok {
				v = sig.v
				return
			}
			panic(r)
		}
	}()
	sc := newScope(c.env)
	for i, prm := range c.params {
		sc.defineTyped(prm.Name, prm.Type, args[i])
	}
	if c.exprB != nil {
		return in.eval(c.exprB, sc)
	}
	in.execBlock(c.block, sc)
	return &Value{K: vNull}
}

// formatContainer 容器格式化（print/插值共用；Map/Set 按键排序——DET-01）。
// 注意：§266 的插值允许清单只含元组不含数组/Map/Set；静态拒绝在 M2-C 类型检查。
func formatContainer(v *Value) string {
	switch v.K {
	case vArr, vList:
		parts := make([]string, len(v.A))
		for i, e := range v.A {
			parts[i] = format(e)
		}
		return "[" + strings.Join(parts, ", ") + "]"
	case vSet:
		elems := v.Set.elements()
		parts := make([]string, len(elems))
		for i, e := range elems {
			parts[i] = format(e)
		}
		return "{" + strings.Join(parts, ", ") + "}"
	case vMap:
		ks := v.M.keysSorted()
		parts := make([]string, 0, len(ks))
		for _, k := range ks {
			parts = append(parts, format(v.M.disp[k])+": "+format(v.M.vals[k]))
		}
		return "{" + strings.Join(parts, ", ") + "}"
	case vTuple:
		parts := make([]string, len(v.A))
		for i, e := range v.A {
			parts[i] = format(e)
		}
		return "(" + strings.Join(parts, ", ") + ")"
	case vClosure:
		return "<closure>"
	case vObj:
		return "<" + v.O.cls.Name + ">"
	}
	return "?"
}
