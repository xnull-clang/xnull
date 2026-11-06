package ffi

import (
	"strconv"
)

// ---- 声明文件 AST（仅声明结构，不做语义判定） ----

// typeRef 是声明中的类型引用（未解析）。
type typeRef struct {
	Pos      pos
	Name     string
	ArrayDim int
	Optional bool
}

type paramSrc struct {
	Pos  pos
	Name string
	Type typeRef
}

type annArg struct {
	Key   string // 无键参数为空串（如 @blocking(.unaware)）
	Value string // ".borrow" 形值保留前导点
	Pos   pos
}

type annotation struct {
	Name string
	Pos  pos
	Args []annArg
}

type entrySrc struct {
	Pos    pos
	Name   string
	Ret    typeRef
	Params []paramSrc
	Anns   []annotation
}

type fieldSrc struct {
	Pos  pos
	Type string
	Name string
}

type layoutSrc struct {
	Pos    pos
	Name   string
	Fields []fieldSrc
}

type handleSrc struct {
	Pos   pos
	Name  string
	Close string
}

type errRuleSrc struct {
	Pos  pos
	Code int32
	Kind string
}

type region struct {
	Name    string
	Pos     pos
	File    string
	Layouts []*layoutSrc
	Handles []*handleSrc
	ErrMap  []errRuleSrc
	Entries []*entrySrc
}

// ---- 解析器 ----

type parseErr struct {
	p   pos
	msg string
}

type parser struct {
	file string
	toks []token
	i    int
}

func (p *parser) peek() token { return p.toks[p.i] }

func (p *parser) next() token {
	t := p.toks[p.i]
	if t.kind != tokEOF {
		p.i++
	}
	return t
}

func (p *parser) fail(at pos, msg string) { panic(parseErr{at, msg}) }

func (p *parser) acceptPunct(s string) bool {
	t := p.peek()
	if t.kind == tokPunct && t.text == s {
		p.i++
		return true
	}
	return false
}

func (p *parser) expectPunct(s string) token {
	t := p.next()
	if t.kind != tokPunct || t.text != s {
		p.fail(t.pos, "期望 '"+s+"'")
	}
	return t
}

func (p *parser) expectIdent(what string) token {
	t := p.next()
	if t.kind != tokIdent {
		p.fail(t.pos, "期望"+what)
	}
	return t
}

// parseFile 解析一个 .xfb 文件。语法错误 → FFI-100 诊断（该文件不再进入校验）。
func parseFile(src, file string) (regions []*region, diags []Diagnostic) {
	lx := newLexer(src, file)
	toks := lx.run()
	if len(lx.diags) > 0 {
		return nil, lx.diags
	}
	p := &parser{file: file, toks: toks}
	defer func() {
		if r := recover(); r != nil {
			pe, ok := r.(parseErr)
			if !ok {
				panic(r)
			}
			regions = nil
			diags = []Diagnostic{{
				File: file, Line: pe.p.Line, Col: pe.p.Col, Code: "FFI-100", Message: pe.msg,
			}}
		}
	}()
	for p.peek().kind != tokEOF {
		regions = append(regions, p.parseRegion())
	}
	return regions, nil
}

func (p *parser) parseRegion() *region {
	kw := p.next()
	if kw.kind != tokIdent || kw.text != "ffi" {
		p.fail(kw.pos, "期望 ffi 块（S7 绑定声明文件顶层）")
	}
	nm := p.expectIdent("ffi 块名")
	p.expectPunct("{")
	rg := &region{Name: nm.text, Pos: kw.pos, File: p.file}
	for {
		t := p.peek()
		if t.kind == tokEOF {
			p.fail(t.pos, "ffi 块未闭合")
		}
		if t.kind == tokPunct && t.text == "}" {
			p.next()
			return rg
		}
		if t.kind == tokIdent {
			switch t.text {
			case "layout":
				rg.Layouts = append(rg.Layouts, p.parseLayout())
				continue
			case "handle":
				rg.Handles = append(rg.Handles, p.parseHandle())
				continue
			case "errorMap":
				p.parseErrorMap(rg)
				continue
			}
		}
		rg.Entries = append(rg.Entries, p.parseEntry())
	}
}

func (p *parser) parseLayout() *layoutSrc {
	kw := p.next()
	p.expectPunct("(")
	form := p.expectIdent("layout 形式")
	if form.text != "c" {
		p.fail(form.pos, "仅支持 layout(c)（S7 §3.3）")
	}
	p.expectPunct(")")
	st := p.expectIdent("struct")
	if st.text != "struct" {
		p.fail(st.pos, "layout(c) 后需 struct")
	}
	nm := p.expectIdent("结构名")
	p.expectPunct("{")
	ls := &layoutSrc{Pos: kw.pos, Name: nm.text}
	for {
		t := p.peek()
		if t.kind == tokEOF {
			p.fail(t.pos, "layout(c) 结构未闭合")
		}
		if t.kind == tokPunct && t.text == "}" {
			p.next()
			return ls
		}
		ft := p.expectIdent("字段类型")
		fn := p.expectIdent("字段名")
		ls.Fields = append(ls.Fields, fieldSrc{Pos: ft.pos, Type: ft.text, Name: fn.text})
		p.acceptPunct(";")
	}
}

