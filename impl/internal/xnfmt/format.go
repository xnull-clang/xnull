package xnfmt

import (
	"strings"
	"unicode/utf8"
)

// Format 按格式化规范 v1.0.0 格式化源码。失败时返回诊断（不返回部分结果）。
func Format(file, src string) (string, []Diagnostic) {
	norm, diag := decode(file, src)
	if diag != nil {
		return "", []Diagnostic{*diag}
	}
	toks, diags := scan(file, norm)
	if len(diags) > 0 {
		return "", diags
	}
	if len(toks) == 0 {
		return "", nil // R3.6
	}
	annotate(toks)
	lines := groupLines(toks)
	return render(file, lines), nil
}

// decode 执行 P1：UTF-8 严格校验（R3.1）、去 BOM（R3.2）、换行归一（R3.3）。
func decode(file, src string) (string, *Diagnostic) {
	if !utf8.ValidString(src) {
		line, col := 1, 1
		for i := 0; i < len(src); {
			r, size := utf8.DecodeRuneInString(src[i:])
			if r == utf8.RuneError && size == 1 {
				return "", &Diagnostic{File: file, Line: line, Col: col, Code: fmtEnc, Message: "输入不是合法 UTF-8"}
			}
			if r == '\n' {
				line++
				col = 1
			} else {
				col++
			}
			i += size
		}
	}
	s := strings.TrimPrefix(src, "\ufeff")
	s = strings.ReplaceAll(s, "\r\n", "\n")
	s = strings.ReplaceAll(s, "\r", "\n")
	return s, nil
}

// ---- 行记录（P3） ----

type logicalLine struct {
	toks    []token
	line    int
	endLine int
}

func (l logicalLine) first() token { return l.toks[0] }
func (l logicalLine) last() token  { return l.toks[len(l.toks)-1] }
func (l logicalLine) onlyComments() bool {
	for _, t := range l.toks {
		if !t.isComment() {
			return false
		}
	}
	return true
}

func groupLines(toks []token) []logicalLine {
	var out []logicalLine
	for _, t := range toks {
		if n := len(out); n > 0 {
			cur := &out[n-1]
			if t.line <= cur.endLine { // 同一逻辑行（含跨行 token 的闭合行）
				cur.toks = append(cur.toks, t)
				if t.endLine > cur.endLine {
					cur.endLine = t.endLine
				}
				continue
			}
		}
		out = append(out, logicalLine{toks: []token{t}, line: t.line, endLine: t.endLine})
	}
	return out
}

// ---- 角色判定（R7 / R8） ----

func annotate(toks []token) {
	// 三元 ? / 可空 ? 与配对冒号（R8.1–R8.5）
	var pending []int
	depth := 0
	for i := range toks {
		t := &toks[i]
		switch t.text {
		case "(", "[", "{":
			depth++
		case ")", "]", "}":
			if depth > 0 {
				depth--
			}
			if t.text == "}" {
				pending = pending[:0]
			}
		case ";":
			pending = pending[:0]
		case "?":
			if hasTernaryColon(toks, i) {
				t.ternaryQ = true
				pending = append(pending, i)
			} else if i > 0 && isTypeAtom(toks[i-1]) {
				t.nullableQ = true
			}
		case ":":
			if n := len(pending); n > 0 {
				toks[pending[n-1]].ternaryQ = true
				t.ternaryColon = true
				pending = pending[:n-1]
			}
		case "<":
			if j, ok := genericClose(toks, i); ok {
				t.genericOpen = true
				toks[j].genericClose = true
			}
		}
	}
	// 一元/后缀（R7）
	for i := range toks {
		switch toks[i].text {
		case "!":
			toks[i].unaryPrefix = true
		case "~":
			toks[i].unaryPrefix = true
		case "+", "-":
			if i == 0 || !isExprEnd(toks[i-1]) {
				toks[i].unaryPrefix = true
			}
		case "++", "--":
			if i == 0 || !isExprEnd(toks[i-1]) {
				toks[i].unaryPrefix = true
			} else {
				toks[i].unaryPostfix = true
			}
		}
	}
}

// hasTernaryColon 实现 R8.1：同层前向扫描，遇到 ; { } / EOF 停止。
func hasTernaryColon(toks []token, q int) bool {
	depth := 0
	for j := q + 1; j < len(toks); j++ {
		switch toks[j].text {
		case "(", "[":
			depth++
		case ")", "]":
			if depth > 0 {
				depth--
			}
		case "{", "}":
			if depth == 0 {
				return false
			}
		case ";":
			if depth == 0 {
				return false
			}
		case ":":
			if depth == 0 {
				return true
			}
		}
	}
	return false
}

var genericAllowed = map[string]bool{
	",": true, ".": true, "[": true, "]": true, "?": true, "<": true, ">": true,
	">>": true, "(": true, ")": true, "->": true,
}

