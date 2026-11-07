// s504.go：跨任务内存的 codegen 侧（S5-04）。
//
// 运行时合同（S5-00 / S5-01，rt_task.c）：
//   - spawn 在运行时侧 xrt_task_root_bind(env)，任务终结 unbind；
//   - 任务闭包 ABI：int32_t body(void *env, xrt_context *ctx, xrt_task_result *out)；
//   - 结果值/错误由 body 以 +1/拥有语义交出，join 移交调用方。
//
// codegen 职责：
//  1. 任务 env 为 GC 对象（xn_task_env），scan 遍历捕获的引用（GC 可达）；
//     ARC 捕获在装箱时 retain，env 清扫时由 scan 释放；
//  2. 挂起点/发布点调用 xrt_safepoint()（spawn/join/close、任务体入口/出口）；
//  3. 任务结果中的 GC 引用以 xrt_task_root_bind/unbind 跨任务持有（S5-00 §7.3）；
//  4. xrt_task_result ↔ XNull Result<T, TaskError> 映射（TaskError = xrt_error_kind）。
package codegen

import (
	"fmt"
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

// taskBodyInfo 描述任务闭包体（供 emitReturn 转换 Result → xrt_task_result）。
type taskBodyInfo struct {
	bodyName string
	resultC  string
	memberC  string
	errC     string
}

// isTaskHandleC 判断 C 类型是否为任务/上下文句柄（ARC，不参与 GC 根登记）。
func isTaskHandleC(c string) bool {
	switch c {
	case "xrt_context *", "xrt_cancel_token *", "xrt_task_group *", "xrt_task *":
		return true
	}
	return false
}

// needTaskEnv 确保生成任务 env 支撑类型，返回 env 类型名。
func (g *gen) needTaskEnv() string {
	if !g.taskSupportAdded {
		g.taskSupportAdded = true
		g.taskSupport = append(g.taskSupport, `/* S5-04：任务 env（GC 对象；scan 遍历捕获引用） */
typedef struct {
    rt_header hdr;
    size_t    nrefs;
    size_t    nvals;
    /* 紧随其后：void *refs[nrefs]; int64_t vals[nvals]; */
} xn_task_env;
static void *xn_task_env_refs(xn_task_env *e) { return (void *)(e + 1); }
static int64_t *xn_task_env_vals(xn_task_env *e) { return (int64_t *)((void **)(e + 1) + e->nrefs); }
static void xn_task_env_scan(void *p, void (*visit)(void *)) {
    xn_task_env *e = (xn_task_env *)p;
    void **refs = (void **)xn_task_env_refs(e);
    for (size_t i = 0; i < e->nrefs; i++) { if (refs[i] != NULL) { visit(refs[i]); } }
}
static const rt_type RT_TYPE_XN_TASK_ENV = { "TaskEnv", sizeof(xn_task_env), NULL, xn_task_env_scan };
static xn_task_env *xn_task_env_new(size_t nrefs, size_t nvals) {
    xn_task_env *e = (xn_task_env *)rt_gc_new_size(&RT_TYPE_XN_TASK_ENV,
        sizeof(xn_task_env) + nrefs * sizeof(void *) + nvals * sizeof(int64_t));
    e->nrefs = nrefs;
    e->nvals = nvals;
    return e;
}
`)
	}
	return "xn_task_env"
}

// taskRefCapture 判断捕获值是否需要作为引用槽（GC/ARC 引用）。
func (g *gen) taskRefCapture(c string) bool {
	if c == "" {
		return false
	}
	if g.isGCRootC(c) || isClassPtr(c) || isHandlePtr(c) || c == "xrt_bytes_obj *" ||
		c == "xrt_text *" || c == "xrt_sb *" || c == "rt_string *" {
		return true
	}
	return false
}

// collectLambdaDecls 收集闭包体内声明的名字（用于区分捕获与局部）。
func collectLambdaDecls(b *xfront.Block, out map[string]bool) {
	if b == nil {
		return
	}
	var walkStmt func(st xfront.Stmt)
	walkBlock := func(bb *xfront.Block) {
		if bb == nil {
			return
		}
		for _, st := range bb.Stmts {
			walkStmt(st)
		}
	}
	walkStmt = func(st xfront.Stmt) {
		switch n := st.(type) {
		case *xfront.LocalDeclStmt:
			out[n.Name] = true
		case *xfront.IfStmt:
			walkBlock(n.Then)
			if n.Else != nil {
				walkStmt(n.Else)
			}
		case *xfront.WhileStmt:
			walkBlock(n.Body)
		case *xfront.ForStmt:
			out[n.Var] = true
			walkBlock(n.Body)
		case *xfront.SwitchStmt:
			for _, c := range n.Cases {
				for _, s := range c.Stmts {
					walkStmt(s)
				}
			}
			if n.Default != nil {
				for _, s := range n.Default.Stmts {
					walkStmt(s)
				}
			}
		case *xfront.DeferStmt:
			if n.Block != nil {
				walkBlock(n.Block)
			} else if n.Stmt != nil {
				walkStmt(n.Stmt)
			}
		case *xfront.LabeledStmt:
			walkStmt(n.Stmt)
		}
	}
	for _, st := range b.Stmts {
		walkStmt(st)
	}
}

// lambdaResultC 从闭包体的 return 表达式推断 Result<T,TaskError> C 类型。
func (s *scope) lambdaResultC(lam *xfront.Lambda) (string, error) {
	var found string
	var walk func(stmts []xfront.Stmt) error
	walk = func(stmts []xfront.Stmt) error {
		for _, st := range stmts {
			switch n := st.(type) {
			case *xfront.ReturnStmt:
				if n.Value == nil {
					continue
				}
				t, err := s.exprType(n.Value)
				if err != nil {
					return err
				}
				if !strings.HasPrefix(t, "xn_Result_") {
					return fmt.Errorf("codegen：任务闭包必须返回 Result（得到 %s，S5-00 §二）", t)
				}
				found = t
			case *xfront.IfStmt:
				if err := walk(n.Then.Stmts); err != nil {
					return err
				}
				if eb, ok := n.Else.(*xfront.Block); ok {
					if err := walk(eb.Stmts); err != nil {
						return err
					}
				}
			case *xfront.WhileStmt:
				if err := walk(n.Body.Stmts); err != nil {
					return err
				}
			case *xfront.SwitchStmt:
				for _, c := range n.Cases {
					if err := walk(c.Stmts); err != nil {
						return err
					}
				}
				if n.Default != nil {
					if err := walk(n.Default.Stmts); err != nil {
						return err
					}
				}
			}
		}
		return nil
	}
	if err := walk(lam.Block.Stmts); err != nil {
		return "", err
	}
	if found == "" {
		return "", fmt.Errorf("codegen：任务闭包缺少 Result 返回（S5-00 §二）")
	}
	return found, nil
}

// emitTaskBody 生成任务闭包体函数（env 解包 + Result → xrt_task_result）。
func (s *scope) emitTaskBody(lam *xfront.Lambda, resultC string) (string, error) {
	if len(lam.Params) > 0 {
		return "", fmt.Errorf("codegen：任务闭包暂不支持参数（S5-04）")
	}
	info, err := s.g.resultInfo(resultC)
	if err != nil {
		return "", err
	}
	// 捕获集合：体内出现、且在外层作用域已登记、且非闭包内声明。
	used := map[string]bool{}
	walkBlockAll(lam.Block, used)
	declared := map[string]bool{}
	collectLambdaDecls(lam.Block, declared)
	var captures []string
	for name := range used {
		if declared[name] {
			continue
		}
		if _, ok := s.localCType(name); ok {
			captures = append(captures, name)
		}
	}
	// 保持稳定顺序（按名字排序，确定性）。
	sortStrings(captures)

	bodyName := fmt.Sprintf("xn_task_body_%d", s.g.nextTaskID())
	envT := s.g.needTaskEnv()

	sc := &scope{g: s.g, retC: "int32_t", params: map[string]bool{}, locals: map[string]string{}}
	sc.rootMark = s.g.nextTmp()
	sc.taskBody = &taskBodyInfo{bodyName: bodyName, resultC: resultC, memberC: info.memberC, errC: info.errC}
	sc.taskEnvVar = "e"
	sc.taskOutVar = "out"
	// 捕获局部声明（引用槽/值槽）。
	nrefs, nvals := 0, 0
	var captureDecl []string
	for _, name := range captures {
		ct, _ := s.localCType(name)
		sc.locals[name] = ct
		if s.g.taskRefCapture(ct) {
			captureDecl = append(captureDecl, fmt.Sprintf("%s %s = (%s)((void **)xn_task_env_refs(%s))[%d];", ct, name, ct, sc.taskEnvVar, nrefs))
			nrefs++
		} else if ct == "int64_t" || ct == "int32_t" || ct == "int" || ct == "xrt_error_kind" {
			captureDecl = append(captureDecl, fmt.Sprintf("%s %s = (%s)xn_task_env_vals(%s)[%d];", ct, name, ct, sc.taskEnvVar, nvals))
			nvals++
		} else if strings.HasPrefix(ct, "xn_Result_") {
			ri, err := s.g.resultInfo(ct)
			if err != nil {
				return "", err
			}
			if !isScalarCaptureC(ri.memberC) || !isScalarCaptureC(ri.errC) {
				return "", fmt.Errorf("codegen：任务闭包捕获 Result 含引用/结构字段暂不支持（S5-04）：%s", ct)
			}
			captureDecl = append(captureDecl, fmt.Sprintf("%s %s = (%s){ (int)xn_task_env_vals(%s)[%d], (%s)xn_task_env_vals(%s)[%d], (%s)xn_task_env_vals(%s)[%d] };",
				ct, name, ct, sc.taskEnvVar, nvals, ri.memberC, sc.taskEnvVar, nvals+1, ri.errC, sc.taskEnvVar, nvals+2))
			nvals += 3
		} else {
			return "", fmt.Errorf("codegen：任务闭包捕获类型 %s 暂不支持（S5-04：标量/引用）", ct)
		}
	}
	// 生成体。
	body, err := sc.emitBlock(lam.Block.Stmts)
	if err != nil {
		return "", err
	}
	var b strings.Builder
	fmt.Fprintf(&b, "static int32_t %s(void *env, xrt_context *ctx, xrt_task_result *out) {\n", bodyName)
	b.WriteString("    (void)ctx;\n")
	b.WriteString("    xrt_safepoint(); /* 任务体入口：挂起点安全点（S5-00 §7.2） */\n")
	if nrefs+nvals > 0 {
		fmt.Fprintf(&b, "    %s *e = (%s *)env;\n", envT, envT)
		for _, l := range captureDecl {
			b.WriteString("    " + l + "\n")
		}
	}
	b.WriteString(body)
	b.WriteString("\n")
	// 自然落到末尾（无显式 return）：内部错误，不静默当 Ok。
	b.WriteString("    xn_root_restore(" + sc.rootMark + ");\n")
	b.WriteString("    out->ok = 0; out->kind = XRT_ERR_INTERNAL; out->value = NULL; out->error = NULL;\n")
	b.WriteString("    xrt_safepoint();\n")
	b.WriteString("    return 0;\n}\n\n")
	return b.String(), nil
}

// emitTaskSpawn 生成 g.spawn(lambda)：env GC 装箱 + 任务体 + 发布点安全点。
func (s *scope) emitTaskSpawn(recvName, recvC string, lam *xfront.Lambda, taskC string) ([]string, string, error) {
	if recvC != "xrt_task_group *" {
		return nil, "", fmt.Errorf("codegen：spawn 接收者必须是 TaskGroup（S5-04）")
	}
	resultC, err := s.lambdaResultC(lam)
	if err != nil {
		return nil, "", err
	}
	bodyText, err := s.emitTaskBody(lam, resultC)
	if err != nil {
		return nil, "", err
	}
	// 捕获清单（与 emitTaskBody 同规则）。
	used := map[string]bool{}
	walkBlockAll(lam.Block, used)
	declared := map[string]bool{}
	collectLambdaDecls(lam.Block, declared)
	var captures []string
	for name := range used {
		if declared[name] {
			continue
		}
		if _, ok := s.localCType(name); ok {
			captures = append(captures, name)
		}
	}
	sortStrings(captures)
	nrefs, nvals := 0, 0
	for _, name := range captures {
		ct, _ := s.localCType(name)
		if s.g.taskRefCapture(ct) {
			nrefs++
		} else if strings.HasPrefix(ct, "xn_Result_") {
			nvals += 3
		} else {
			nvals++
		}
	}
	s.g.lateProtos = append(s.g.lateProtos, fmt.Sprintf("static int32_t %s(void *env, xrt_context *ctx, xrt_task_result *out);", taskBodyName(bodyText)))
	s.g.lateFns = append(s.g.lateFns, bodyText)

	envT := s.g.needTaskEnv()
	env := s.tmp()
	task := s.tmp()
	rc := s.tmp()
	lines := []string{}
	if len(s.pending) > 0 {
		lines = append(lines, s.pending...)
		s.pending = nil
	}
	lines = append(lines, fmt.Sprintf("%s *%s = xn_task_env_new(%d, %d);", envT, env, nrefs, nvals))
	ri, vi := 0, 0
	for _, name := range captures {
		ct, _ := s.localCType(name)
		ref := s.cRef(name)
		if s.g.taskRefCapture(ct) {
			// ARC 捕获 retain（env 清扫时 scan 释放）；GC 引用不计数。
			if !s.g.isGCRootC(ct) {
				lines = append(lines, fmt.Sprintf("rt_retain((void *)%s);", ref))
			}
			lines = append(lines, fmt.Sprintf("((void **)xn_task_env_refs(%s))[%d] = (void *)%s;", env, ri, ref))
			ri++
		} else if strings.HasPrefix(ct, "xn_Result_") {
			ri, err := s.g.resultInfo(ct)
			if err != nil {
				return nil, "", err
			}
			lines = append(lines, fmt.Sprintf("xn_task_env_vals(%s)[%d] = (int64_t)(%s.ok);", env, vi, ref))
			lines = append(lines, fmt.Sprintf("xn_task_env_vals(%s)[%d] = (int64_t)(%s.v);", env, vi+1, ref))
			lines = append(lines, fmt.Sprintf("xn_task_env_vals(%s)[%d] = (int64_t)(%s.err);", env, vi+2, ref))
			_ = ri
			vi += 3
		} else {
			lines = append(lines, fmt.Sprintf("xn_task_env_vals(%s)[%d] = (int64_t)(%s);", env, vi, ref))
			vi++
		}
	}
	lines = append(lines, fmt.Sprintf("xrt_task *%s = NULL;", task))
	lines = append(lines, fmt.Sprintf("int32_t %s = xrt_task_group_spawn(%s, %s, %s, &%s);", rc, recvName, taskBodyName(bodyText), env, task))
	lines = append(lines, fmt.Sprintf("if (%s != 0) { xrt_fatal(\"task_group_spawn 失败（S5-00 §三）\"); }", rc))
	lines = append(lines, "xrt_safepoint(); /* 任务 env 发布点（S5-00 §7.6） */")
	return lines, task, nil
}

// taskBodyName 从生成体文本提取函数名（第一行 "static int32_t <name>("）。
func taskBodyName(text string) string {
	const pre = "static int32_t "
	i := strings.Index(text, pre)
	if i < 0 {
		return ""
	}
	rest := text[i+len(pre):]
	if j := strings.IndexByte(rest, '('); j >= 0 {
		return rest[:j]
	}
	return ""
}

// emitTaskResult 生成 t.join()/g.close() → Result<T,TaskError> 映射。
func (s *scope) emitTaskResult(recvName, recvC, name, resultC string, args []xfront.Expr) (string, error) {
	info, err := s.g.resultInfo(resultC)
	if err != nil {
		return "", err
	}
	tr := s.tmp()
	rc := s.tmp()
	dst := s.tmp()
	lines := append([]string{}, s.pending...)
	s.pending = nil
	switch {
	case recvC == "xrt_task *" && name == "join":
		lines = append(lines, "xrt_task_result "+tr+";")
		lines = append(lines, "int32_t "+rc+" = xrt_task_join("+recvName+", &"+tr+");")
	case recvC == "xrt_task *" && name == "joinDeadline":
		if len(args) != 1 {
			return "", fmt.Errorf("codegen：joinDeadline 需要 1 个参数（S5-02）")
		}
		d, err := s.intExpr(args[0])
		if err != nil {
			return "", err
		}
		_ = d
		lines = append(lines, "xrt_task_result "+tr+";")
		lines = append(lines, "int32_t "+rc+" = xrt_task_join_deadline("+recvName+", (int64_t)("+d+"), &"+tr+");")
	case recvC == "xrt_task_group *" && name == "close":
		lines = append(lines, "xrt_task_result "+tr+";")
		lines = append(lines, "int32_t "+rc+" = xrt_task_group_close("+recvName+", &"+tr+");")
	default:
		return "", fmt.Errorf("codegen：任务结果成员 %s 未支持（S5-04）", name)
	}
	zero := s.g.resultZeroC(info.memberC)
	lines = append(lines, resultC+" "+dst+";")
	lines = append(lines, "if ("+rc+" != 0) {")
	lines = append(lines, "    "+dst+".ok = 0; "+dst+".v = "+zero+"; "+dst+".err = (xrt_error_kind)"+rc+";")
	lines = append(lines, "} else if (!"+tr+".ok) {")
	lines = append(lines, "    "+dst+".ok = 0; "+dst+".v = "+zero+"; "+dst+".err = "+tr+".kind;")
	lines = append(lines, "} else {")
	lines = append(lines, "    "+dst+".ok = 1; "+dst+".v = "+taskUnbox(info.memberC, tr+".value")+"; "+dst+".err = 0;")
	if s.g.isGCRootC(info.memberC) {
		// 任务结果中的 GC 引用以任务根持有；join 后由调用方 Result 槽接管。
		lines = append(lines, "    xrt_task_root_unbind("+tr+".value);")
		lines = append(lines, "    xn_root_add("+dst+".v);")
	}
	lines = append(lines, "}")
	lines = append(lines, "xrt_safepoint(); /* join/close 结果发布点（S5-00 §7.6） */")
	s.pending = append(s.pending, lines...)
	return dst, nil
}

// isScalarCaptureC 判断捕获/任务结果值是否为标量（可放入 int64 槽）。
func isScalarCaptureC(c string) bool {
	switch c {
	case "int64_t", "int32_t", "int", "xrt_error_kind":
		return true
	}
	return false
}

// taskBox 把 XNull 值装入 xrt_task_result.value（标量按 intptr，引用直传）。
func taskBox(memberC, v string) string {
	switch memberC {
	case "int64_t", "int32_t", "int":
		return "((void *)(intptr_t)(" + v + "))"
	}
	return "((void *)(" + v + "))"
}

// taskUnbox 把 xrt_task_result.value 还原为 XNull 值。
func taskUnbox(memberC, v string) string {
	switch memberC {
	case "int64_t":
		return "((int64_t)(intptr_t)" + v + ")"
	case "int32_t":
		return "((int32_t)(intptr_t)" + v + ")"
	case "int":
		return "((int)(intptr_t)" + v + ")"
	}
	return "((" + memberC + ")" + v + ")"
}

// taskValueExpr 生成任务/上下文句柄值表达式（含 spawn 闭包装箱）。
func (s *scope) taskValueExpr(e xfront.Expr, wantC string) ([]string, string, error) {
	switch n := e.(type) {
	case *xfront.IdentExpr:
		return nil, s.cRef(n.Name), nil
	case *xfront.NullLit:
		return nil, "NULL", nil
	case *xfront.Paren:
		return s.taskValueExpr(n.X, wantC)
	case *xfront.Call:
		mem, ok := n.Callee.(*xfront.Member)
		if !ok {
			return nil, "", fmt.Errorf("codegen：任务/上下文调用 %T 未支持（S5-04）", n.Callee)
		}
		if recv, ok := mem.X.(*xfront.IdentExpr); ok {
			switch {
			case recv.Name == "Context" && mem.Name == "background":
				return nil, "xrt_context_background()", nil
			case recv.Name == "TaskGroup" && mem.Name == "create":
				if len(n.Args) != 1 {
					return nil, "", fmt.Errorf("codegen：TaskGroup.create 需要 1 个 Context（S5-00 §三）")
				}
				arg, err := s.intExpr(n.Args[0])
				if err != nil {
					return nil, "", err
				}
				lines := append([]string{}, s.pending...)
				s.pending = nil
				return lines, "xrt_task_group_new(" + arg + ")", nil
			}
		}
		rn, rc, err := recvCName(mem.X, s)
		if err != nil {
			return nil, "", err
		}
		switch {
		case rc == "xrt_context *":
			switch mem.Name {
			case "token":
				return nil, "xrt_context_token(" + rn + ")", nil
			case "withDeadline":
				if len(n.Args) != 1 {
					return nil, "", fmt.Errorf("codegen：Context.withDeadline 需要 1 个 deadline（S5-00 §四）")
				}
				d, err := s.intExpr(n.Args[0])
				if err != nil {
					return nil, "", err
				}
				lines := append([]string{}, s.pending...)
				s.pending = nil
				return lines, "xrt_context_with_deadline(" + rn + ", (int64_t)(" + d + "))", nil
			}
		case rc == "xrt_task_group *" && mem.Name == "spawn":
			if len(n.Args) != 1 {
				return nil, "", fmt.Errorf("codegen：TaskGroup.spawn 需要 1 个闭包（S5-00 §三）")
			}
			lam, ok := n.Args[0].(*xfront.Lambda)
			if !ok {
				return nil, "", fmt.Errorf("codegen：spawn 实参必须是闭包（S5-04）")
			}
			lines, task, err := s.emitTaskSpawn(rn, rc, lam, wantC)
			if err != nil {
				return nil, "", err
			}
			return lines, task, nil
		}
	}
	return nil, "", fmt.Errorf("codegen：任务/上下文表达式 %T 未支持（S5-04）", e)
}
