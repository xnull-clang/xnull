package ffi

import (
	"fmt"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

// scalarTypes 是 S7 §3.2 标量映射表的 XNull 侧类型名。
var scalarTypes = map[string]bool{
	"Int": true, "UInt": true,
	"Int8": true, "Int16": true, "Int32": true, "Int64": true,
	"UInt8": true, "UInt16": true, "UInt32": true, "UInt64": true,
	"Float": true, "Float32": true, "Float64": true,
	"Bool": true, "Char": true,
}

// bannedTypeNames 给出不可跨界类型的专门诊断文案（S7 §3.6）。
var bannedTypeNames = map[string]string{
	"Result":   "Result 不跨语言边界（S7 §3.6 / INV-FFI-2）：错误经错误码出参交付",
	"List":     "容器不跨边界（S7 §3.6）；需要时改为标量数组或句柄",
	"Map":      "容器不跨边界（S7 §3.6）；需要时改为标量数组或句柄",
	"Set":      "容器不跨边界（S7 §3.6）；需要时改为标量数组或句柄",
	"Tuple":    "元组无跨边界合同（S7 §3.6）",
	"Fn":       "闭包不跨边界；回调经 trampoline 注册（S7 §5.1）",
	"Closure":  "闭包不跨边界；回调经 trampoline 注册（S7 §5.1）",
	"Optional": "可选类型不跨边界（S7 §3.6）；NULL 语义由绑定包装层处理",
}

// errorKinds 是允许的错误分类名（S4 附录 A）。
var errorKinds = map[string]bool{
	"Invalid": true, "NotFound": true, "Permission": true, "Conflict": true,
	"Cancelled": true, "Timeout": true, "Internal": true, "Limit": true,
	"Unavailable": true,
}

var knownAnnotations = map[string]bool{
	"ffiEntry": true, "lease": true, "errorCode": true,
	"blocking": true, "longRunning": true, "unsafe": true,
}

func firstAnn(as []annotation, name string) *annotation {
	for i := range as {
		if as[i].Name == name {
			return &as[i]
		}
	}
	return nil
}

func annValue(a *annotation, key string) (string, bool) {
	for _, x := range a.Args {
		if x.Key == key {
			return x.Value, true
		}
	}
	return "", false
}

// checker 对单个 ffi 块做合同校验并产出注册表条目。
type checker struct {
	file    string
	rg      *region
	diags   []Diagnostic
	layouts map[string]*layoutSrc
	handles map[string]*handleSrc
	entries map[string]*entrySrc
	out     *Registry
}

func newChecker(file string, rg *region, out *Registry) *checker {
	return &checker{
		file: file, rg: rg, out: out,
		layouts: map[string]*layoutSrc{},
		handles: map[string]*handleSrc{},
		entries: map[string]*entrySrc{},
	}
}

func (c *checker) diag(p pos, code, msg string) {
	c.diags = append(c.diags, Diagnostic{
		File: c.file, Line: p.Line, Col: p.Col, Code: code, Message: msg,
	})
}

func (c *checker) run() []Diagnostic {
	c.collectNames()
	c.checkLayouts()
	c.checkHandles()
	c.checkEntries()
	c.checkHandleClose()
	return c.diags
}

// collectNames 登记声明名并检测同名重复（FFI-111），同时输出结构/句柄声明。
func (c *checker) collectNames() {
	for _, ls := range c.rg.Layouts {
		if _, dup := c.layouts[ls.Name]; dup {
			c.diag(ls.Pos, "FFI-111", "重复的 layout(c) 结构声明 "+ls.Name)
			continue
		}
		if _, dup := findLayout(c.out, ls.Name); dup {
			c.diag(ls.Pos, "FFI-111", "layout(c) 结构 "+ls.Name+" 在其它声明块重复")
			continue
		}
		c.layouts[ls.Name] = ls
		fields := make([]LayoutField, 0, len(ls.Fields))
		for _, f := range ls.Fields {
			fields = append(fields, LayoutField{Name: f.Name, Type: f.Type})
		}
		c.out.Layouts = append(c.out.Layouts, Layout{Name: ls.Name, Region: c.rg.Name, Fields: fields})
	}
	for _, h := range c.rg.Handles {
		if _, dup := c.handles[h.Name]; dup {
			c.diag(h.Pos, "FFI-111", "重复的句柄声明 "+h.Name)
			continue
		}
		if _, dup := findHandle(c.out, h.Name); dup {
			c.diag(h.Pos, "FFI-111", "句柄 "+h.Name+" 在其它声明块重复")
			continue
		}
		c.handles[h.Name] = h
		c.out.Handles = append(c.out.Handles, Handle{Name: h.Name, Region: c.rg.Name, Close: h.Close})
	}
	for _, e := range c.rg.Entries {
		if _, dup := c.entries[e.Name]; dup {
			c.diag(e.Pos, "FFI-111", "重复的入口声明 "+e.Name)
			continue
		}
		c.entries[e.Name] = e
	}
}

func findLayout(r *Registry, name string) (Layout, bool) {
	for i := range r.Layouts {
		if r.Layouts[i].Name == name {
			return r.Layouts[i], true
		}
	}
	return Layout{}, false
}

func findHandle(r *Registry, name string) (Handle, bool) {
	for i := range r.Handles {
		if r.Handles[i].Name == name {
			return r.Handles[i], true
		}
	}
	return Handle{}, false
}

// checkLayouts 校验 layout(c)：字段限标量与嵌套 layout(c)，禁递归，字段名唯一。
func (c *checker) checkLayouts() {
	for _, ls := range c.rg.Layouts {
		seen := map[string]bool{}
		for _, f := range ls.Fields {
			if seen[f.Name] {
				c.diag(f.Pos, "FFI-109", "结构 "+ls.Name+" 重复字段 "+f.Name)
			}
			seen[f.Name] = true
			if scalarTypes[f.Type] {
				continue
			}
			if _, ok := c.layouts[f.Type]; ok {
				continue
			}
			c.diag(f.Pos, "FFI-109", fmt.Sprintf(
				"字段 %s.%s 类型 %s 非法：layout(c) 字段限标量或嵌套 layout(c) 结构（S7 §3.3）",
				ls.Name, f.Name, f.Type))
		}
		if len(ls.Fields) == 0 {
			c.diag(ls.Pos, "FFI-109", "layout(c) 结构 "+ls.Name+" 至少需要一个字段")
		}
		// 递归值包含检查（S7 §3.3、STRUCT-01）
		if path := c.findLayoutCycle(ls.Name, map[string]bool{}, nil); len(path) > 0 {
			c.diag(ls.Pos, "FFI-109", "layout(c) 结构递归包含："+strings.Join(path, " → "))
		}
	}
}

func (c *checker) findLayoutCycle(name string, onPath map[string]bool, path []string) []string {
	if onPath[name] {
		return append(path, name)
	}
	ls, ok := c.layouts[name]
	if !ok {
		return nil
	}
	onPath[name] = true
	defer delete(onPath, name)
	for _, f := range ls.Fields {
		if _, nested := c.layouts[f.Type]; !nested {
			continue
		}
		if cyc := c.findLayoutCycle(f.Type, onPath, append(path, name)); len(cyc) > 0 {
			return cyc
		}
	}
	return nil
}

// checkHandles 校验句柄声明：close 入口必须存在且签名匹配（S7 §4.3）。
func (c *checker) checkHandles() {
	for _, h := range c.rg.Handles {
		if h.Close == "" {
			c.diag(h.Pos, "FFI-105", "句柄 "+h.Name+" 缺少 close 入口声明（S7 §4.3）")
			continue
		}
		if _, ok := c.entries[h.Close]; !ok {
			c.diag(h.Pos, "FFI-105", "句柄 "+h.Name+" 的 close 入口 "+h.Close+" 未声明")
		}
	}
}

// checkHandleClose 在入口解析完成后校验 close 签名：恰一个该句柄类型参数。
func (c *checker) checkHandleClose() {
	for _, h := range c.rg.Handles {
		e, ok := c.entries[h.Close]
		if !ok {
			continue
		}
		if len(e.Params) != 1 {
			c.diag(e.Pos, "FFI-105", "close 入口 "+e.Name+" 必须恰好一个句柄参数（S7 §4.3）")
			continue
		}
		if len(e.Params) == 1 && e.Params[0].Type.Name != h.Name {
			c.diag(e.Pos, "FFI-105", "close 入口 "+e.Name+" 的参数必须是句柄 "+h.Name)
		}
	}
}

// checkEntries 逐入口校验注解、类型、租约、错误码、阻塞分类与 @unsafe。
func (c *checker) checkEntries() {
	// 区域级：可归还的参数类型集合（.reclaim）与句柄类型集合
	claimTypes := map[string]bool{}
	for _, e := range c.rg.Entries {
		la := firstAnn(e.Anns, "lease")
		if la == nil {
			continue
		}
		for _, a := range la.Args {
			if a.Key == "" {
				continue
			}
			if lk, ok := parseLease(a.Value); ok && lk == LeaseClaim {
				for _, p := range e.Params {
					if p.Name == a.Key {
						claimTypes[boundKey(c, p.Type)] = true
					}
				}
			}
		}
	}
	for _, e := range c.rg.Entries {
		c.checkEntry(e, claimTypes)
	}
}

// boundKey 生成类型的结构键（用于归还配对判定）。
func boundKey(c *checker, t typeRef) string {
	bt, ok := c.quietBound(t)
	if !ok {
		return "?" + t.Name
	}
	return bt.String()
}

func (c *checker) checkEntry(e *entrySrc, claimTypes map[string]bool) {
	// 跨声明块重名：直接跳过，避免注册表出现两个同名入口
	if _, dup := c.out.Entry(e.Name); dup {
		c.diag(e.Pos, "FFI-111", "入口 "+e.Name+" 在其它声明块重复")
		return
	}
	// 注解名合法性
	for _, a := range e.Anns {
		if !knownAnnotations[a.Name] {
			c.diag(a.Pos, "FFI-101", "未知注解 @"+a.Name+"（绑定层声明仅支持 ffiEntry/lease/errorCode/blocking/longRunning/unsafe）")
		}
	}

	entry := Entry{Name: e.Name, Region: c.rg.Name}
	cname := ""
	if fe := firstAnn(e.Anns, "ffiEntry"); fe == nil {
		c.diag(e.Pos, "FFI-101", "入口 "+e.Name+" 缺少 @ffiEntry(cName = ...)（S7 §2.2）")
	} else if v, ok := annValue(fe, "cName"); !ok || v == "" {
		c.diag(fe.Pos, "FFI-101", "入口 "+e.Name+" 的 @ffiEntry 缺少非空 cName")
	} else {
		cname = v
	}
	entry.CName = cname

	ret, okRet := c.bound(e.Ret, true)
	entry.Ret = ret
	params := make([]Param, 0, len(e.Params))
	typeOK := okRet
	for _, p := range e.Params {
		bt, ok := c.bound(p.Type, false)
		if !ok {
			typeOK = false
		}
		params = append(params, Param{Name: p.Name, Type: bt})
	}
	entry.Params = params
	if !typeOK {
		return // 类型层已报诊断，后续租约/错误码校验依赖类型，跳过
	}

	// 租约（逐参数覆盖，缺省即违规 S7 §2.2 / INV-FFI-1）
	lease := make([]LeaseKind, len(params))
	if la := firstAnn(e.Anns, "lease"); la == nil {
		/* 逐参数全覆盖对零参数入口是空真：此时允许省略 @lease（S7 §2.2） */
		if len(params) > 0 {
			c.diag(e.Pos, "FFI-101", "入口 "+e.Name+" 缺少 @lease 声明（INV-FFI-1：无租约声明的入口被拒绝）")
		}
	} else {
		neverReclaim, _ := annValue(la, "neverReclaim")
		named := map[string]bool{}
		for _, a := range la.Args {
			if a.Key == "" || a.Key == "neverReclaim" {
				continue
			}
			idx := -1
			for i, p := range params {
				if p.Name == a.Key {
					idx = i
					break
				}
			}
			if idx < 0 {
				c.diag(a.Pos, "FFI-101", "租约引用了不存在的参数 "+a.Key)
				continue
			}
			lk, ok := parseLease(a.Value)
			if !ok {
				c.diag(a.Pos, "FFI-101", "租约值非法（限 .borrow/.transfer/.reclaim）："+a.Value)
				continue
			}
			lease[idx] = lk
			named[a.Key] = true
		}
		for i, p := range params {
			if !named[p.Name] {
				c.diag(e.Pos, "FFI-101", "参数 "+p.Name+" 缺少租约声明（逐参数声明，S7 §2.2）")
			}
			if p.Type.Kind == KindString || p.Type.Kind == KindText {
				if lease[i] == LeaseTransfer || lease[i] == LeaseClaim {
					c.diag(e.Pos, "FFI-103", "String/Text 不可移交或归还（S7 §3.4）：参数 "+p.Name+" 需改为 .borrow 或用 Bytes 复制")
				}
			}
			if lease[i] == LeaseTransfer {
				tk := p.Type.String()
				pairOK := claimTypes[tk] || p.Type.Kind == KindHandle
				if !pairOK && neverReclaim == "" {
					c.diag(e.Pos, "FFI-102", "参数 "+p.Name+" 声明 .transfer 但无对称 .reclaim 入口，且未声明 neverReclaim 理由（S7 §2.2）")
				}
			}
		}
	}
	entry.Lease = lease

	// 错误码通道（S7 §7.1）
	if ec := firstAnn(e.Anns, "errorCode"); ec != nil {
		v, ok := annValue(ec, "codeParam")
		if !ok {
			c.diag(ec.Pos, "FFI-106", "@errorCode 缺少 codeParam 参数")
		} else {
			ch := strings.TrimPrefix(v, ".")
			if ch == "result" || ch == "return" {
				if ret.Kind != KindScalar || ret.Name != "Int32" {
					c.diag(ec.Pos, "FFI-106", "错误码即返回值时返回类型必须是 Int32（S7 §7.1 基准约定）")
				}
				entry.ErrorCodeRet = true
			} else {
				found := false
				for _, p := range params {
					if p.Name == ch {
						found = true
						if p.Type.Kind != KindScalar || p.Type.Name != "Int32" {
							c.diag(ec.Pos, "FFI-106", "错误码出参 "+ch+" 必须是 Int32（S7 §7.1 基准约定）")
						}
					}
				}
				if !found {
					c.diag(ec.Pos, "FFI-106", "错误码出参 "+ch+" 不在参数列表")
				}
				entry.ErrorCode = ch
			}
		}
	}

	// 阻塞分类（S7 §7.3）
	if bl := firstAnn(e.Anns, "blocking"); bl != nil {
		for _, a := range bl.Args {
			switch a.Value {
			case ".aware":
				entry.Blocking = BlockingAware
			case ".unaware":
				entry.Blocking = BlockingUnaware
			default:
				c.diag(a.Pos, "FFI-107", "阻塞分类非法（限 .aware/.unaware）："+a.Value)
			}
		}
		if entry.Blocking == BlockingUnclassified {
			c.diag(bl.Pos, "FFI-107", "入口 "+e.Name+" 的 @blocking 缺少分类值（S7 §7.3）")
		}
	} else {
		c.diag(e.Pos, "FFI-107", "入口 "+e.Name+" 缺少 @blocking 分类声明（S7 §7.3 / FFI-07）")
	}
	if firstAnn(e.Anns, "longRunning") != nil {
		entry.LongRunning = true
		if entry.Blocking == BlockingUnaware {
			if _, ok := c.entries["submit"+e.Name]; !ok {
				c.diag(e.Pos, "FFI-107", "长阻塞入口 "+e.Name+" 缺少专用执行器伴生入口 submit"+e.Name+"（S7 §7.3）")
			}
		}
	}

	// @unsafe 受控入口（S7 §8）
	if us := firstAnn(e.Anns, "unsafe"); us != nil {
		entry.Unsafe = true
		txt, _ := annValue(us, "contract")
		entry.ContractText = txt
		if strings.TrimSpace(txt) == "" {
			c.diag(us.Pos, "FFI-110", "@unsafe 入口 "+e.Name+" 必须声明 contract 前提与违规后果（S7 §8）")
		}
		if !underBindings(c.file) {
			c.diag(us.Pos, "FFI-110", "@unsafe 入口只能出现在绑定层目录 bindings/ 下（S7 §8）："+c.file)
		}
	}

	// 错误码映射表（区域级，随入口输出便于消费）
	if len(c.rg.ErrMap) > 0 {
		rules := make([]ErrRule, 0, len(c.rg.ErrMap))
		for _, r := range c.rg.ErrMap {
			if !errorKinds[r.Kind] {
				c.diag(r.Pos, "FFI-106", "未知错误分类 "+r.Kind+"（S4 附录 A 分类名）")
				continue
			}
			rules = append(rules, ErrRule{Code: r.Code, Kind: r.Kind})
		}
		sort.Slice(rules, func(i, j int) bool { return rules[i].Code < rules[j].Code })
		entry.ErrorMap = rules
	}

	// 句柄 close 归属
	for _, h := range c.rg.Handles {
		if h.Close == e.Name {
			entry.CloseOf = h.Name
		}
	}

	c.out.Entries = append(c.out.Entries, entry)
}

// parseLease 解析租约值。
func parseLease(v string) (LeaseKind, bool) {
	switch v {
	case ".borrow":
		return LeaseBorrow, true
	case ".transfer":
		return LeaseTransfer, true
	case ".reclaim":
		return LeaseClaim, true
	default:
		return LeaseNone, false
	}
}

// underBindings 判断声明文件是否位于绑定层目录（bindings/）。
func underBindings(file string) bool {
	p := filepath.ToSlash(file)
	return strings.HasPrefix(p, "bindings/") || strings.Contains(p, "/bindings/")
}

// resolve 解析类型引用但不报诊断（code 为空表示成功）。
func (c *checker) resolve(t typeRef, isRet bool) (BoundType, string, string) {
	if t.ArrayDim > 1 {
		return BoundType{}, "FFI-104", "嵌套数组不直接跨边界（S7 §3.5）：按逐行缓冲区处理"
	}
	if t.Optional {
		return BoundType{}, "FFI-105", "可选类型不跨边界（S7 §3.6）；NULL 语义由绑定包装层处理"
	}
	if strings.Contains(t.Name, "*") {
		return BoundType{}, "FFI-108", "不提供裸指针类型（S7 §3.2）；边界表示由类型编组表决定"
	}
	var base BoundType
	switch {
	case t.Name == "Void":
		if !isRet {
			return BoundType{}, "FFI-105", "Void 仅可作为返回类型"
		}
		base = BoundType{Kind: KindVoid, Name: "Void"}
	case scalarTypes[t.Name]:
		base = BoundType{Kind: KindScalar, Name: t.Name}
	case t.Name == "String":
		base = BoundType{Kind: KindString, Name: "String"}
	case t.Name == "Text":
		base = BoundType{Kind: KindText, Name: "Text"}
	case t.Name == "Bytes":
		base = BoundType{Kind: KindBytes, Name: "Bytes"}
	case c.handles[t.Name] != nil:
		base = BoundType{Kind: KindHandle, Name: t.Name}
	case c.layouts[t.Name] != nil:
		base = BoundType{Kind: KindLayout, Name: t.Name}
	default:
		if msg, ok := bannedTypeNames[t.Name]; ok {
			return BoundType{}, "FFI-105", msg
		}
		return BoundType{}, "FFI-105", fmt.Sprintf(
			"类型 %s 不跨边界（S7 §2.1/§3.6；未声明的句柄或 layout(c) 结构亦不可用）", t.Name)
	}
	if t.ArrayDim == 1 {
		if base.Kind != KindScalar && base.Kind != KindLayout {
			return BoundType{}, "FFI-104", "数组元素限于标量或 layout(c) 结构（S7 §3.5）：" + base.String()
		}
		return BoundType{Kind: KindArray, Elem: &base}, "", ""
	}
	return base, "", ""
}

// bound 解析类型引用为边界类型；失败时报诊断。
func (c *checker) bound(t typeRef, isRet bool) (BoundType, bool) {
	bt, code, msg := c.resolve(t, isRet)
	if code != "" {
		c.diag(t.Pos, code, msg)
		return BoundType{}, false
	}
	return bt, true
}

// quietBound 仅供配对判定使用（不产生诊断）。
func (c *checker) quietBound(t typeRef) (BoundType, bool) {
	bt, code, _ := c.resolve(t, false)
	return bt, code == ""
}

// parseI32 供测试与外部工具使用。
func parseI32(s string) (int32, bool) {
	v, err := strconv.ParseInt(s, 10, 32)
	if err != nil {
		return 0, false
	}
	return int32(v), true
}