func (p *parser) parseHandle() *handleSrc {
	kw := p.next()
	nm := p.expectIdent("句柄名")
	p.expectPunct("{")
	h := &handleSrc{Pos: kw.pos, Name: nm.text}
	for {
		t := p.peek()
		if t.kind == tokEOF {
			p.fail(t.pos, "handle 块未闭合")
		}
		if t.kind == tokPunct && t.text == "}" {
			p.next()
			return h
		}
		key := p.expectIdent("句柄成员")
		if key.text != "close" {
			p.fail(key.pos, "句柄仅支持 close 成员（S7 §4.3）")
		}
		p.expectPunct("=")
		v := p.expectIdent("close 入口名")
		h.Close = v.text
		p.acceptPunct(";")
	}
}

func (p *parser) parseErrorMap(rg *region) {
	kw := p.next()
	p.expectPunct("{")
	for {
		t := p.peek()
		if t.kind == tokEOF {
			p.fail(t.pos, "errorMap 块未闭合")
		}
		if t.kind == tokPunct && t.text == "}" {
			p.next()
			return
		}
		codeTok := p.next()
		if codeTok.kind != tokNumber {
			p.fail(codeTok.pos, "errorMap 码值必须是整数")
		}
		code, err := strconv.ParseInt(codeTok.text, 10, 32)
		if err != nil {
			p.fail(codeTok.pos, "errorMap 码值超出 Int32 范围")
		}
		p.expectPunct("=")
		kind := p.expectIdent("ErrorKind 分类")
		rg.ErrMap = append(rg.ErrMap, errRuleSrc{Pos: kw.pos, Code: int32(code), Kind: kind.text})
		p.acceptPunct(";")
	}
}

func (p *parser) parseEntry() *entrySrc {
	e := &entrySrc{Pos: p.peek().pos}
	for p.peek().kind == tokPunct && p.peek().text == "@" {
		e.Anns = append(e.Anns, p.parseAnnotation())
	}
	e.Ret = p.parseType()
	nm := p.expectIdent("入口名")
	e.Name = nm.text
	p.expectPunct("(")
	if !(p.peek().kind == tokPunct && p.peek().text == ")") {
		for {
			pt := p.parseType()
			pn := p.expectIdent("参数名")
			e.Params = append(e.Params, paramSrc{Pos: pt.Pos, Name: pn.text, Type: pt})
			if p.acceptPunct(",") {
				continue
			}
			break
		}
	}
	p.expectPunct(")")
	p.expectPunct(";")
	return e
}

func (p *parser) parseType() typeRef {
	t := p.next()
	if t.kind != tokIdent {
		p.fail(t.pos, "期望类型名")
	}
	tr := typeRef{Pos: t.pos, Name: t.text}
	for p.peek().kind == tokPunct && (p.peek().text == "[" || p.peek().text == "*") {
		if p.peek().text == "*" {
			p.next()
			tr.Name += "*" // 裸指针文本保留，交合同校验层给 FFI-108
			continue
		}
		p.next()
		p.expectPunct("]")
		tr.ArrayDim++
	}
	if p.peek().kind == tokPunct && p.peek().text == "?" {
		p.next()
		tr.Optional = true
	}
	return tr
}

func (p *parser) parseAnnotation() annotation {
	at := p.expectPunct("@")
	nm := p.expectIdent("注解名")
	a := annotation{Name: nm.text, Pos: at.pos}
	if p.peek().kind == tokPunct && p.peek().text == "(" {
		p.next()
		for {
			a.Args = append(a.Args, p.parseAnnArg())
			if p.acceptPunct(",") {
				continue
			}
			break
		}
		p.expectPunct(")")
	}
	return a
}

func (p *parser) parseAnnArg() annArg {
	t := p.next()
	switch {
	case t.kind == tokIdent && p.peek().kind == tokPunct && p.peek().text == "=":
		p.next()
		v := p.next()
		if v.kind == tokPunct && v.text == "." {
			id := p.expectIdent("租约/通道值")
			return annArg{Key: t.text, Value: "." + id.text, Pos: t.pos}
		}
		if v.kind != tokString && v.kind != tokNumber && v.kind != tokIdent {
			p.fail(v.pos, "注解参数值非法")
		}
		return annArg{Key: t.text, Value: v.text, Pos: t.pos}
	case t.kind == tokPunct && t.text == ".":
		id := p.expectIdent("值")
		return annArg{Value: "." + id.text, Pos: t.pos}
	case t.kind == tokString || t.kind == tokNumber || t.kind == tokIdent:
		return annArg{Value: t.text, Pos: t.pos}
	default:
		p.fail(t.pos, "注解参数非法")
	}
	return annArg{}
}
