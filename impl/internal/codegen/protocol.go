// protocol.go：协议类型与 vtable 动态派发（S2 §4/§5.6/§5.7）。
//
// 表示（codegen 私有）：
//
//	xn_proto_<P> = void *                        协议类型接收者（对象指针）
//	xn_vt_obj    = { rt_header hdr; void **__vtable; }  对象 vtable 前缀
//	xn_vt_<C>[N] = { [slot] = &实现方法, ... }   每实现类一张槽位表
//
// 槽位按「方法签名」全局唯一（方法名 + 参数 C 类型 + 返回 C 类型），确定顺序。
// 只有协议静态类型接收者走 vtable；类接收者仍静态派发（S2 §5.6）。
package codegen

import (
	"fmt"
	"sort"
	"strconv"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

type protoSig struct {
	name   string
	void   bool
	ret    xfront.TypeRef
	params []*xfront.Param
	slot   int
}

type protoInfo struct {
	name    string
	ctype   string // xn_proto_<Name>
	decl    *xfront.ProtocolDecl
	extends []*protoInfo
	sigs    []*protoSig
}

type protoSlot struct {
	key     string
	void    bool
	retC    string
	paramCs []string
}

// sliceContains 判断协议列表是否包含类型名。
func sliceContains(list []*xfront.NamedType, name string) bool {
	for _, n := range list {
		if typeName(n) == name {
			return true
		}
	}
	return false
}

// collectProtocols 收集协议声明、继承链与全局槽位（确定顺序）。
func (g *gen) collectProtocols(u *xfront.CompilationUnit) error {
	decls := map[string]*xfront.ProtocolDecl{}
	var order []string
	for _, d := range u.Decls {
		if p, ok := d.(*xfront.ProtocolDecl); ok {
			decls[p.Name] = p
			order = append(order, p.Name)
		}
	}
	var visiting map[string]bool
	var build func(name string) (*protoInfo, error)
	build = func(name string) (*protoInfo, error) {
		if pi, ok := g.protocols[name]; ok {
			return pi, nil
		}
		decl, ok := decls[name]
		if !ok {
			return nil, fmt.Errorf("codegen：未定义的协议 %s", name)
		}
		if visiting[name] {
			return nil, fmt.Errorf("codegen：协议继承环（%s）", name)
		}
		visiting[name] = true
		pi := &protoInfo{name: name, ctype: "xn_proto_" + name, decl: decl}
		g.protocols[name] = pi
		for _, ext := range decl.Extends {
			ep, err := build(typeName(ext))
			if err != nil {
				return nil, err
			}
			pi.extends = append(pi.extends, ep)
		}
		visiting[name] = false
		return pi, nil
	}
	visiting = map[string]bool{}
	for _, name := range order {
		if _, err := build(name); err != nil {
			return err
		}
	}
	// 槽位：先父协议、后本协议；按声明顺序；同签名复用。
	for _, name := range order {
		pi := g.protocols[name]
		if err := g.assignProtoSlots(pi, map[string]bool{}); err != nil {
			return err
		}
	}
	return nil
}

// assignProtoSlots 递归登记协议签名槽位。
func (g *gen) assignProtoSlots(pi *protoInfo, seen map[string]bool) error {
	if seen[pi.name] {
		return nil
	}
	seen[pi.name] = true
	for _, ep := range pi.extends {
		if err := g.assignProtoSlots(ep, seen); err != nil {
			return err
		}
	}
	for _, sig := range pi.decl.Sigs {
		paramCs := make([]string, 0, len(sig.Params))
		for _, p := range sig.Params {
			pc, err := g.cType(p.Type)
			if err != nil {
				return err
			}
			paramCs = append(paramCs, pc)
		}
		retC := "void"
		if !sig.Void {
			rc, err := g.cType(sig.Ret)
			if err != nil {
				return err
			}
			retC = rc
		}
		key := sig.Name + "(" + strings.Join(paramCs, ",") + ")->" + retC
		slot, ok := g.protoSlotByKey[key]
		if !ok {
			slot = len(g.slotOrder)
			g.protoSlotByKey[key] = slot
			g.slotOrder = append(g.slotOrder, protoSlot{key: key, void: sig.Void, retC: retC, paramCs: paramCs})
		}
		pi.sigs = append(pi.sigs, &protoSig{name: sig.Name, void: sig.Void, ret: sig.Ret, params: sig.Params, slot: slot})
	}
	return nil
}

// protoSigOf 按方法名与实参个数查协议签名（重载按元数选择）。
func (pi *protoInfo) protoSigOf(name string, argc int) *protoSig {
	var inherited []*protoSig
	var walk func(p *protoInfo, seen map[string]bool)
	walk = func(p *protoInfo, seen map[string]bool) {
		if seen[p.name] {
			return
		}
		seen[p.name] = true
		for _, ep := range p.extends {
			walk(ep, seen)
		}
		inherited = append(inherited, p.sigs...)
	}
	walk(pi, map[string]bool{})
	for _, sig := range inherited {
		if sig.name == name && len(sig.params) == argc {
			return sig
		}
	}
	return nil
}

// isProtoC 判断 C 类型是否为协议类型。
func (g *gen) isProtoC(c string) bool {
	return strings.HasPrefix(c, "xn_proto_")
}

// protoCType 协议名 → C 类型（未登记返回空）。
func (g *gen) protoCType(name string) (string, bool) {
	pi, ok := g.protocols[name]
	if !ok {
		return "", false
	}
	return pi.ctype, true
}

// emitProtocolTypes 输出协议类型与 vtable 对象前缀。
func (g *gen) emitProtocolTypes(b *strings.Builder) {
	if len(g.protocols) == 0 {
		return
	}
	names := make([]string, 0, len(g.protocols))
	for n := range g.protocols {
		names = append(names, n)
	}
	sort.Strings(names)
	for _, n := range names {
		fmt.Fprintf(b, "typedef void *%s;\n", g.protocols[n].ctype)
	}
	b.WriteString("typedef struct { rt_header hdr; void **__vtable; } xn_vt_obj;\n\n")
}

// allProtocols 返回类（含继承链）实现的全部协议。
func (ci *classInfo) allProtocols() []*xfront.NamedType {
	var out []*xfront.NamedType
	seen := map[string]bool{}
	for c := ci; c != nil; c = c.base {
		for _, p := range c.protocols {
			n := typeName(p)
			if !seen[n] {
				seen[n] = true
				out = append(out, p)
			}
		}
	}
	return out
}

// emitVtables 在方法定义之后填充各实现类的槽位表。
func (g *gen) emitVtables(b *strings.Builder) error {
	if len(g.slotOrder) == 0 {
		return nil
	}
	b.WriteString("static void xn_init_vtables(void) {\n")
	names := make([]string, 0, len(g.classes))
	for n := range g.classes {
		names = append(names, n)
	}
	sort.Strings(names)
	for _, n := range names {
		ci := g.classes[n]
		if !ci.vptr {
			continue
		}
		entries := map[int]string{}
		for _, pref := range ci.allProtocols() {
			pi, ok := g.protocols[typeName(pref)]
			if !ok {
				return fmt.Errorf("codegen：类 %s 实现未定义协议 %s", n, typeName(pref))
			}
			var walk func(p *protoInfo, seen map[string]bool) error
			walk = func(p *protoInfo, seen map[string]bool) error {
				if seen[p.name] {
					return nil
				}
				seen[p.name] = true
				for _, ep := range p.extends {
					if err := walk(ep, seen); err != nil {
						return err
					}
				}
				for _, sig := range p.sigs {
					m, ok := ci.methodOfArgs(sig.name, len(sig.params))
					if !ok || len(m.decl.Params) != len(sig.params) || m.ext {
						return fmt.Errorf("codegen：类 %s 未实现协议 %s 的方法 %s（扩展方法不能作协议实现，S2 §11.2）", n, p.name, sig.name)
					}
					entries[sig.slot] = m.cname
				}
				return nil
			}
			if err := walk(pi, map[string]bool{}); err != nil {
				return err
			}
		}
		slots := make([]int, 0, len(entries))
		for s := range entries {
			slots = append(slots, s)
		}
		sort.Ints(slots)
		for _, s := range slots {
			fmt.Fprintf(b, "    xn_vt_%s[%d] = (void *)&%s;\n", n, s, entries[s])
		}
	}
	b.WriteString("}\n\n")
	return nil
}

// protoRecv 生成协议接收者 C 表达式（标识符/括号）。
func (s *scope) protoRecv(e xfront.Expr) (string, error) {
	switch n := e.(type) {
	case *xfront.IdentExpr:
		return s.cRef(n.Name), nil
	case *xfront.Paren:
		return s.protoRecv(n.X)
	case *xfront.Member:
		rn, _, err := recvCName(n, s)
		if err != nil {
			return "", err
		}
		return rn, nil
	}
	return "", fmt.Errorf("codegen：协议接收者 %T 未支持（M4.4b 范围）", e)
}

// protoDispatch 生成协议方法 vtable 调用表达式。
func (s *scope) protoDispatch(mem *xfront.Member, args []xfront.Expr) (string, string, error) {
	rt, err := s.exprType(mem.X)
	if err != nil {
		return "", "", err
	}
	pi, ok := s.g.protocols[strings.TrimPrefix(rt, "xn_proto_")]
	if !ok {
		return "", "", fmt.Errorf("codegen：%s 不是协议类型", rt)
	}
	sig := pi.protoSigOf(mem.Name, len(args))
	if sig == nil {
		return "", "", fmt.Errorf("codegen：协议 %s 没有方法 %s/%d（S2 §4.2）", pi.name, mem.Name, len(args))
	}
	recv, err := s.protoRecv(mem.X)
	if err != nil {
		return "", "", err
	}
	argv, err := s.callArgs(args)
	if err != nil {
		return "", "", err
	}
	si := s.g.slotOrder[sig.slot]
	params := append([]string{"void *"}, si.paramCs...)
	retC := si.retC
	if si.void {
		retC = "void"
	}
	callArgs := append([]string{recv}, argv...)
	expr := "((" + retC + " (*)(" + strings.Join(params, ", ") + "))((xn_vt_obj *)(" + recv + "))->__vtable[" + strconv.Itoa(sig.slot) + "])(" + strings.Join(callArgs, ", ") + ")"
	return expr, retC, nil
}

// protoValue 生成协议值（对象指针）；owned 表示已持 +1。
func (s *scope) protoValue(e xfront.Expr) ([]string, string, bool, error) {
	switch n := e.(type) {
	case *xfront.NullLit:
		return nil, "NULL", false, nil
	case *xfront.Paren:
		return s.protoValue(n.X)
	case *xfront.IdentExpr:
		r := s.cRef(n.Name)
		t := s.tmp()
		return []string{"void *" + t + " = rt_retain((void *)" + r + ");"}, t, true, nil
	case *xfront.New:
		ctor, err := s.emitNewClass(n)
		if err != nil {
			return nil, "", false, err
		}
		lines := append([]string{}, s.pending...)
		s.pending = nil
		return lines, ctor, true, nil
	case *xfront.Call:
		et, err := s.exprType(n)
		if err != nil {
			return nil, "", false, err
		}
		if s.g.isProtoC(et) {
			if id, ok := n.Callee.(*xfront.IdentExpr); ok {
				args, err := s.callArgs(n.Args)
				if err != nil {
					return nil, "", false, err
				}
				cn, err := s.g.callName(id.Name, n.TypeArgs, len(n.Args))
				if err != nil {
					return nil, "", false, err
				}
				lines := append([]string{}, s.pending...)
				s.pending = nil
				return lines, cn + "(" + strings.Join(args, ", ") + ")", true, nil
			}
			mem, ok := n.Callee.(*xfront.Member)
			if !ok {
				return nil, "", false, fmt.Errorf("codegen：协议值调用 %T 未支持", n.Callee)
			}
			expr, _, err := s.protoDispatch(mem, n.Args)
			if err != nil {
				return nil, "", false, err
			}
			lines := append([]string{}, s.pending...)
			s.pending = nil
			t := s.tmp()
			return append(lines, "void *"+t+" = rt_retain((void *)("+expr+"));"), t, true, nil
		}
		if isClassPtr(et) {
			expr, owns, err := s.classCallExpr(n)
			if err != nil {
				return nil, "", false, err
			}
			lines := append([]string{}, s.pending...)
			s.pending = nil
			if owns {
				return lines, expr, true, nil
			}
			t := s.tmp()
			return append(lines, "void *"+t+" = rt_retain((void *)"+expr+");"), t, true, nil
		}
		return nil, "", false, fmt.Errorf("codegen：协议值调用返回类型 %s 未支持", et)
	}
	return nil, "", false, fmt.Errorf("codegen：协议值 %T 未支持（S2 §4.4）", e)
}
