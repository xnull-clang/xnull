// s6_sync.go：XDK-05 同步原语（Mutex/Channel/Atomic*）的 codegen 发射。
//
// 运行时合同（S5-03 / E5 rt_sync.c）：
//
//	xrt_mutex_new(data, ops) / xrt_mutex_with_lock(m, body, env, ctx)
//	xrt_channel_new(cap, ops) / send(ch,v,ctx) / receive(ch,&v,ctx) / close(ch)
//	xrt_atomic_{int,bool,ref}_{new,load,store,cas}
//
// 本卡只覆盖标量元素（Int/Bool）与 Mutex<标量>；引用元素/AtomicRef 的 ops
// （retain/release）与 GC 发布点随 XDK-05 后续卡（S3-06 并发化）补齐。
package codegen

import (
	"fmt"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

// isSyncHandleC 判断 C 类型是否为同步原语句柄（ARC 资源，不参与 GC 根登记）。
func isSyncHandleC(c string) bool {
	switch c {
	case "xrt_mutex *", "xrt_channel *", "xrt_atomic_int *", "xrt_atomic_bool *", "xrt_atomic_ref *":
		return true
	}
	return false
}

// syncElemType 返回同步原语类型实参（Mutex<T>/Channel<T>/AtomicRef<T>）的 C 类型。
func (s *scope) syncElemType(n *xfront.Call, fallback string) (string, error) {
	if len(n.TypeArgs) == 1 {
		return s.g.cType(n.TypeArgs[0])
	}
	if fallback != "" {
		return fallback, nil
	}
	return "", fmt.Errorf("codegen：%s 需要类型实参（XDK-05）", callIdent(n))
}

func callIdent(n *xfront.Call) string {
	if id, ok := n.Callee.(*xfront.IdentExpr); ok {
		return id.Name
	}
	return "构造"
}

// syncBox 把标量/引用装箱为 void*（与 xrt 同步原语的 data/value 约定）。
func syncBox(c, v string) string {
	switch c {
	case "int64_t", "int32_t", "int", "xn_char", "uint8_t", "uint16_t", "uint32_t", "uint64_t":
		return "((void *)(intptr_t)(" + v + "))"
	}
	return "((void *)(" + v + "))"
}

// syncUnbox 从 void* 还原。
func syncUnbox(c, v string) string {
	switch c {
	case "int64_t":
		return "((int64_t)(intptr_t)" + v + ")"
	case "int32_t":
		return "((int32_t)(intptr_t)" + v + ")"
	case "int":
		return "((int)(intptr_t)" + v + ")"
	}
	return "((" + c + ")" + v + ")"
}

// syncValueExpr 生成同步原语句柄值（构造或已绑定变量）。
func (s *scope) syncValueExpr(e xfront.Expr, wantC string) ([]string, string, error) {
	switch n := e.(type) {
	case *xfront.IdentExpr:
		return nil, s.cRef(n.Name), nil
	case *xfront.NullLit:
		return nil, "NULL", nil
	case *xfront.Paren:
		return s.syncValueExpr(n.X, wantC)
	case *xfront.Call:
		id, ok := n.Callee.(*xfront.IdentExpr)
		if !ok {
			return nil, "", fmt.Errorf("codegen：同步原语构造 %T 未支持（XDK-05）", n.Callee)
		}
		switch id.Name {
		case "Mutex", "Channel", "AtomicRef":
			elem, err := s.syncElemType(n, "")
			if err != nil {
				return nil, "", err
			}
			if len(n.Args) != 1 {
				return nil, "", fmt.Errorf("codegen：%s 构造需要 1 个实参（XDK-05）", id.Name)
			}
			v, err := s.intExpr(n.Args[0])
			if err != nil {
				return nil, "", err
			}
			lines := append([]string{}, s.pending...)
			s.pending = nil
			switch id.Name {
			case "Mutex":
				return lines, "xrt_mutex_new(" + syncBox(elem, v) + ", NULL)", nil
			case "Channel":
				return lines, "xrt_channel_new((size_t)(" + v + "), NULL)", nil
			default:
				return lines, "xrt_atomic_ref_new(" + syncBox(elem, v) + ", NULL)", nil
			}
		case "AtomicInt":
			v, err := s.intExpr(n.Args[0])
			if err != nil {
				return nil, "", err
			}
			lines := append([]string{}, s.pending...)
			s.pending = nil
			return lines, "xrt_atomic_int_new((int64_t)(" + v + "))", nil
		case "AtomicBool":
			v, err := s.intExpr(n.Args[0])
			if err != nil {
				return nil, "", err
			}
			lines := append([]string{}, s.pending...)
			s.pending = nil
			return lines, "xrt_atomic_bool_new((int)(" + v + "))", nil
		}
	}
	return nil, "", fmt.Errorf("codegen：同步原语表达式 %T 未支持（XDK-05）", e)
}

// emitSyncResult 生成返回 Result 的同步调用（Channel.send/receive、Mutex.withLock）。
func (s *scope) emitSyncResult(recvName, recvC, name, resultC string, args []xfront.Expr) (string, error) {
	info, err := s.g.resultInfo(resultC)
	if err != nil {
		return "", err
	}
	lines := append([]string{}, s.pending...)
	s.pending = nil
	rc := s.tmp()
	dst := s.tmp()
	zeroV := s.g.resultZeroC(info.memberC)
	switch {
	case recvC == "xrt_channel *" && name == "send":
		elem, ok := s.g.syncElems[recvName]
		if !ok || len(args) != 1 {
			return "", fmt.Errorf("codegen：Channel.send 需要元素类型与 1 个实参（XDK-05）")
		}
		v, err := s.intExpr(args[0])
		if err != nil {
			return "", err
		}
		lines = append(lines, "int32_t "+rc+" = xrt_channel_send("+recvName+", "+syncBox(elem, v)+", NULL);")
		lines = append(lines, resultC+" "+dst+";")
		lines = append(lines, "if ("+rc+" != 0) { "+dst+".ok = 0; "+dst+".v = "+zeroV+"; "+dst+".err = (xrt_error_kind)"+rc+"; }")
		lines = append(lines, "else { "+dst+".ok = 1; "+dst+".v = "+zeroV+"; "+dst+".err = 0; }")
	case recvC == "xrt_channel *" && name == "receive":
		elem, ok := s.g.syncElems[recvName]
		if !ok {
			return "", fmt.Errorf("codegen：Channel.receive 缺少元素类型（XDK-05）")
		}
		v := s.tmp()
		lines = append(lines, "void *"+v+" = NULL;")
		lines = append(lines, "int32_t "+rc+" = xrt_channel_receive("+recvName+", &"+v+", NULL);")
		lines = append(lines, resultC+" "+dst+";")
		lines = append(lines, "if ("+rc+" != 0) { "+dst+".ok = 0; "+dst+".v = "+zeroV+"; "+dst+".err = (xrt_error_kind)"+rc+"; }")
		lines = append(lines, "else { "+dst+".ok = 1; "+dst+".v = "+syncUnbox(elem, v)+"; "+dst+".err = 0; }")
	case recvC == "xrt_mutex *" && name == "withLock":
		if len(args) != 1 {
			return "", fmt.Errorf("codegen：Mutex.withLock 需要 1 个闭包（XDK-05）")
		}
		lam, ok := args[0].(*xfront.Lambda)
		if !ok {
			return "", fmt.Errorf("codegen：Mutex.withLock 实参必须是闭包（XDK-05）")
		}
		bodyName, err := s.emitLockBody(recvName, lam)
		if err != nil {
			return "", err
		}
		lines = append(lines, "int32_t "+rc+" = xrt_mutex_with_lock("+recvName+", "+bodyName+", NULL, NULL);")
		lines = append(lines, resultC+" "+dst+";")
		lines = append(lines, "if ("+rc+" != 0) { "+dst+".ok = 0; "+dst+".v = "+zeroV+"; "+dst+".err = (xrt_error_kind)"+rc+"; }")
		lines = append(lines, "else { "+dst+".ok = 1; "+dst+".v = "+zeroV+"; "+dst+".err = 0; }")
	default:
		return "", fmt.Errorf("codegen：同步 Result 成员 %s 未支持（XDK-05）", name)
	}
	s.pending = append(s.pending, lines...)
	return dst, nil
}

// emitLockBody 生成 Mutex.withLock 的作用域回调体。
func (s *scope) emitLockBody(recvName string, lam *xfront.Lambda) (string, error) {
	if len(lam.Params) != 1 {
		return "", fmt.Errorf("codegen：withLock 闭包需要 1 个参数（XDK-05）")
	}
	used := map[string]bool{}
	walkBlockAll(lam.Block, used)
	declared := map[string]bool{}
	collectLambdaDecls(lam.Block, declared)
	for name := range used {
		if declared[name] {
			continue
		}
		if _, ok := s.localCType(name); ok {
			return "", fmt.Errorf("codegen：withLock 闭包捕获外部变量 %s 暂不支持（XDK-05）", name)
		}
	}
	if _, ok := s.g.syncElems[recvName]; !ok {
		return "", fmt.Errorf("codegen：Mutex.withLock 缺少元素类型（XDK-05）")
	}
	pc, err := s.g.cType(lam.Params[0].Type)
	if err != nil {
		return "", err
	}
	name := fmt.Sprintf("xn_lock_body_%d", s.g.nextTaskID())
	sc := &scope{g: s.g, retC: "int32_t", params: map[string]bool{}, locals: map[string]string{}}
	sc.locals[lam.Params[0].Name] = pc
	sc.lockBody = &taskBodyInfo{bodyName: name, resultC: "", memberC: "", errC: ""}
	body, err := sc.emitBlock(lam.Block.Stmts)
	if err != nil {
		return "", err
	}
	var b strings.Builder
	fmt.Fprintf(&b, "static int32_t %s(void *data, void *env, xrt_context *ctx) {\n", name)
	b.WriteString("    (void)env; (void)ctx;\n")
	fmt.Fprintf(&b, "    %s %s = (%s)(intptr_t)data;\n", pc, lam.Params[0].Name, pc)
	b.WriteString(body)
	b.WriteString("\n    return 0;\n}\n\n")
	s.g.lateProtos = append(s.g.lateProtos, fmt.Sprintf("static int32_t %s(void *data, void *env, xrt_context *ctx);", name))
	s.g.lateFns = append(s.g.lateFns, b.String())
	return name, nil
}

// emitSyncAtomicValue 生成 Atomic*.load / compareExchange 的标量值。
func (s *scope) emitSyncAtomicValue(recvName, recvC, name string, args []xfront.Expr) (string, bool, error) {
	switch recvC {
	case "xrt_atomic_int *", "xrt_atomic_bool *":
		base := "xrt_atomic_int"
		if recvC == "xrt_atomic_bool *" {
			base = "xrt_atomic_bool"
		}
		switch name {
		case "load":
			return "((int64_t)" + base + "_load(" + recvName + "))", true, nil
		case "compareExchange":
			if len(args) != 2 {
				return "", true, fmt.Errorf("codegen：compareExchange 需要 2 个实参（XDK-05）")
			}
			e, err := s.intExpr(args[0])
			if err != nil {
				return "", true, err
			}
			d, err := s.intExpr(args[1])
			if err != nil {
				return "", true, err
			}
			return "((int64_t)" + base + "_cas(" + recvName + ", (int64_t)(" + e + "), (int64_t)(" + d + ")))", true, nil
		}
	case "xrt_atomic_ref *":
		elem, _ := s.g.syncElems[recvName]
		switch name {
		case "load":
			return syncUnbox(elem, "xrt_atomic_ref_load("+recvName+")"), true, nil
		case "compareExchange":
			e, err := s.intExpr(args[0])
			if err != nil {
				return "", true, err
			}
			d, err := s.intExpr(args[1])
			if err != nil {
				return "", true, err
			}
			return "((int64_t)xrt_atomic_ref_cas(" + recvName + ", " + syncBox(elem, e) + ", " + syncBox(elem, d) + "))", true, nil
		}
	}
	return "", false, nil
}

// emitSyncSpecialStmt 生成同步原语的语句形态（store/close）。
func (s *scope) emitSyncSpecialStmt(recvName, recvC, name string, args []xfront.Expr) ([]string, bool, error) {
	switch recvC {
	case "xrt_atomic_int *", "xrt_atomic_bool *":
		if name == "store" && len(args) == 1 {
			v, err := s.intExpr(args[0])
			if err != nil {
				return nil, true, err
			}
			base := "xrt_atomic_int"
			if recvC == "xrt_atomic_bool *" {
				base = "xrt_atomic_bool"
			}
			return []string{base + "_store(" + recvName + ", (int64_t)(" + v + "));"}, true, nil
		}
	case "xrt_atomic_ref *":
		elem, _ := s.g.syncElems[recvName]
		if name == "store" && len(args) == 1 {
			v, err := s.intExpr(args[0])
			if err != nil {
				return nil, true, err
			}
			return []string{"xrt_atomic_ref_store(" + recvName + ", " + syncBox(elem, v) + ");"}, true, nil
		}
	case "xrt_channel *":
		if name == "close" {
			return []string{"xrt_channel_close(" + recvName + ");"}, true, nil
		}
	}
	return nil, false, nil
}
