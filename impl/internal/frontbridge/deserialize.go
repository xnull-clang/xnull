// Package frontbridge 是 Go 工具链与 XNull 自举前端之间的桥接层。
//
// 正常路径：xparser.x 输出 xnast v1 S 表达式 → 本包反序列化为 *xfront.CompilationUnit。
// Go xfront 仅作 oracle（诊断与回退），不再作为 check/run/build 的 AST 来源。
//
// 设计见 handoff/B2-04-bridge.md。
package frontbridge

import (
	"fmt"
	"reflect"
	"strconv"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

// sexpr 是 xnast v1 dump 的通用语法树。
// 节点：(TypeName (Field Value)...)；切片：(slice v...)；空值：(nil)；标量为裸 token 或带引号字符串。
type sexpr struct {
	scalar bool
	quoted bool
	text   string // 节点名或标量值（字符串已反转义）
	slice  bool
	fields []sfield
	elems  []*sexpr
}

type sfield struct {
	name string
	val  *sexpr
}

type sexprParser struct {
	s string
	i int
}

// Deserialize 把 xnast v1 的 AST dump 解码为 *xfront.CompilationUnit。
func Deserialize(dump string) (*xfront.CompilationUnit, error) {
	v, err := parseDump(strings.TrimSpace(dump))
	if err != nil {
		return nil, err
	}
	rv, err := decodeValue(v, reflect.TypeOf(xfront.CompilationUnit{}))
	if err != nil {
		return nil, err
	}
	u, ok := rv.Addr().Interface().(*xfront.CompilationUnit)
	if !ok {
		return nil, fmt.Errorf("frontbridge: dump 根节点不是 CompilationUnit")
	}
	return u, nil
}

func parseDump(s string) (*sexpr, error) {
	p := &sexprParser{s: s}
	p.ws()
	if p.eof() {
		return nil, fmt.Errorf("frontbridge: 空 dump")
	}
	if strings.HasPrefix(s[p.i:], "(xnast") {
		p.i++ // '('
		name := p.bare()
		if name != "xnast" {
			return nil, fmt.Errorf("frontbridge: 期望 xnast，得到 %q", name)
		}
		p.ws()
		if p.bare() != "v1" {
			return nil, fmt.Errorf("frontbridge: 不支持的 dump 版本")
		}
		p.ws()
		v, err := p.value()
		if err != nil {
			return nil, err
		}
		p.ws()
		if p.eof() || p.s[p.i] != ')' {
			return nil, fmt.Errorf("frontbridge: dump 末尾缺少 )")
		}
		p.i++
		p.ws()
		if !p.eof() {
			return nil, fmt.Errorf("frontbridge: dump 后有多余内容")
		}
		return v, nil
	}
	v, err := p.value()
	if err != nil {
		return nil, err
	}
	p.ws()
	if !p.eof() {
		return nil, fmt.Errorf("frontbridge: dump 后有多余内容")
	}
	return v, nil
}

func (p *sexprParser) eof() bool { return p.i >= len(p.s) }

func (p *sexprParser) ws() {
	for p.i < len(p.s) {
		switch p.s[p.i] {
		case ' ', '\n', '\t', '\r':
			p.i++
		default:
			return
		}
	}
}

func (p *sexprParser) bare() string {
	start := p.i
	for p.i < len(p.s) {
		switch p.s[p.i] {
		case ' ', '\n', '\t', '\r', '(', ')':
			return p.s[start:p.i]
		default:
			p.i++
		}
	}
	return p.s[start:p.i]
}

func (p *sexprParser) value() (*sexpr, error) {
	p.ws()
	if p.eof() {
		return nil, fmt.Errorf("frontbridge: 意外结束")
	}
	switch p.s[p.i] {
	case '(':
		return p.node()
	case '"':
		start := p.i
		p.i++
		for p.i < len(p.s) {
			switch p.s[p.i] {
			case '\\':
				p.i += 2
			case '"':
				p.i++
				raw := p.s[start:p.i]
				text, err := strconv.Unquote(raw)
				if err != nil {
					return nil, fmt.Errorf("frontbridge: 字符串转义非法 %q: %w", raw, err)
				}
				return &sexpr{scalar: true, quoted: true, text: text}, nil
			default:
				p.i++
			}
		}
		return nil, fmt.Errorf("frontbridge: 字符串未闭合")
	default:
		tok := p.bare()
		if tok == "" {
			return nil, fmt.Errorf("frontbridge: 位置 %d 处缺少标量", p.i)
		}
		return &sexpr{scalar: true, text: tok}, nil
	}
}

func (p *sexprParser) node() (*sexpr, error) {
	if p.s[p.i] != '(' {
		return nil, fmt.Errorf("frontbridge: 期望 (，位置 %d", p.i)
	}
	p.i++
	name := p.bare()
	if name == "" {
		return nil, fmt.Errorf("frontbridge: 节点名为空，位置 %d", p.i)
	}
	n := &sexpr{text: name}
	if name == "slice" {
		n.slice = true
		for {
			p.ws()
			if p.eof() {
				return nil, fmt.Errorf("frontbridge: slice 未闭合")
			}
			if p.s[p.i] == ')' {
				p.i++
				return n, nil
			}
			v, err := p.value()
			if err != nil {
				return nil, err
			}
			n.elems = append(n.elems, v)
		}
	}
	for {
		p.ws()
		if p.eof() {
			return nil, fmt.Errorf("frontbridge: 节点 %s 未闭合", name)
		}
		if p.s[p.i] == ')' {
			p.i++
			return n, nil
		}
		if p.s[p.i] != '(' {
			return nil, fmt.Errorf("frontbridge: 节点 %s 的字段缺少 (，位置 %d", name, p.i)
		}
		p.i++
		fname := p.bare()
		if fname == "" {
			return nil, fmt.Errorf("frontbridge: 节点 %s 的字段名为空", name)
		}
		v, err := p.value()
		if err != nil {
			return nil, err
		}
		p.ws()
		if p.eof() || p.s[p.i] != ')' {
			return nil, fmt.Errorf("frontbridge: 字段 %s 未闭合", fname)
		}
		p.i++
		n.fields = append(n.fields, sfield{name: fname, val: v})
	}
}

// concreteByName 是接口字段可出现的具体 AST 类型（按 Go 类型名索引）。
var concreteByName = func() map[string]reflect.Type {
	types := []reflect.Type{
		// Expr
		reflect.TypeOf((*xfront.IdentExpr)(nil)),
		reflect.TypeOf((*xfront.IntLitExpr)(nil)),
		reflect.TypeOf((*xfront.FloatLitExpr)(nil)),
		reflect.TypeOf((*xfront.CharLitExpr)(nil)),
		reflect.TypeOf((*xfront.BoolLit)(nil)),
		reflect.TypeOf((*xfront.NullLit)(nil)),
		reflect.TypeOf((*xfront.StrLitExpr)(nil)),
		reflect.TypeOf((*xfront.Paren)(nil)),
		reflect.TypeOf((*xfront.Tuple)(nil)),
		reflect.TypeOf((*xfront.ArrayLit)(nil)),
		reflect.TypeOf((*xfront.MapLit)(nil)),
		reflect.TypeOf((*xfront.Unary)(nil)),
		reflect.TypeOf((*xfront.Binary)(nil)),
		reflect.TypeOf((*xfront.Ternary)(nil)),
		reflect.TypeOf((*xfront.Member)(nil)),
		reflect.TypeOf((*xfront.TupleMember)(nil)),
		reflect.TypeOf((*xfront.Call)(nil)),
		reflect.TypeOf((*xfront.Index)(nil)),
		reflect.TypeOf((*xfront.New)(nil)),
		reflect.TypeOf((*xfront.NewArray)(nil)),
		reflect.TypeOf((*xfront.Lambda)(nil)),
		reflect.TypeOf((*xfront.TypeAsExpr)(nil)),
		// Stmt
		reflect.TypeOf((*xfront.ReturnStmt)(nil)),
		reflect.TypeOf((*xfront.ExprStmt)(nil)),
		reflect.TypeOf((*xfront.LocalDeclStmt)(nil)),
		reflect.TypeOf((*xfront.AssignStmt)(nil)),
		reflect.TypeOf((*xfront.IncDecStmt)(nil)),
		reflect.TypeOf((*xfront.IfStmt)(nil)),
		reflect.TypeOf((*xfront.WhileStmt)(nil)),
		reflect.TypeOf((*xfront.DoWhileStmt)(nil)),
		reflect.TypeOf((*xfront.ForStmt)(nil)),
		reflect.TypeOf((*xfront.SwitchStmt)(nil)),
		reflect.TypeOf((*xfront.SwitchCase)(nil)),
		reflect.TypeOf((*xfront.DeferStmt)(nil)),
		reflect.TypeOf((*xfront.BreakStmt)(nil)),
		reflect.TypeOf((*xfront.ContinueStmt)(nil)),
		reflect.TypeOf((*xfront.GotoStmt)(nil)),
		reflect.TypeOf((*xfront.LabeledStmt)(nil)),
		reflect.TypeOf((*xfront.ThrowStmt)(nil)),
		reflect.TypeOf((*xfront.EmptyStmt)(nil)),
		reflect.TypeOf((*xfront.Block)(nil)),
		// TypeRef
		reflect.TypeOf((*xfront.NamedType)(nil)),
		reflect.TypeOf((*xfront.SuffixedType)(nil)),
		reflect.TypeOf((*xfront.FuncTypeRef)(nil)),
		reflect.TypeOf((*xfront.TupleTypeRef)(nil)),
		// TopDecl
		reflect.TypeOf((*xfront.TopFunc)(nil)),
		reflect.TypeOf((*xfront.TopField)(nil)),
		reflect.TypeOf((*xfront.ClassDecl)(nil)),
		reflect.TypeOf((*xfront.StructDecl)(nil)),
		reflect.TypeOf((*xfront.ProtocolDecl)(nil)),
		reflect.TypeOf((*xfront.EnumDecl)(nil)),
		reflect.TypeOf((*xfront.SingletonDecl)(nil)),
		reflect.TypeOf((*xfront.FactoryDecl)(nil)),
		reflect.TypeOf((*xfront.ExtensionDecl)(nil)),
		reflect.TypeOf((*xfront.AnnotationDecl)(nil)),
		reflect.TypeOf((*xfront.PackageDecl)(nil)),
		reflect.TypeOf((*xfront.ImportDecl)(nil)),
	}
	m := make(map[string]reflect.Type, len(types))
	for _, t := range types {
		m[t.Elem().Name()] = t
	}
	return m
}()

func decodeValue(v *sexpr, t reflect.Type) (reflect.Value, error) {
	if !v.scalar && v.text == "nil" && len(v.fields) == 0 {
		return reflect.Zero(t), nil
	}
	switch t.Kind() {
	case reflect.Pointer:
		elem := reflect.New(t.Elem())
		dv, err := decodeValue(v, t.Elem())
		if err != nil {
			return reflect.Value{}, err
		}
		elem.Elem().Set(dv)
		return elem, nil
	case reflect.Interface:
		ct := concreteByName[v.text]
		if ct == nil {
			return reflect.Value{}, fmt.Errorf("frontbridge: 未知具体类型 %q（目标接口 %s）", v.text, t)
		}
		if !ct.Implements(t) {
			return reflect.Value{}, fmt.Errorf("frontbridge: 类型 %s 未实现接口 %s", ct, t)
		}
		dv, err := decodeValue(v, ct)
		if err != nil {
			return reflect.Value{}, err
		}
		return dv, nil
	case reflect.Struct:
		if v.scalar {
			return reflect.Value{}, fmt.Errorf("frontbridge: 期望结构体 %s，得到标量 %q", t, v.text)
		}
		if v.text != t.Name() {
			return reflect.Value{}, fmt.Errorf("frontbridge: 期望结构体 %s，得到 %s", t, v.text)
		}
		out := reflect.New(t).Elem()
		for _, f := range v.fields {
			sf, ok := t.FieldByName(f.name)
			if !ok {
				return reflect.Value{}, fmt.Errorf("frontbridge: 结构体 %s 无字段 %s", t, f.name)
			}
			dv, err := decodeValue(f.val, sf.Type)
			if err != nil {
				return reflect.Value{}, fmt.Errorf("frontbridge: %s.%s: %w", t, f.name, err)
			}
			out.FieldByIndex(sf.Index).Set(dv)
		}
		return out, nil
	case reflect.Slice:
		if !v.slice {
			return reflect.Value{}, fmt.Errorf("frontbridge: 期望切片，得到 %q", v.text)
		}
		out := reflect.MakeSlice(t, len(v.elems), len(v.elems))
		for i, e := range v.elems {
			dv, err := decodeValue(e, t.Elem())
			if err != nil {
				return reflect.Value{}, fmt.Errorf("frontbridge: 切片元素 %d: %w", i, err)
			}
			out.Index(i).Set(dv)
		}
		return out, nil
	case reflect.String:
		if !v.scalar || !v.quoted {
			return reflect.Value{}, fmt.Errorf("frontbridge: 期望字符串，得到 %q", v.text)
		}
		return reflect.ValueOf(v.text).Convert(t), nil
	case reflect.Bool:
		if !v.scalar {
			return reflect.Value{}, fmt.Errorf("frontbridge: 期望布尔，得到 %q", v.text)
		}
		switch v.text {
		case "true":
			return reflect.ValueOf(true).Convert(t), nil
		case "false":
			return reflect.ValueOf(false).Convert(t), nil
		}
		return reflect.Value{}, fmt.Errorf("frontbridge: 布尔值非法 %q", v.text)
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		if !v.scalar {
			return reflect.Value{}, fmt.Errorf("frontbridge: 期望整数，得到 %q", v.text)
		}
		n, err := strconv.ParseInt(v.text, 10, 64)
		if err != nil {
			return reflect.Value{}, fmt.Errorf("frontbridge: 整数非法 %q: %w", v.text, err)
		}
		return reflect.ValueOf(n).Convert(t), nil
	case reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64:
		if !v.scalar {
			return reflect.Value{}, fmt.Errorf("frontbridge: 期望无符号整数，得到 %q", v.text)
		}
		n, err := strconv.ParseUint(v.text, 10, 64)
		if err != nil {
			return reflect.Value{}, fmt.Errorf("frontbridge: 无符号整数非法 %q: %w", v.text, err)
		}
		return reflect.ValueOf(n).Convert(t), nil
	case reflect.Float32, reflect.Float64:
		if !v.scalar {
			return reflect.Value{}, fmt.Errorf("frontbridge: 期望浮点，得到 %q", v.text)
		}
		n, err := strconv.ParseFloat(v.text, 64)
		if err != nil {
			return reflect.Value{}, fmt.Errorf("frontbridge: 浮点非法 %q: %w", v.text, err)
		}
		return reflect.ValueOf(n).Convert(t), nil
	default:
		return reflect.Value{}, fmt.Errorf("frontbridge: 不支持的字段类型 %s", t)
	}
}
