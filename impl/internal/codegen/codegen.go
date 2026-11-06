// Package codegen 把语义检查通过的 XNull 程序生成 C 源码（M4.1）。
//
// 消费 impl/runtime 的 ABI（rt.h/rt_gc.h）：Int→int64_t、Bool→int、
// String→rt_string*（单一所有权：字符串求值结果由消耗语句构造并在用后
// 释放，xn_concat/xn_str_* 返回新串）、Result<T,E>→按实例化的值结构体。
// defer/errdefer 以退出点内联清理序列实现（§10.3：块退出/return/try
// 传播执行，errdefer 仅在函数以 Err 返回时执行）；throw/fatal 走
// xn_throw（fprintf+exit(134)，§10.4 不展开栈）。
//
// M4.1 范围：三示例特征面（Int/Bool/String、拼接、print/str、
// Result 成员、defer/errdefer、if/while/return、局部声明/赋值、顶层
// 函数调用）。类声明、容器、闭包等随 M4 后续批次扩展；超出范围的
// 构造返回错误，不静默降级。
package codegen

import (
	"fmt"
	"sort"
	"strconv"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

// prelude 是生成文件的运行时前置（impl/runtime ABI + 打印/字符串助手）。
const prelude = `/* 由 XNull 编译器生成（M4.1 代码生成）。 */
#include "rt.h"
#include "rt_gc.h"
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void xn_print_int(int64_t v) { printf("%lld\n", (long long)v); }
static void xn_print_bool(int v) { fputs(v ? "true\n" : "false\n", stdout); }
static void xn_print_str(rt_string *s) { printf("%.*s\n", (int)s->len, s->bytes); }

static rt_string *xn_str_int(int64_t v) {
    char buf[32];
    int n = snprintf(buf, sizeof(buf), "%lld", (long long)v);
    return rt_string_new(buf, (size_t)n);
}

/* 按分配头合同构造定长字符串（S3 §2：计数从 1 起）。 */
static rt_string *xn_alloc_str(size_t n);

/* ---- String 成员（S1 §9.2，字节语义）---- */
static int xn_str_eq(rt_string *a, rt_string *b) {
    return a->len == b->len && memcmp(a->bytes, b->bytes, a->len) == 0;
}

static int64_t xn_str_length(rt_string *s) { return (int64_t)s->len; }

static rt_string *xn_str_substr(rt_string *s, int64_t start, int64_t n) {
    if (start < 0) { start = 0; }
    if (n < 0) { n = 0; }
    if ((size_t)start > s->len) { start = (int64_t)s->len; }
    if ((size_t)(start + n) > s->len) { n = (int64_t)s->len - start; }
    rt_string *out = xn_alloc_str((size_t)n);
    if (n > 0) { memcpy(out->bytes, s->bytes + start, (size_t)n); }
    return out;
}

static int64_t xn_str_indexof(rt_string *s, rt_string *sub) {
    if (sub->len == 0) { return 0; }
    if (sub->len > s->len) { return -1; }
    for (size_t i = 0; i + sub->len <= s->len; i++) {
        if (memcmp(s->bytes + i, sub->bytes, sub->len) == 0) { return (int64_t)i; }
    }
    return -1;
}

static int xn_str_startswith(rt_string *s, rt_string *p) {
    if (p->len > s->len) { return 0; }
    return memcmp(s->bytes, p->bytes, p->len) == 0;
}

static int xn_str_endswith(rt_string *s, rt_string *p) {
    if (p->len > s->len) { return 0; }
    return memcmp(s->bytes + (s->len - p->len), p->bytes, p->len) == 0;
}

static int xn_is_space(uint8_t c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\v' || c == '\f' || c == '\r';
}

static rt_string *xn_str_trim(rt_string *s) {
    size_t b = 0, e = s->len;
    while (b < e && xn_is_space((uint8_t)s->bytes[b])) { b++; }
    while (e > b && xn_is_space((uint8_t)s->bytes[e - 1])) { e--; }
    return xn_str_substr(s, (int64_t)b, (int64_t)(e - b));
}

static rt_string *xn_str_upper(rt_string *s) {
    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);
    for (size_t i = 0; i < out->len; i++) {
        char c = out->bytes[i];
        if (c >= 'a' && c <= 'z') { out->bytes[i] = (char)(c - 'a' + 'A'); }
    }
    return out;
}

static rt_string *xn_str_lower(rt_string *s) {
    rt_string *out = xn_str_substr(s, 0, (int64_t)s->len);
    for (size_t i = 0; i < out->len; i++) {
        char c = out->bytes[i];
        if (c >= 'A' && c <= 'Z') { out->bytes[i] = (char)(c - 'A' + 'a'); }
    }
    return out;
}

static rt_string *xn_alloc_str(size_t n) {
    rt_string *s = malloc(sizeof(rt_string) + n + 1);
    if (s == NULL) { abort(); }
    memset(s, 0, sizeof(rt_string) + n + 1);
    s->hdr.kind = RT_KIND_ARC;
    s->hdr.type = &RT_TYPE_STRING;
    atomic_init(&s->hdr.refcount, 1);
    s->len = n;
    s->bytes[n] = 0;
    return s;
}

/* 拼接：接管 a、b 的所有权，返回新串。 */
static rt_string *xn_concat(rt_string *a, rt_string *b) {
    rt_string *out = xn_alloc_str(a->len + b->len);
    memcpy(out->bytes, a->bytes, a->len);
    memcpy(out->bytes + a->len, b->bytes, b->len);
    rt_release(a);
    rt_release(b);
    return out;
}

static void xn_throw(rt_string *msg) {
    fprintf(stderr, "fatal: %.*s\n", (int)msg->len, msg->bytes);
    exit(134);
}
`

// EmitC 生成完整 C 翻译单元文本。
func EmitC(u *xfront.CompilationUnit) (string, error) {
	g := &gen{results: map[string]string{}, cs: newContainers(), fnRet: map[string]string{}, classes: map[string]*classInfo{}}
	for _, d := range u.Decls {
		if fn, ok := d.(*xfront.TopFunc); ok {
			if err := g.collectResult(fn); err != nil {
				return "", err
			}
		}
	}
	// 类收集（字段/方法签名；M4.4b 单类无继承无协议）
	for _, d := range u.Decls {
		if c, ok := d.(*xfront.ClassDecl); ok {
			if err := g.collectClass(c); err != nil {
				return "", err
			}
		}
	}
	// 函数签名表（类型推断消费）
	seenFn := map[string]bool{}
	for _, d := range u.Decls {
		if fn, ok := d.(*xfront.TopFunc); ok {
			if seenFn[fn.Name] {
				return "", fmt.Errorf("codegen：顶层函数 `%s` 重载未支持（§4.4 重载属 M4.5+；当前同名函数在 C 侧冲突）", fn.Name)
			}
			seenFn[fn.Name] = true
			rc, err := g.cType(fn.Ret)
			if err != nil {
				return "", err
			}
			if fn.Void {
				rc = "void"
			}
			g.fnRet[fn.Name] = rc
		}
	}
	// 第一遍：试生成以收集 Result/容器实例化（产物丢弃）
	for _, d := range u.Decls {
		switch n := d.(type) {
		case *xfront.TopFunc:
			if _, err := g.genFunc(n); err != nil {
				return "", err
			}
		case *xfront.ClassDecl:
			ci := g.classes[n.Name]
			for _, m := range ci.methods {
				if _, err := g.genMethod(ci, m); err != nil {
					return "", err
				}
			}
		default:
			return "", fmt.Errorf("codegen：顶层声明 %T 未支持（M4.1 范围：顶层函数/类）", d)
		}
	}
	g.tmp = 0
	var fns []string
	// 第二遍：正式生成顶层函数
	for _, d := range u.Decls {
		fn, ok := d.(*xfront.TopFunc)
		if !ok {
			continue
		}
		c, err := g.genFunc(fn)
		if err != nil {
			return "", err
		}
		fns = append(fns, c)
	}
	var b strings.Builder
	b.WriteString(prelude)
	names := make([]string, 0, len(g.results))
	for name := range g.results {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		member := "int64_t"
		if strings.HasPrefix(name, "xn_Result_Bool_") {
			member = "int"
		}
		fmt.Fprintf(&b, "typedef struct { int ok; %s v; rt_string *err; } %s;\n", member, name)
	}
	b.WriteString("\n")
	b.WriteString("static void xn_fatal_oob(void);\n")
	b.WriteString("static void xn_fatal_oob(void) {\n")
	b.WriteString("    fprintf(stderr, \"fatal: 容器下标越界\\n\");\n")
	b.WriteString("    exit(134);\n")
	b.WriteString("}\n\n")
	g.cs.emitForwardDecls(&b)
	g.cs.emit(&b)
	// 类结构/构造/方法（M4.4b）：容器与 Result typedef 已就位
	for _, d := range u.Decls {
		if n, ok := d.(*xfront.ClassDecl); ok {
			ci := g.classes[n.Name]
			g.emitClassStruct(&b, ci)
			if err := g.emitClassCtor(&b, ci); err != nil {
				return "", err
			}
			// 方法前向声明（方法间互相调用与声明顺序无关）
			for _, md := range n.Methods {
				if md.IsDeinit {
					continue
				}
				m := ci.methods[md.Name]
				proto, err := g.methodProto(ci, m)
				if err != nil {
					return "", err
				}
				b.WriteString(proto + "\n")
			}
			b.WriteString("\n")
			for _, md := range n.Methods {
				if md.IsDeinit {
					continue
				}
				mc, err := g.genMethod(ci, ci.methods[md.Name])
				if err != nil {
					return "", err
				}
				b.WriteString(mc + "\n")
			}
		}
	}
	b.WriteString("static rt_string *xn_result_error_copy_rt(rt_string *err) {\n")
	b.WriteString("    return rt_string_new(err->bytes, err->len);\n")
	b.WriteString("}\n\n")
	for _, fn := range fns {
		b.WriteString(fn)
		b.WriteString("\n")
	}
	// C 入口：调用 XNull main，返回值作进程退出码；回收会合释放隔离区
	mainVoid := false
	for _, d := range u.Decls {
		if fn, ok := d.(*xfront.TopFunc); ok && fn.Name == "main" {
			mainVoid = fn.Void
		}
	}
	if mainVoid {
		b.WriteString("int main(void) { xn_main(); rt_quarantine_flush(); return 0; }\n")
	} else {
		b.WriteString("int main(void) { int64_t xn_r = xn_main(); rt_quarantine_flush(); return (int)xn_r; }\n")
	}
	return b.String(), nil
}

type gen struct {
	results map[string]string     // Result 实例化名 → v 成员类型
	cs      *containers           // 容器实例化注册表（M4.4a）
	fnRet   map[string]string     // 顶层函数名 → 返回 C 类型（类型推断用）
	classes map[string]*classInfo // 类名 → 生成信息（M4.4b）
	tmp     int
}

// typeName 取 NamedType 的末段名（x.y.z → z）。
func typeName(nt *xfront.NamedType) string {
	if len(nt.Qual) == 0 {
		return ""
	}
	return nt.Qual[len(nt.Qual)-1]
}

func resultName(args []xfront.TypeRef) (string, error) {
	if len(args) != 2 {
		return "", fmt.Errorf("codegen：Result 需要两个类型实参")
	}
	vt, ok := args[0].(*xfront.NamedType)
	if !ok {
		return "", fmt.Errorf("codegen：Result 值类型 %T 未支持", args[0])
	}
	et, ok := args[1].(*xfront.NamedType)
	if !ok || typeName(et) != "String" {
		return "", fmt.Errorf("codegen：Result 错误类型暂仅支持 String（M4.1 范围）")
	}
	switch typeName(vt) {
	case "Int":
		return "xn_Result_Int_String", nil
	case "Bool":
		return "xn_Result_Bool_String", nil
	}
	return "", fmt.Errorf("codegen：Result 值类型暂支持 Int/Bool，got %s", typeName(vt))
}

func (g *gen) collectResult(fn *xfront.TopFunc) error {
	if !fn.Void {
		if nt, ok := fn.Ret.(*xfront.NamedType); ok && typeName(nt) == "Result" {
			name, err := resultName(nt.Args)
			if err != nil {
				return err
			}
			g.results[name] = ""
		}
	}
	return g.collectBlock(fn.Body)
}

func (g *gen) collectBlock(b *xfront.Block) error {
	for _, st := range b.Stmts {
		if err := g.collectStmt(st); err != nil {
			return err
		}
	}
	return nil
}

func (g *gen) collectStmt(st xfront.Stmt) error {
	switch n := st.(type) {
	case *xfront.LocalDeclStmt:
		if nt, ok := n.Type.(*xfront.NamedType); ok && typeName(nt) == "Result" {
			name, err := resultName(nt.Args)
			if err != nil {
				return err
			}
			g.results[name] = ""
		}
	case *xfront.IfStmt:
		if err := g.collectBlock(n.Then); err != nil {
			return err
		}
		if eb, ok := n.Else.(*xfront.Block); ok {
			return g.collectBlock(eb)
		}
		if n.Else != nil {
			return g.collectStmt(n.Else)
		}
	case *xfront.WhileStmt:
		return g.collectBlock(n.Body)
	case *xfront.DeferStmt:
		if n.Block != nil {
			return g.collectBlock(n.Block)
		}
	}
	return nil
}

func (g *gen) cType(t xfront.TypeRef) (string, error) {
	switch n := t.(type) {
	case nil:
		return "void", nil
	case *xfront.SuffixedType:
		if len(n.Suffixes) == 1 && n.Suffixes[0] == "[]" {
			ec, err := g.cType(n.Base)
			if err != nil {
				return "", err
			}
			if err := g.cs.needArr(ec); err != nil {
				return "", err
			}
			return arrName(ec), nil
		}
		return "", fmt.Errorf("codegen：类型后缀 %v 未支持（M4.4a 范围）", n.Suffixes)
	case *xfront.NamedType:
		switch typeName(n) {
		case "Int":
			return "int64_t", nil
		case "Bool":
			return "int", nil
		case "String":
			return "rt_string *", nil
		case "List":
			if len(n.Args) != 1 {
				return "", fmt.Errorf("codegen：List 需要一个类型实参")
			}
			ec, err := g.cType(n.Args[0])
			if err != nil {
				return "", err
			}
			if err := g.cs.needArr(ec); err != nil {
				return "", err
			}
			return arrName(ec), nil
		case "Set":
			if len(n.Args) != 1 {
				return "", fmt.Errorf("codegen：Set 需要一个类型实参")
			}
			ec, err := g.cType(n.Args[0])
			if err != nil {
				return "", err
			}
			if err := g.cs.needSet(ec); err != nil {
				return "", err
			}
			return setName(ec), nil
		case "Map":
			if len(n.Args) != 2 {
				return "", fmt.Errorf("codegen：Map 需要两个类型实参")
			}
			kc, err := g.cType(n.Args[0])
			if err != nil {
				return "", err
			}
			vc, err := g.cType(n.Args[1])
			if err != nil {
				return "", err
			}
			if err := g.cs.needMap(kc, vc); err != nil {
				return "", err
			}
			return mapName(kc, vc), nil
		case "Result":
			return resultName(n.Args)
		default:
			if _, ok := g.classOf(typeName(n)); ok {
				return "xn_Cls_" + typeName(n) + " *", nil
			}
		case "void":
			return "void", nil
		}
	}
	if nt, ok := t.(*xfront.NamedType); ok {
		return "", fmt.Errorf("codegen：类型 %s 未支持（M4.1 范围）", typeName(nt))
	}
	return "", fmt.Errorf("codegen：类型 %T 未支持（M4.1 范围）", t)
}

// ---------- 函数 ----------

func (g *gen) genFunc(fn *xfront.TopFunc) (string, error) {
	retC, err := g.cType(fn.Ret)
	if err != nil {
		return "", err
	}
	if fn.Void {
		retC = "void"
	}
	var params []string
	for _, p := range fn.Params {
		pc, err := g.cType(p.Type)
		if err != nil {
			return "", err
		}
		params = append(params, pc+" xn_p_"+p.Name)
	}
	hasResult := retC == "xn_Result_Int_String" || retC == "xn_Result_Bool_String"
	pnames := map[string]bool{}
	locals := map[string]string{}
	for _, p := range fn.Params {
		pnames[p.Name] = true
		if pc, err := g.cType(p.Type); err == nil {
			locals[p.Name] = pc
		}
	}
	sc := &scope{g: g, retC: retC, hasResult: hasResult, params: pnames, locals: locals}
	body, err := sc.emitBlock(fn.Body.Stmts)
	if err != nil {
		return "", err
	}
	var b strings.Builder
	fmt.Fprintf(&b, "%s xn_%s(%s) {\n", retC, fn.Name, strings.Join(params, ", "))
	if hasResult {
		b.WriteString("    xn_Result_Int_String xn_ret;\n")
	}
	b.WriteString(body)
	// 函数体末尾自然退出的 defer 已由 emitBlock 的块退出清理承载
	//（errdefer 不触发：无返回发生，§10.3）
	if hasResult && !sc.returned {
		// 自然落到函数末尾（无 return）：C 结构体零值即 ok=0（Err 语义由 sema 保证不可达）
		b.WriteString("    xn_Result_Int_String xn_zero = {0};\n")
		b.WriteString("    xn_ret = xn_zero;\n")
		b.WriteString("    return xn_ret;\n")
	}
	b.WriteString("}\n")
	return b.String(), nil
}

// ---------- 作用域与 defer（§10.3） ----------

type deferItem struct {
	errdefer bool
	lines    []string // 缩进 8 的 C 语句
}

type scope struct {
	g         *gen
	retC      string
	hasResult bool
	defers    []deferItem       // 本块注册的清理（LIFO）
	pending   []string          // 表达式求值产生的临时声明（语句边界冲刷到输出）
	params    map[string]bool   // 参数名（C 侧带 xn_p_ 前缀）
	locals    map[string]string // 局部变量 → C 类型（for-in/容器成员查找）
	returned  bool              // 末句已生成 return（块退出清理跳过）
}

// localCType 查局部变量 C 类型（含参数；参数按其声明类型登记）。
func (s *scope) localCType(name string) (string, bool) {
	c, ok := s.locals[name]
	return c, ok
}

// newChild 生成继承函数级状态的子作用域（if/while 体等块级范围）。
func (s *scope) newChild() *scope {
	locals := map[string]string{}
	for k, v := range s.locals {
		locals[k] = v
	}
	return &scope{g: s.g, retC: s.retC, hasResult: s.hasResult, params: s.params, locals: locals}
}

func (s *scope) tmp() string {
	s.g.tmp++
	return fmt.Sprintf("xn_t%d", s.g.tmp)
}

// emitCleanup 生成清理序列（注册逆序）。condErr 为 true 时 errdefer 以
// 运行时 `xn_ret.ok` 判定（return / try 传播路径）；false 时跳过 errdefer
// （普通块退出/Ok 返回不触发，§10.3）。
func (s *scope) emitCleanup(condErr bool, indent string) string {
	var out []string
	for i := len(s.defers) - 1; i >= 0; i-- {
		d := s.defers[i]
		if d.errdefer {
			if !s.hasResult || !condErr {
				continue
			}
			out = append(out, indent+"if (!xn_ret.ok) {")
			out = append(out, d.lines...)
			out = append(out, indent+"}")
		} else {
			out = append(out, indent+"{")
			out = append(out, d.lines...)
			out = append(out, indent+"}")
		}
	}
	return strings.Join(out, "\n") + trailingNewline(out)
}

func trailingNewline(lines []string) string {
	if len(lines) == 0 {
		return ""
	}
	return "\n"
}

// emitBlock 生成语句序列；块退出时执行本块注册的 defer（errdefer 不触发）。
func (s *scope) emitBlock(stmts []xfront.Stmt) (string, error) {
	var out []string
	for _, st := range stmts {
		lines, err := s.emitStmt(st)
		if err != nil {
			return "", err
		}
		out = append(out, lines...)
	}
	// 块退出清理（跳过 errdefer）；末句是 return 时清理已随返回路径生成
	if !s.returned {
		for i := len(s.defers) - 1; i >= 0; i-- {
			d := s.defers[i]
			if !d.errdefer {
				out = append(out, "    {")
				out = append(out, reindent(d.lines, "    ")...)
				out = append(out, "    }")
			}
		}
	}
	return strings.Join(out, "\n") + trailingNewline(out), nil
}

// ---------- 语句 ----------

func (s *scope) emitStmt(st xfront.Stmt) ([]string, error) {
	out := s.pending
	s.pending = nil
	lines, err := s.emitStmtInner(st)
	if err != nil {
		return nil, err
	}
	out = append(out, s.pending...)
	s.pending = nil
	return append(out, lines...), nil
}

func (s *scope) emitStmtInner(st xfront.Stmt) ([]string, error) {
	switch n := st.(type) {
	case *xfront.ExprStmt:
		return s.emitExprStmt(n.X)
	case *xfront.LocalDeclStmt:
		return s.emitLocalDecl(n)
	case *xfront.AssignStmt:
		return s.emitAssign(n)
	case *xfront.ReturnStmt:
		return s.emitReturn(n)
	case *xfront.IfStmt:
		return s.emitIf(n)
	case *xfront.WhileStmt:
		cond, err := s.cond(n.Cond)
		if err != nil {
			return nil, err
		}
		// 条件求值产生前置语句（字符串临时等）时不能在循环外提升：
		// 降级为 while(1){ 前置; if(!cond) break; 体 }——每轮重新求值，
		// continue 跳到顶部同样重新求值（语义等价 §6.4）。
		if len(s.pending) > 0 {
			pre := append([]string{}, s.pending...)
			s.pending = nil
			bodySc := s.newChild()
			body, err := bodySc.emitBlock(n.Body.Stmts)
			if err != nil {
				return nil, err
			}
			out := []string{"    while (1) {"}
			out = append(out, reindent(pre, "        ")...)
			out = append(out, "        if (!("+cond+")) { break; }")
			out = append(out, reindent(splitLines(body), "        ")...)
			out = append(out, "    }")
			return out, nil
		}
		bodySc := s.newChild()
		body, err := bodySc.emitBlock(n.Body.Stmts)
		if err != nil {
			return nil, err
		}
		return append([]string{"    while (" + cond + ") {"}, append(reindent(splitLines(body), "    "), "    }")...), nil
	case *xfront.ForStmt:
		return s.emitForIn(n)
	case *xfront.DeferStmt:
		var lines []string
		if n.Block != nil {
			for _, st := range n.Block.Stmts {
				ls, err := s.emitStmt(st)
				if err != nil {
					return nil, err
				}
				lines = append(lines, ls...)
			}
		} else {
			ls, err := s.emitStmt(n.Stmt)
			if err != nil {
				return nil, err
			}
			lines = ls
		}
		s.defers = append(s.defers, deferItem{errdefer: n.Errdefer, lines: reindent(lines, "        ")})
		return nil, nil
	case *xfront.ThrowStmt:
		v, err := s.strExprOne(n.Value)
		if err != nil {
			return nil, err
		}
		out := append([]string{}, s.pending...)
		s.pending = nil
		return append(out, "xn_throw("+v+");"), nil
	}
	return nil, fmt.Errorf("codegen：语句 %T 未支持（M4.1 范围）", st)
}

func reindent(lines []string, indent string) []string {
	out := make([]string, len(lines))
	for i, l := range lines {
		if l == "" {
			out[i] = l
		} else {
			out[i] = indent + l
		}
	}
	return out
}

// emitExprStmt 表达式语句：print(...) 或 void 调用。
func (s *scope) emitExprStmt(e xfront.Expr) ([]string, error) {
	call, ok := e.(*xfront.Call)
	if !ok {
		return nil, fmt.Errorf("codegen：表达式语句 %T 未支持（M4.1 范围）", e)
	}
	if mem, ok := call.Callee.(*xfront.Member); ok {
		if rn, rc, err := recvCName(mem.X, s); err == nil {
			if isClassPtr(rc) {
				if v, hit, err := s.classMemberValue(rc, rn, mem, call.Args); err != nil {
					return nil, err
				} else if hit {
					out := append([]string{}, s.pending...)
					s.pending = nil
					return append(out, v+";"), nil
				}
			}
			if isContainerC(rc) {
				lines, hit, err := s.containerMemberStmt(rc, rn, mem.Name, call.Args)
				if err != nil {
					return nil, err
				}
				if hit {
					return lines, nil
				}
			}
		}
		return nil, fmt.Errorf("codegen：成员调用 %s 未支持（M4.4a 范围）", mem.Name)
	}
	id, ok := call.Callee.(*xfront.IdentExpr)
	if !ok {
		return nil, fmt.Errorf("codegen：调用目标 %T 未支持", call.Callee)
	}
	if id.Name == "print" {
		return s.emitPrint(call.Args[0])
	}
	if id.Name == "str" {
		return nil, fmt.Errorf("codegen：str(...) 结果被丢弃（sema 应拒绝）")
	}
	args, err := s.callArgs(call.Args)
	if err != nil {
		return nil, err
	}
	return []string{"xn_" + id.Name + "(" + strings.Join(args, ", ") + ");"}, nil
}

// emitForIn 生成 `for x in src { }`：容器遍历（M4.4a；整型区间随区间表达式批次）。
func (s *scope) emitForIn(n *xfront.ForStmt) ([]string, error) {
	// 源：容器局部变量或字段链（self.kids 等，M5.1-b）
	srcName, srcC, err := recvCName(n.Src, s)
	if err != nil || !isContainerC(srcC) {
		return nil, fmt.Errorf("codegen：for-in 源 %T 不是容器（M4.4a/M5.1-b 范围）", n.Src)
	}
	elem, ok := containerElem(srcC)
	if !ok {
		return nil, fmt.Errorf("codegen：for-in 元素类型推不出（%s）", srcC)
	}
	acc := srcName
	if strings.HasPrefix(srcC, "xn_set_") {
		acc += ".a"
	}
	bodySc := s.newChild()
	bodySc.locals = map[string]string{}
	if s.locals != nil {
		for k, v := range s.locals {
			bodySc.locals[k] = v
		}
	}
	bodySc.locals[n.Var] = elem
	body, err := bodySc.emitBlock(n.Body.Stmts)
	if err != nil {
		return nil, err
	}
	idx := s.tmp()
	lines := []string{
		"for (size_t " + idx + " = 0; " + idx + " < " + acc + ".len; " + idx + "++) {",
		"    " + elem + " " + n.Var + " = " + acc + ".data[" + idx + "];",
	}
	lines = append(lines, reindent(splitLines(body), "    ")...)
	lines = append(lines, "}")
	return lines, nil
}

// emitPrint 按静态类型分派 print：String（自有临时）/Bool/Int。
// 借用形态（容器元素 get/下标读）不释放——所有权在容器。
func (s *scope) emitPrint(e xfront.Expr) ([]string, error) {
	t, err := s.exprType(e)
	if err != nil {
		return nil, err
	}
	switch t {
	case "rt_string *":
		if s.isBorrowExpr(e) {
			v, err := s.borrowStr(e)
			if err != nil {
				return nil, err
			}
			return []string{"xn_print_str(" + v + ");"}, nil
		}
		lines, err := s.strExpr(e)
		if err != nil {
			return nil, err
		}
		tv := lastVar(lines)
		return append(lines, "xn_print_str("+tv+");", "rt_release("+tv+");"), nil
	case "int":
		v, err := s.boolExpr(e)
		if err != nil {
			return nil, err
		}
		return []string{"xn_print_bool(" + v + ");"}, nil
	case "int64_t":
		v, err := s.intExpr(e)
		if err != nil {
			return nil, err
		}
		return []string{"xn_print_int(" + v + ");"}, nil
	}
	return nil, fmt.Errorf("codegen：print 实参类型 %s 未支持（M4.4a 范围）", t)
}

// isBorrowExpr 判断字符串表达式是否为借用（不拥有所有权）。
func (s *scope) isBorrowExpr(e xfront.Expr) bool {
	switch n := e.(type) {
	case *xfront.Index:
		return true
	case *xfront.Member:
		return true
	case *xfront.Call:
		if mem, ok := n.Callee.(*xfront.Member); ok && mem.Name == "get" {
			return true
		}
	}
	return false
}

// borrowStr 生成借用字符串表达式（不产生所有权）。
func (s *scope) borrowStr(e xfront.Expr) (string, error) {
	switch n := e.(type) {
	case *xfront.Member:
		recvName, recvC, err := recvCName(n.X, s)
		if err != nil {
			return "", err
		}
		if ci, ok := s.g.classOfC(recvC); ok {
			if f, ok2 := ci.fieldOf(n.Name); ok2 && f.isStr {
				return recvName + "->" + f.cname, nil
			}
		}
		return "", fmt.Errorf("codegen：String 成员 %s 借用不可判定（M4.4b 范围）", n.Name)
	case *xfront.Index:
		return s.indexRead(n)
	case *xfront.Call:
		if mem, ok := n.Callee.(*xfront.Member); ok {
			if rn, rc, err := recvCName(mem.X, s); err == nil && isContainerC(rc) {
				if v, hit, err := s.containerMemberValue(rc, rn, mem.Name, n.Args); err != nil {
					return "", err
				} else if hit {
					return v, nil
				}
			}
		}
	}
	return "", fmt.Errorf("codegen：借用字符串表达式 %T 未支持（M4.4a 范围）", e)
}

// boolExpr 生成 C 布尔值表达式。
func (s *scope) boolExpr(e xfront.Expr) (string, error) {
	if c, err := s.cond(e); err == nil {
		return c, nil
	}
	return s.intExpr(e)
}

func (s *scope) isStrShape(e xfront.Expr) bool {
	switch n := e.(type) {
	case *xfront.StrLitExpr:
		return true
	case *xfront.Binary:
		if n.Op == "+" {
			return s.isStrShape(n.L)
		}
	}
	return false
}

// emitLocalDecl 局部声明。
func (s *scope) emitLocalDecl(n *xfront.LocalDeclStmt) ([]string, error) {
	tc, err := s.g.cType(n.Type)
	if err != nil {
		return nil, err
	}
	if isClassPtr(tc) {
		if n.Init == nil {
			return nil, fmt.Errorf("codegen：类实例局部声明需要 new 初始化（M4.4b 范围）")
		}
		if nw, ok := n.Init.(*xfront.New); ok {
			ctor, err := s.emitNewClass(nw)
			if err != nil {
				return nil, err
			}
			s.defers = append(s.defers, deferItem{lines: []string{"rt_release(" + n.Name + ");"}})
			s.locals[n.Name] = tc
			return []string{tc + " " + n.Name + " = " + ctor + ";"}, nil
		}
		if cl, ok := n.Init.(*xfront.Call); ok {
			expr, owns, err := s.classCallExpr(cl)
			if err != nil {
				return nil, err
			}
			lines := append([]string{}, s.pending...)
			s.pending = nil
			if owns {
				s.defers = append(s.defers, deferItem{lines: []string{"rt_release(" + n.Name + ");"}})
			}
			s.locals[n.Name] = tc
			return append(lines, tc+" "+n.Name+" = "+expr+";"), nil
		}
		return nil, fmt.Errorf("codegen：类实例局部初始值只支持 new/调用（M5.1-b 范围：%T）", n.Init)
	}
	if isContainerC(tc) {
		if n.Init == nil {
			return nil, fmt.Errorf("codegen：容器局部声明需要初始化（M4.4a 范围）")
		}
		lines, v, err := s.valExpr(n.Init, tc)
		if err != nil {
			return nil, err
		}
		s.defers = append(s.defers, deferItem{lines: []string{tc + "_free(&" + n.Name + ");"}})
		s.locals[n.Name] = tc
		return append(lines, tc+" "+n.Name+" = "+v+";"), nil
	}
	switch tc {
	case "rt_string *":
		if n.Init == nil {
			return []string{"rt_string *" + n.Name + " = rt_string_from_c(\"\");"}, nil
		}
		// try 形态：Result 局部 + 解包（此处类型是 String，不支持）
		lines, err := s.strExpr(n.Init)
		if err != nil {
			return nil, err
		}
		t := lastVar(lines)
		// 所有权移交局部：函数退出时释放（追加到本层 defer）
		s.defers = append(s.defers, deferItem{lines: []string{"rt_release(" + n.Name + ");"}})
		s.locals[n.Name] = tc
		// 把最后一行的临时声明直接改名为目标变量（保留其前置语句）
		out := append([]string{}, lines[:len(lines)-1]...)
		last := strings.Replace(lines[len(lines)-1], "rt_string *"+t+" =", "rt_string *"+n.Name+" =", 1)
		return append(out, last), nil
	case "xn_Result_Int_String", "xn_Result_Bool_String":
		// try 形态：`Result<...> r = try f(x)` 或 `T v = try f(x)`（v 取 .v）
		if n.Init != nil {
			if u, ok := n.Init.(*xfront.Unary); ok && u.Op == "try" {
				return s.emitTryInto(tc, n.Name, u.X)
			}
		}
		v, err := s.resultExpr(n.Init, tc)
		if err != nil {
			return nil, err
		}
		out := append([]string{}, s.pending...)
		s.pending = nil
		s.locals[n.Name] = tc
		return append(out, tc+" "+n.Name+" = "+v+";"), nil
	default:
		// Int/Bool；try 形态解包 .v
		if n.Init != nil {
			if u, ok := n.Init.(*xfront.Unary); ok && u.Op == "try" {
				t := s.tmp()
				lines, err := s.emitTryInto("xn_Result_Int_String", t, u.X)
				if err != nil {
					return nil, err
				}
				return append(lines, tc+" "+n.Name+" = "+t+".v;"), nil
			}
			v, err := s.intExpr(n.Init)
			if err != nil {
				return nil, err
			}
			s.locals[n.Name] = tc
			return []string{tc + " " + n.Name + " = " + v + ";"}, nil
		}
		s.locals[n.Name] = tc
		return []string{tc + " " + n.Name + " = 0;"}, nil
	}
}

// emitTryInto 生成 try 传播：临时 Result ← 调用；失败则接管清理并返回。
// 目标变量名 name 接收整个 Result 结构。
func (s *scope) emitTryInto(resultC, name string, callExpr xfront.Expr) ([]string, error) {
	call, ok := callExpr.(*xfront.Call)
	if !ok {
		return nil, fmt.Errorf("codegen：try 实参必须是调用，got %T", callExpr)
	}
	id, ok := call.Callee.(*xfront.IdentExpr)
	if !ok {
		return nil, fmt.Errorf("codegen：try 调用目标 %T 未支持", call.Callee)
	}
	args, err := s.callArgs(call.Args)
	if err != nil {
		return nil, err
	}
	lines := []string{
		resultC + " " + name + " = xn_" + id.Name + "(" + strings.Join(args, ", ") + ");",
		"if (!" + name + ".ok) {",
	}
	// try 传播 = 以 Err 返回：全部 defer 执行，errdefer 触发（xn_ret 为 Err）
	lines = append(lines, "    xn_ret = "+name+";")
	lines = append(lines, reindent(splitLines(strings.TrimSuffix(s.emitCleanup(true, ""), "\n")), "        ")...)
	lines = append(lines, "    return xn_ret;", "}")
	return lines, nil
}

func (s *scope) emitAssign(n *xfront.AssignStmt) ([]string, error) {
	if n.Op != "=" {
		return nil, fmt.Errorf("codegen：复合赋值 %s 未支持（M4.1 范围）", n.Op)
	}
	if mem, ok := n.Target.(*xfront.Member); ok {
		return s.emitFieldAssign(mem, n.Value)
	}
	if idx, ok := n.Target.(*xfront.Index); ok {
		return s.emitIndexAssign(idx, n.Value)
	}
	id, ok := n.Target.(*xfront.IdentExpr)
	if !ok {
		return nil, fmt.Errorf("codegen：赋值目标 %T 未支持（M4.1 范围）", n.Target)
	}
	// String 局部：新串接管，旧串释放（§9.2 不可变字符串）
	if tc, ok := s.localCType(id.Name); ok && tc == "rt_string *" {
		lines, err := s.strExpr(n.Value)
		if err != nil {
			return nil, err
		}
		t := lastVar(lines)
		name := id.Name
		out := append([]string{}, lines...)
		out = append(out, "rt_release("+name+");")
		out = append(out, name+" = "+t+";")
		return out, nil
	}
	v, err := s.intExpr(n.Value)
	if err != nil {
		return nil, err
	}
	return []string{id.Name + " = " + v + ";"}, nil
}

func (s *scope) emitReturn(n *xfront.ReturnStmt) ([]string, error) {
	if s.retC == "void" {
		if n.Value != nil {
			return nil, fmt.Errorf("codegen：void 函数不得带返回值")
		}
		out := []string{}
		out = append(out, splitLines(s.emitCleanup(true, "    "))...)
		s.returned = true
		return append(out, "return;"), nil
	}
	if isClassPtr(s.retC) && n.Value != nil {
		// 类引用返回：与 String 同一纪律——标识符 retain 后返回（本层 defer release 抵消）；
		// new 调用产物直接移交（无需 retain）。
		if id, ok := n.Value.(*xfront.IdentExpr); ok {
			name := id.Name
			if s.params != nil && s.params[name] {
				name = "xn_p_" + name
			}
			out := append([]string{}, s.pending...)
			s.pending = nil
			out = append(out, "rt_retain("+name+");")
			out = append(out, splitLines(s.emitCleanup(true, "    "))...)
			s.returned = true
			return append(out, "return "+name+";"), nil
		}
		if nw, ok := n.Value.(*xfront.New); ok {
			ctor, err := s.emitNewClass(nw)
			if err != nil {
				return nil, err
			}
			t := s.tmp()
			out := append([]string{}, s.pending...)
			s.pending = nil
			out = append(out, retBase(s.retC)+t+" = "+ctor+";")
			out = append(out, splitLines(s.emitCleanup(true, "    "))...)
			s.returned = true
			return append(out, "return "+t+";"), nil
		}
		return nil, fmt.Errorf("codegen：类返回表达式 %T 未支持（M5.1-b 范围：局部变量/new）", n.Value)
	}
	if s.retC == "rt_string *" && n.Value != nil {
		// 标识符返回：retain 后返回（局部清理仍会 release 本层引用）
		if id, ok := n.Value.(*xfront.IdentExpr); ok {
			name := id.Name
			if s.params != nil && s.params[name] {
				name = "xn_p_" + name
			}
			out := append([]string{}, s.pending...)
			s.pending = nil
			out = append(out, "rt_retain("+name+");")
			out = append(out, splitLines(s.emitCleanup(true, "    "))...)
			s.returned = true
			return append(out, "return "+name+";"), nil
		}
		lines, err := s.strExpr(n.Value)
		if err != nil {
			return nil, err
		}
		t := lastVar(lines)
		out := append([]string{}, lines...)
		out = append(out, splitLines(s.emitCleanup(true, "    "))...)
		s.returned = true
		return append(out, "return "+t+";"), nil
	}
	if (s.retC == "int64_t" || s.retC == "int") && n.Value != nil {
		v, err := s.intExpr(n.Value)
		if err != nil {
			return nil, err
		}
		out := splitLines(s.emitCleanup(true, "    "))
		s.returned = true
		return append(out, "return "+v+";"), nil
	}
	switch v := n.Value.(type) {
	case *xfront.Call:
		if id, ok := v.Callee.(*xfront.IdentExpr); ok && (id.Name == "Ok" || id.Name == "Err") {
			structLit, err := s.resultExpr(v, s.retC)
			if err != nil {
				return nil, err
			}
			out := append([]string{}, s.pending...)
			s.pending = nil
			out = append(out, "xn_ret = "+structLit+";")
			out = append(out, splitLines(s.emitCleanup(true, "    "))...)
			s.returned = true
			return append(out, "return xn_ret;"), nil
		}
		// 返回函数调用结果（Result）
		args, err := s.callArgs(v.Args)
		if err != nil {
			return nil, err
		}
		callee, ok := v.Callee.(*xfront.IdentExpr)
		if !ok {
			return nil, fmt.Errorf("codegen：返回调用目标 %T 未支持", v.Callee)
		}
		out := append([]string{}, s.pending...)
		s.pending = nil
		out = append(out, "xn_ret = xn_"+callee.Name+"("+strings.Join(args, ", ")+");")
		out = append(out, splitLines(s.emitCleanup(true, "    "))...)
		s.returned = true
		return append(out, "return xn_ret;"), nil
	}
	return nil, fmt.Errorf("codegen：返回表达式 %T 未支持（M4.1 范围）", n.Value)
}

func (s *scope) emitIf(n *xfront.IfStmt) ([]string, error) {
	cond, err := s.cond(n.Cond)
	if err != nil {
		return nil, err
	}
	thenSc := s.newChild()
	thenBody, err := thenSc.emitBlock(n.Then.Stmts)
	if err != nil {
		return nil, err
	}
	var out []string
	out = append(out, "if ("+cond+") {")
	out = append(out, reindent(splitLines(thenBody), "    ")...)
	if n.Else == nil {
		out = append(out, "}")
		return indentAll(out), nil
	}
	out = append(out, "} else {")
	if eb, ok := n.Else.(*xfront.Block); ok {
		elseSc := s.newChild()
		elseBody, err := elseSc.emitBlock(eb.Stmts)
		if err != nil {
			return nil, err
		}
		out = append(out, reindent(splitLines(elseBody), "    ")...)
	} else {
		elseSc := s.newChild()
		elseLines, err := elseSc.emitStmt(n.Else)
		if err != nil {
			return nil, err
		}
		out = append(out, reindent(elseLines, "    ")...)
	}
	out = append(out, "}")
	return indentAll(out), nil
}

func indentAll(lines []string) []string {
	return reindent(lines, "    ")
}

func splitLines(s string) []string {
	if s == "" {
		return nil
	}
	return strings.Split(s, "\n")
}

// ---------- 表达式（strExpr 约定：返回的语句序列把结果放进最后一个声明的临时） ----------

func lastVar(lines []string) string {
	l := lines[len(lines)-1]
	// "rt_string *xn_tN = ..." → 取 = 左侧最后一个标识符
	if i := strings.Index(l, "="); i >= 0 {
		f := strings.Fields(l[:i])
		if len(f) > 0 {
			return strings.TrimPrefix(f[len(f)-1], "*")
		}
	}
	return l
}

// strExpr 生成"拥有 rt_string*"的字符串值；结果存入最后一个临时变量。
func (s *scope) strExpr(e xfront.Expr) ([]string, error) {
	switch n := e.(type) {
	case *xfront.StrLitExpr:
		t := s.tmp()
		return []string{"rt_string *" + t + " = rt_string_from_c(" + cQuote(plainText(n)) + ");"}, nil
	case *xfront.Binary:
		if n.Op == "+" {
			var out []string
			ls, err := s.strExpr(n.L)
			if err != nil {
				return nil, err
			}
			rs, err := s.strExpr(n.R)
			if err != nil {
				return nil, err
			}
			out = append(out, ls...)
			out = append(out, rs...)
			t := s.tmp()
			out = append(out, "rt_string *"+t+" = xn_concat("+lastVar(ls)+", "+lastVar(rs)+");")
			return out, nil // xn_concat 接管两侧所有权
		}
	case *xfront.Call:
		if id, ok := n.Callee.(*xfront.IdentExpr); ok && id.Name == "str" {
			v, err := s.intExpr(n.Args[0])
			if err != nil {
				return nil, err
			}
			t := s.tmp()
			return []string{"rt_string *" + t + " = xn_str_int(" + v + ");"}, nil
		}
		if id, ok := n.Callee.(*xfront.IdentExpr); ok {
			if ret, ok2 := s.g.fnRet[id.Name]; ok2 && ret == "rt_string *" {
				args, err := s.callArgs(n.Args)
				if err != nil {
					return nil, err
				}
				t := s.tmp()
				out := append([]string{}, s.pending...)
				s.pending = nil
				return append(out, "rt_string *"+t+" = xn_"+id.Name+"("+strings.Join(args, ", ")+");"), nil
			}
		}
		if mem, ok := n.Callee.(*xfront.Member); ok {
			if rt, err2 := s.exprType(mem.X); err2 == nil && rt == "rt_string *" {
				call, hit, err := s.strMemberValue(mem, n.Args, true)
				if err != nil {
					return nil, err
				}
				if hit {
					t := s.tmp()
					out := append([]string{}, s.pending...)
					s.pending = nil
					return append(out, "rt_string *"+t+" = "+call+";"), nil
				}
			}
			if recv, ok2 := mem.X.(*xfront.IdentExpr); ok2 {
				if rc, ok3 := s.localCType(recv.Name); ok3 && isClassPtr(rc) {
					rn := recv.Name
					if s.params != nil && s.params[rn] {
						rn = "xn_p_" + rn
					}
					call, _, err := s.classMemberValue(rc, rn, mem, n.Args)
					if err != nil {
						return nil, err
					}
					t := s.tmp()
					out := append([]string{}, s.pending...)
					s.pending = nil
					return append(out, "rt_string *"+t+" = "+call+";"), nil
				}
			}
		}
		if mem, ok := n.Callee.(*xfront.Member); ok && mem.Name == "error" {
			if recv, ok2 := mem.X.(*xfront.IdentExpr); ok2 {
				t := s.tmp()
				return []string{"rt_string *" + t + " = xn_result_error_copy_rt(" + recv.Name + ".err);"}, nil
			}
		}
	case *xfront.IdentExpr:
		name := n.Name
		if s.params != nil && s.params[name] {
			name = "xn_p_" + name
		}
		// 借用 → 为消费方取得一份引用（concat 接管两侧所有权）
		t := s.tmp()
		return []string{"rt_string *" + t + " = rt_retain(" + name + ");"}, nil
	case *xfront.Member:
		recvName, recvC, err := recvCName(n.X, s)
		if err != nil {
			return nil, err
		}
		ci, ok := s.g.classOfC(recvC)
		if ok {
			if f, ok2 := ci.fieldOf(n.Name); ok2 && f.isStr {
				t := s.tmp()
				return []string{"rt_string *" + t + " = rt_retain(" + recvName + "->" + f.cname + ");"}, nil
			}
		}
		return nil, fmt.Errorf("codegen：String 成员 %s 的接收者不支持（M4.4b 范围）", n.Name)
	case *xfront.Paren:
		return s.strExpr(n.X)
	}
	return nil, fmt.Errorf("codegen：String 表达式 %T 未支持（M4.1 范围）", e)
}

// resultExpr 生成 Result 值表达式（Ok/Err 构造或函数调用）。
func (s *scope) resultExpr(e xfront.Expr, resultC string) (string, error) {
	switch n := e.(type) {
	case *xfront.Call:
		id, ok := n.Callee.(*xfront.IdentExpr)
		if !ok {
			return "", fmt.Errorf("codegen：Result 表达式目标 %T 未支持", n.Callee)
		}
		switch id.Name {
		case "Ok":
			v, err := s.intExpr(n.Args[0])
			if err != nil {
				return "", err
			}
			return "(" + resultC + "){1, " + v + ", NULL}", nil
		case "Err":
			sv, err := s.strExprOne(n.Args[0])
			if err != nil {
				return "", err
			}
			return "(" + resultC + "){0, 0, " + sv + "}", nil
		}
		args, err := s.callArgs(n.Args)
		if err != nil {
			return "", err
		}
		return "xn_" + id.Name + "(" + strings.Join(args, ", ") + ")", nil
	}
	return "", fmt.Errorf("codegen：Result 表达式 %T 未支持（M4.1 范围）", e)
}

// strExprOne 生成字符串表达式（临时语句 + 最终 C 表达式文本，Err 构造用）。
func (s *scope) strExprOne(e xfront.Expr) (string, error) {
	lines, err := s.strExpr(e)
	if err != nil {
		return "", err
	}
	s.pending = append(s.pending, lines...)
	return lastVar(lines), nil
}

// cond 生成 C 布尔条件。
func (s *scope) cond(e xfront.Expr) (string, error) {
	switch n := e.(type) {
	case *xfront.BoolLit:
		if n.V {
			return "1", nil
		}
		return "0", nil
	case *xfront.Binary:
		switch n.Op {
		case "&&", "||":
			l, err := s.cond(n.L)
			if err != nil {
				return "", err
			}
			r, err := s.cond(n.R)
			if err != nil {
				return "", err
			}
			return "(" + l + " " + n.Op + " " + r + ")", nil
		}
		v, err := s.intExpr(n)
		return "(" + v + ")", err
	}
	// 其余标量形态（局部/字面量/调用）按 Int 处理
	v, err := s.intExpr(e)
	return "(" + v + ")", err
}

// intExpr 生成 int64_t/int 表达式。
func (s *scope) intExpr(e xfront.Expr) (string, error) {
	switch n := e.(type) {
	case *xfront.IntLitExpr:
		v, err := intValue(n)
		if err != nil {
			return "", err
		}
		return strconv.FormatInt(v, 10), nil
	case *xfront.IdentExpr:
		if s.params != nil && s.params[n.Name] {
			return "xn_p_" + n.Name, nil
		}
		return n.Name, nil
	case *xfront.Binary:
		if n.Op == "==" || n.Op == "!=" {
			if lt, err := s.exprType(n.L); err == nil && lt == "rt_string *" {
				ls, err := s.strExpr(n.L)
				if err != nil {
					return "", err
				}
				rs, err := s.strExpr(n.R)
				if err != nil {
					return "", err
				}
				out := append([]string{}, ls...)
				out = append(out, rs...)
				s.pending = append(s.pending, out...)
				eq := "xn_str_eq(" + lastVar(ls) + ", " + lastVar(rs) + ")"
				if n.Op == "!=" {
					return "(!(" + eq + "))", nil
				}
				return eq, nil
			}
		}
		l, err := s.intExpr(n.L)
		if err != nil {
			return "", err
		}
		r, err := s.intExpr(n.R)
		if err != nil {
			return "", err
		}
		return "(" + l + " " + cOp(n.Op) + " " + r + ")", nil
	case *xfront.Paren:
		return s.intExpr(n.X)
	case *xfront.Unary:
		switch n.Op {
		case "!":
			v, err := s.intExpr(n.X)
			if err != nil {
				return "", err
			}
			return "(!(" + v + "))", nil
		case "-":
			v, err := s.intExpr(n.X)
			if err != nil {
				return "", err
			}
			return "(-(" + v + "))", nil
		}
		return "", fmt.Errorf("codegen：一元运算 %s 未支持（M4.4b 范围）", n.Op)
	case *xfront.Index:
		return s.indexRead(n)
	case *xfront.Member:
		recvName, recvC, err := recvCName(n.X, s)
		if err != nil {
			return "", err
		}
		if v, hit, err := s.classMemberValue(recvC, recvName, n, nil); err != nil {
			return "", err
		} else if hit {
			return v, nil
		}
		return "", fmt.Errorf("codegen：成员 %s 的接收者类型 %s 不支持（M4.4b 范围）", n.Name, recvC)
	case *xfront.New:
		return s.emitNewClass(n)
	case *xfront.Call:
		if id, ok := n.Callee.(*xfront.IdentExpr); ok {
			switch id.Name {
			case "Ok", "Err", "print", "str":
				return "", fmt.Errorf("codegen：%s(...) 不能作为 Int 值（M4.4a 范围）", id.Name)
			}
			args, err := s.callArgs(n.Args)
			if err != nil {
				return "", err
			}
			s.pending = append(s.pending, s.flushPendingArgs()...)
			return "xn_" + id.Name + "(" + strings.Join(args, ", ") + ")", nil
		}
		if mem, ok := n.Callee.(*xfront.Member); ok {
			if rt, err2 := s.exprType(mem.X); err2 == nil && rt == "rt_string *" {
				if v, hit, err := s.strMemberValue(mem, n.Args, false); err != nil {
					return "", err
				} else if hit {
					return v, nil
				}
			}
			if recv, ok2 := mem.X.(*xfront.IdentExpr); ok2 {
				if rc, ok3 := s.localCType(recv.Name); ok3 && isClassPtr(rc) {
					rn := recv.Name
					if s.params != nil && s.params[rn] {
						rn = "xn_p_" + rn
					}
					if v, hit, err := s.classMemberValue(rc, rn, mem, n.Args); err != nil {
						return "", err
					} else if hit {
						return v, nil
					}
				}
			}
		}
		if mem, ok := n.Callee.(*xfront.Member); ok {
			if rn, rc, err := recvCName(mem.X, s); err == nil && isContainerC(rc) {
				if v, hit, err := s.containerMemberValue(rc, rn, mem.Name, n.Args); err != nil {
					return "", err
				} else if hit {
					return v, nil
				}
			}
			if recv, ok2 := mem.X.(*xfront.IdentExpr); ok2 {
				switch mem.Name {
				case "isOk":
					return "(" + recv.Name + ").ok", nil
				case "isErr":
					return "(!(" + recv.Name + ").ok)", nil
				case "value":
					return "(" + recv.Name + ").v", nil
				case "unwrapOr":
					arg, err := s.intExpr(n.Args[0])
					if err != nil {
						return "", err
					}
					return "((" + recv.Name + ").ok ? (" + recv.Name + ").v : (" + arg + "))", nil
				}
			}
		}
	}
	return "", fmt.Errorf("codegen：Int 表达式 %T 未支持（M4.1 范围）", e)
}

// retBase 生成返回类型声明前缀（xn_Cls_X * → 'xn_Cls_X *'）。
func retBase(c string) string { return c }

// classCallExpr 生成「返回类引用」的调用表达式。
// 返回 owns=true 表示调用点获得 +1 引用（须释放）；false 为借用（容器 get 等）。
func (s *scope) classCallExpr(cl *xfront.Call) (string, bool, error) {
	switch c := cl.Callee.(type) {
	case *xfront.IdentExpr:
		args, err := s.callArgs(cl.Args)
		if err != nil {
			return "", false, err
		}
		return "xn_" + c.Name + "(" + strings.Join(args, ", ") + ")", true, nil
	case *xfront.Member:
		rn, rc, err := recvCName(c.X, s)
		if err != nil {
			return "", false, err
		}
		if isContainerC(rc) {
			v, hit, err := s.containerMemberValue(rc, rn, c.Name, cl.Args)
			if err != nil {
				return "", false, err
			}
			if hit {
				return v, false, nil // 容器元素借用
			}
		}
		if isClassPtr(rc) {
			v, hit, err := s.classMemberValue(rc, rn, c, cl.Args)
			if err != nil {
				return "", false, err
			}
			if hit {
				return v, true, nil // 方法返回 +1 引用
			}
		}
	}
	return "", false, fmt.Errorf("codegen：类调用表达式被调 %T 未支持（M5.1-b 范围）", cl.Callee)
}

// callArgs 生成调用实参（按推断类型分派：String 临时移交所有权、
// 容器按值传递、标量按值）。
func (s *scope) callArgs(args []xfront.Expr) ([]string, error) {
	var out []string
	for _, a := range args {
		t, err := s.exprType(a)
		if err != nil {
			return nil, err
		}
		switch {
		case t == "rt_string *":
			lines, err := s.strExpr(a)
			if err != nil {
				return nil, err
			}
			s.pending = append(s.pending, lines...)
			out = append(out, lastVar(lines))
		case isClassPtr(t):
			if id, ok := a.(*xfront.IdentExpr); ok {
				name := id.Name
				if s.params != nil && s.params[name] {
					name = "xn_p_" + name
				}
				out = append(out, name)
				continue
			}
			// 临时类实参（M5.1-b）：new / 顶层调用产物 → 本层临时持有、
			// 函数尾统一释放（存活略长于语句但无泄漏、确定性；被调按借用消费）
			if nw, ok := a.(*xfront.New); ok {
				ctor, err := s.emitNewClass(nw)
				if err != nil {
					return nil, err
				}
				tn := s.tmp()
				s.pending = append(s.pending, t+" "+tn+" = "+ctor+";")
				s.defers = append(s.defers, deferItem{lines: []string{"rt_release(" + tn + ");"}})
				out = append(out, tn)
				continue
			}
			if cl, ok := a.(*xfront.Call); ok {
				expr, owns, err := s.classCallExpr(cl)
				if err != nil {
					return nil, err
				}
				if owns {
					tn := s.tmp()
					s.pending = append(s.pending, t+" "+tn+" = "+expr+";")
					s.defers = append(s.defers, deferItem{lines: []string{"rt_release(" + tn + ");"}})
					out = append(out, tn)
				} else {
					out = append(out, expr) // 借用：直传
				}
				continue
			}
			return nil, fmt.Errorf("codegen：类实例实参只支持变量/new/调用（M5.1-b 范围）")
		case isContainerC(t):
			if id, ok := a.(*xfront.IdentExpr); ok {
				name := id.Name
				if s.params != nil && s.params[name] {
					name = "xn_p_" + name
				}
				out = append(out, name)
				continue
			}
			lines, v, err := s.valExpr(a, t)
			if err != nil {
				return nil, err
			}
			s.pending = append(s.pending, lines...)
			out = append(out, v)
		default:
			v, err := s.intExpr(a)
			if err != nil {
				return nil, err
			}
			out = append(out, v)
		}
	}
	return out, nil
}

func intValue(n *xfront.IntLitExpr) (int64, error) {
	text := n.Text
	for _, suf := range []string{"i", "I", "u", "U", "l", "L"} {
		text = strings.TrimSuffix(text, suf)
	}
	return strconv.ParseInt(text, n.Base, 64)
}

func cOp(op string) string { return op }

// cQuote 转 C 字符串字面量（UTF-8 字节直出）。
func cQuote(s string) string {
	var b strings.Builder
	b.WriteByte('"')
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch c {
		case '"':
			b.WriteString("\\\"")
		case '\\':
			b.WriteString("\\\\")
		case '\n':
			b.WriteString("\\n")
		case '\t':
			b.WriteString("\\t")
		case '\r':
			b.WriteString("\\r")
		case '\v':
			b.WriteString("\\v")
		case '\f':
			b.WriteString("\\f")
		default:
			if c < 0x20 || c == 0x7f {
				b.WriteString(fmt.Sprintf("\\%03o", c))
				continue
			}
			b.WriteByte(c)
		}
	}
	b.WriteByte('"')
	return b.String()
}

// plainText 提取无插值字符串字面量的文本。
func plainText(n *xfront.StrLitExpr) string {
	var b strings.Builder
	for _, p := range n.Parts {
		b.WriteString(p.Text)
	}
	return b.String()
}

// flushPendingArgs 取走调用实参求值产生的前置语句。
func (s *scope) flushPendingArgs() []string {
	out := s.pending
	s.pending = nil
	return out
}