// genericClose 实现 §8.3 扫描；返回闭合 > / >> 的下标。
func genericClose(toks []token, i int) (int, bool) {
	if i == 0 {
		return 0, false
	}
	prev := toks[i-1]
	if !(prev.kind == tkIdent || prev.text == "]" || prev.text == ">" || prev.text == ">>") {
		return 0, false
	}
	depth := 0
	for j := i; j < len(toks); j++ {
		t := toks[j].text
		switch {
		case t == "<":
			depth++
		case t == ">":
			depth--
		case t == ">>":
			depth -= 2
		case toks[j].kind == tkIdent || genericAllowed[t]:
			// 允许集
		default:
			return 0, false
		}
		if depth <= 0 {
			return j, true
		}
	}
	return 0, false
}

func isTypeAtom(t token) bool {
	if t.kind == tkIdent {
		return true
	}
	return t.text == "]" || t.text == ">" || t.text == ">>"
}

// isExprEnd 是 R7.4 的「表达式结束」集合。
func isExprEnd(t token) bool {
	switch t.kind {
	case tkIdent, tkNumber, tkChar, tkString:
		return true
	case tkKeyword:
		switch t.text {
		case "true", "false", "null", "self", "super":
			return true
		}
	}
	switch t.text {
	case ")", "]", "}":
		return true
	}
	return t.unaryPostfix
}

// ---- 渲染 ----

func render(file string, lines []logicalLine) string {
	// 头部区（R9）
	i := 0
	var headComments []logicalLine
	for i < len(lines) && lines[i].onlyComments() {
		if len(headComments) > 0 && lines[i].line-lines[i-1].endLine > 1 {
			break
		}
		headComments = append(headComments, lines[i])
		i++
	}
	var pkg *logicalLine
	if i < len(lines) && lines[i].first().isKeyword("package") {
		p := lines[i]
		pkg = &p
		i++
	}
	var importBlock []logicalLine
	for i < len(lines) && (lines[i].first().isKeyword("import") || lines[i].onlyComments()) {
		importBlock = append(importBlock, lines[i])
		i++
	}
	body := lines[i:]

	var out []string
	appendSection := func(sec []string) {
		if len(sec) == 0 {
			return
		}
		if len(out) > 0 {
			out = append(out, "")
		}
		out = append(out, sec...)
	}

	if len(headComments) > 0 {
		var sec []string
		for _, ln := range headComments {
			sec = append(sec, renderLine(ln, 0))
		}
		appendSection(sec)
	}
	if pkg != nil {
		appendSection([]string{renderLine(*pkg, 0)})
	}
	if len(importBlock) > 0 {
		appendSection(renderImports(importBlock))
	}
	appendSection(renderBody(body))

	if len(out) == 0 {
		return ""
	}
	return strings.Join(out, "\n") + "\n"
}

// renderImports 按 R9.2–R9.6 重排 import 块。
func renderImports(block []logicalLine) []string {
	var out []string
	var cur []logicalLine
	flush := func() {
		if len(cur) == 0 {
			return
		}
		items := append([]logicalLine{}, cur...)
		sortImports(items)
		for _, ln := range items {
			out = append(out, renderLine(ln, 0))
		}
		cur = cur[:0]
	}
	for _, ln := range block {
		if ln.onlyComments() {
			flush()
			out = append(out, renderLine(ln, 0))
			continue
		}
		cur = append(cur, ln)
	}
	flush()
	return out
}

func sortImports(items []logicalLine) {
	keyOf := func(ln logicalLine) (string, bool, string) {
		var path, alias strings.Builder
		target := &path
		for _, t := range ln.toks[1:] {
			if t.isComment() {
				continue
			}
			if t.isKeyword("as") {
				target = &alias
				continue
			}
			target.WriteString(t.text)
		}
		return path.String(), alias.Len() > 0, alias.String()
	}
	// 稳定插入排序：块内通常 < 20 行。
	for i := 1; i < len(items); i++ {
		for j := i; j > 0; j-- {
			p1, a1, n1 := keyOf(items[j-1])
			p2, a2, n2 := keyOf(items[j])
			less := p2 < p1
			if p1 == p2 {
				if a2 != a1 {
					less = !a2 && a1 // 无别名在前
				} else {
					less = n2 < n1
				}
			}
			if !less {
				break
			}
			items[j-1], items[j] = items[j], items[j-1]
		}
	}
}

type braceCtx struct {
	isSwitch bool
	base     int
	caseOpen bool
}

// renderBody 处理正文：缩进（R4）、空行（R5）、行内空白（R6–R8）。
func renderBody(body []logicalLine) []string {
	var out []string
	b, p := 0, 0
	var stack []braceCtx
	for i, ln := range body {
		first := ln.first()
		if i > 0 {
			prev := body[i-1]
			gap := ln.line - prev.endLine - 1
			if gap > 0 && prev.last().text != "{" && first.text != "}" {
				out = append(out, "")
			}
		}
		bEff := b
		if first.text == "}" {
			bEff--
		}
		level := bEff
		if p > 0 {
			level = bEff + p
			if first.text == ")" || first.text == "]" {
				level--
			}
		} else if top, ok := nearestSwitch(stack); ok && top.caseOpen && bEff > top.base &&
			first.text != "case" && !first.isKeyword("default") && first.text != "}" {
			level++
		}
		if level < 0 {
			level = 0
		}
		out = append(out, renderLine(ln, level))

		if first.text == "case" || first.isKeyword("default") {
			if idx, ok := nearestSwitchIndex(stack); ok {
				stack[idx].caseOpen = true
			}
		}
		for k, t := range ln.toks {
			switch t.text {
			case "{":
				stack = append(stack, braceCtx{isSwitch: switchBefore(ln, k), base: b})
				b++
			case "}":
				if n := len(stack); n > 0 {
					stack = stack[:n-1]
				}
				if b > 0 {
					b--
				}
			case "(", "[":
				p++
			case ")", "]":
				if p > 0 {
					p--
				}
			}
		}
	}
	return out
}

func nearestSwitch(stack []braceCtx) (braceCtx, bool) {
	idx, ok := nearestSwitchIndex(stack)
	if !ok {
		return braceCtx{}, false
	}
	return stack[idx], true
}

func nearestSwitchIndex(stack []braceCtx) (int, bool) {
	for i := len(stack) - 1; i >= 0; i-- {
		if stack[i].isSwitch {
			return i, true
		}
	}
	return 0, false
}

// switchBefore 判断同一行该 `{` 之前是否以 switch 开头（R4.3 的 switchBase 归属）。
func switchBefore(ln logicalLine, braceIdx int) bool {
	for k := braceIdx - 1; k >= 0; k-- {
		t := ln.toks[k]
		if t.isComment() {
			continue
		}
		switch t.text {
		case "switch":
			return true
		case "{", "}", ";", "case":
			return false
		}
	}
	return false
}

func indent(level int) string { return strings.Repeat("    ", level) }

func renderLine(ln logicalLine, level int) string {
	var b strings.Builder
	b.WriteString(indent(level))
	for i, t := range ln.toks {
		if i > 0 && needSpace(ln.toks[i-1], t) {
			b.WriteString(" ")
		}
		b.WriteString(t.text)
	}
	// R3.4：行尾空白删除（行注释正文尾部的空格/制表符；块注释与多行字面量内部不动）
	if last := ln.last(); last.kind == tkComment && !strings.Contains(last.text, "\n") {
		return strings.TrimRight(b.String(), " \t")
	}
	return b.String()
}

// needSpace 是 R6–R8 的「两个相邻 token 之间是否 1 个空格」唯一实现。
func needSpace(prev, cur token) bool {
	if prev.isComment() || cur.isComment() {
		return true // R6.16
	}
	p, c := prev.text, cur.text

	// R6.2 / R6.3：`)` `]` `,` `;` 之前 0 空格
	switch c {
	case ")", "]", ",", ";":
		return false
	}
	// R6.1：`(` `[` 之后 0 空格
	switch p {
	case "(", "[":
		return false
	}
	// R6.4：`.` `?.` 两侧 0 空格
	if c == "." || c == "?." || p == "." || p == "?." {
		return false
	}
	// R6.5 / R6.6：调用/下标/类型后缀紧邻
	if c == "(" && atomBeforeParen(prev) {
		return false
	}
	if c == "[" && atomBeforeParen(prev) {
		return false
	}
	// R8.8 / R8.10：泛型括号与其内容之间 0 空格（闭合符之后按默认规则，见样例 F）
	if cur.genericOpen || prev.genericOpen || cur.genericClose {
		return false
	}
	// R8.4：可空后缀 `?` 贴住其类型（`String?`）；`?` 之后按默认（样例 F：`String? note`）
	if c == "?" && cur.nullableQ {
		return false
	}
	// R8.5：非配对冒号之前 0 空格（配对的三元冒号两侧 1 空格）
	if c == ":" && !cur.ternaryColon {
		return false
	}
	// R6.18：区间运算符两侧 0 空格
	if c == "..<" || c == "..." || p == "..<" || p == "..." {
		return false
	}
	// R6.8：一元前缀之后 / 后缀 ++ -- 之前 0 空格
	if prev.unaryPrefix || cur.unaryPostfix {
		return false
	}
	// R6.9 / R6.12：`}` 与 `{`/内容
	if c == "}" {
		return p != "{" // 空体 `{}` 0 空格
	}
	// R6.10 / R6.11：`{` 之前、之后 1 空格
	if c == "{" || p == "{" {
		return true
	}
	// R6.13 / R6.14：`,` `;` `:` 之后 1 空格
	if p == "," || p == ";" || p == ":" {
		return true
	}
	return true // R6.17
}

// atomBeforeParen 是 R6.5/R6.6 的「表达式原子」判定（控制关键字除外，R6.15）。
func atomBeforeParen(t token) bool {
	switch t.kind {
	case tkIdent, tkNumber, tkString, tkChar:
		return true
	}
	switch t.text {
	case ")", "]", ">", ">>":
		return true
	}
	return false
}
