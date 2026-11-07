package codegen

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"xnull.dev/xnull/internal/codegen/ffi"
	"xnull.dev/xnull/internal/xfront"
)

// S6-02/XDK-02：XDK 合同静态核验（走 `go test ./...`，不引入独立脚本体系）。
//
// 覆盖：
//   - 依赖矩阵：impl/docs/xdk-packages.tsv 是 SSOT；实际 xdk.* import 必须在允许集内，
//     且包间依赖无环（S6 §2/§1.4.3）。
//   - 稳定性/命名：8 包表与源码单元一一对应；包名/类型/函数/方法/字段/枚举项命名；
//     稳定性表与源码头标注一致（S6 §3 第 4/6 条）。
//   - 资源合同：bindings 中每个 handle 必须有存在的 close 入口；XDK 类持有句柄字段时
//     必须声明 close()（S6 §3 第 2 条）。
//   - 无隐式合同：XDK 顶层无未 final/const 字段、singleton 无未 final/const 字段、
//     无隐式初始化/清理/线程局部注解（S6 §3 第 5 条）。
//
// 设计边界：只读取源码/绑定/表格，不执行语义分析，不依赖 codegen 发射。

const (
	xdkCodeTable     = "XDK-001" // 包表缺失/格式错误
	xdkCodePackages  = "XDK-002" // 包集合不一致
	xdkCodeDeps      = "XDK-003" // 依赖违约/非 xdk 导入
	xdkCodeCycle     = "XDK-004" // 包依赖环
	xdkCodeNaming    = "XDK-005" // 命名违约
	xdkCodeStability = "XDK-006" // 稳定性表/源码不一致
	xdkCodeImplicit  = "XDK-007" // 隐藏全局可变/隐式钩子
	xdkCodeResource  = "XDK-008" // 句柄/close 合同违约
	xdkCodeDocs      = "XDK-009" // 架构文档与包表不一致
)

// XDKContractViolation 是一条静态合同违约。
type XDKContractViolation struct {
	File    string
	Line    int
	Col     int
	Code    string
	Message string
}

func (v XDKContractViolation) String() string {
	return fmt.Sprintf("%s:%d:%d: %s %s", v.File, v.Line, v.Col, v.Code, v.Message)
}

type xdkPackageRow struct {
	Name      string
	Stability string
	Deps      []string
	Runtime   string
	FFI       string
	Line      int
}

var xdkCanonicalPackages = []string{
	"errors", "tasks", "sync", "runtime", "collections", "text", "sys", "net",
}

// CheckXDKContracts 对 repoRoot 下的 XDK 包执行静态合同核验。
// 返回按文件/行/码排序的违约列表；空表示通过。
func CheckXDKContracts(repoRoot string) []XDKContractViolation {
	var out []XDKContractViolation
	add := func(rel string, line, col int, code, msg string) {
		if line <= 0 {
			line = 1
		}
		if col <= 0 {
			col = 1
		}
		out = append(out, XDKContractViolation{
			File: rel, Line: line, Col: col, Code: code, Message: msg,
		})
	}

	tablePath := filepath.Join(repoRoot, "impl", "docs", "xdk-packages.tsv")
	rows, tableDiags := loadXDKPackageTable(tablePath)
	out = append(out, tableDiags...)
	rowByName := map[string]xdkPackageRow{}
	for _, r := range rows {
		rowByName[r.Name] = r
	}

	// 包集合：表 == 规范 8 包 == 磁盘文件。
	want := map[string]bool{}
	for _, p := range xdkCanonicalPackages {
		want[p] = true
		if _, ok := rowByName[p]; !ok {
			add("impl/docs/xdk-packages.tsv", 1, 1, xdkCodePackages,
				"包表缺少 `"+p+"`（S6 §2 定案 8 包）")
		}
	}
	for name, r := range rowByName {
		if !want[name] {
			add("impl/docs/xdk-packages.tsv", r.Line, 1, xdkCodePackages,
				"包表含未定案包 `"+name+"`（S6 §2）")
		}
	}

	xdkDir := filepath.Join(repoRoot, "impl", "lib", "xdk")
	entries, err := os.ReadDir(xdkDir)
	if err != nil {
		add("impl/lib/xdk", 1, 1, xdkCodePackages, "无法读取 XDK 单元目录："+err.Error())
		return sortViolations(out)
	}
	files := map[string]bool{}
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".x") {
			continue
		}
		pkg := strings.TrimSuffix(e.Name(), ".x")
		files[pkg] = true
		if !want[pkg] {
			add("impl/lib/xdk/"+e.Name(), 1, 1, xdkCodePackages,
				"未在包表登记的 XDK 单元（S6 §2）")
		}
	}

	// 每个包的源码与依赖。
	for _, pkg := range xdkCanonicalPackages {
		rel := "impl/lib/xdk/" + pkg + ".x"
		if !files[pkg] {
			add(rel, 1, 1, xdkCodePackages, "缺少 XDK 包单元（S6 §2）")
			continue
		}
		src, err := os.ReadFile(filepath.Join(xdkDir, pkg+".x"))
		if err != nil {
			add(rel, 1, 1, xdkCodePackages, "读取失败："+err.Error())
			continue
		}
		text := string(src)
		first := xdkFirstLine(text)
		if !strings.Contains(first, "xdk."+pkg) {
			add(rel, 1, 1, xdkCodeDocs,
				"包单元首行缺少 `xdk."+pkg+"` 包名标注（S6 §3 第 7 条）")
		}

		// 稳定性：表格为 SSOT；源码头若标注必须一致。
		row := rowByName[pkg]
		if !xdkValidStability(row.Stability) {
			add("impl/docs/xdk-packages.tsv", row.Line, 1, xdkCodeStability,
				"包 `"+pkg+"` 稳定性 `"+row.Stability+"` 非法（仅 stable/preview/internal）")
		}
		if row.Runtime == "" {
			add("impl/docs/xdk-packages.tsv", row.Line, 1, xdkCodeDocs,
				"包 `"+pkg+"` 未声明依赖的运行时服务（S6 §3 第 7 条）")
		}
		if row.FFI == "" {
			add("impl/docs/xdk-packages.tsv", row.Line, 1, xdkCodeDocs,
				"包 `"+pkg+"` 未声明跨 FFI 边界（S6 §3 第 7 条）")
		}
		if marker, line := xdkStabilityMarker(text); marker != "" && marker != row.Stability {
			add(rel, line, 1, xdkCodeStability,
				"源码稳定性 @"+marker+" 与包表 `"+row.Stability+"` 不一致（S6 §3 第 6 条）")
		}

		u, pdiags := xfront.ParseUnit(filepath.Join(xdkDir, pkg+".x"), text)
		for _, d := range pdiags {
			add(rel, d.Line, d.Col, xdkCodePackages, "解析失败："+d.Message)
		}
		if u == nil {
			continue
		}

		allowed := map[string]bool{}
		for _, d := range row.Deps {
			allowed[d] = true
		}
		for _, imp := range u.Imports {
			if len(imp.Path) == 0 {
				continue
			}
			if imp.Path[0] != "xdk" {
				add(rel, imp.P.Line, imp.P.Col, xdkCodeDeps,
					"XDK 单元不得导入非 xdk 包 `"+strings.Join(imp.Path, ".")+"`（S6 §3 第 7 条）")
				continue
			}
			if len(imp.Path) < 2 {
				add(rel, imp.P.Line, imp.P.Col, xdkCodeDeps, "xdk 导入缺包名（S6 §2）")
				continue
			}
			dep := imp.Path[1]
			if dep == pkg {
				add(rel, imp.P.Line, imp.P.Col, xdkCodeCycle, "包导入自身（S6 §2）")
				continue
			}
			if !allowed[dep] {
				add(rel, imp.P.Line, imp.P.Col, xdkCodeDeps,
					"依赖 `"+pkg+"→"+dep+"` 不在包表允许集（S6 §1.4.3/§3 第 7 条）")
			}
		}

		// 命名 / 无隐式。
		for _, d := range u.Decls {
			xdkCheckDecl(d, rel, add)
		}
	}

	// 依赖环：以包表声明为图（实际导入必须是其子集）。
	graph := map[string][]string{}
	for _, pkg := range xdkCanonicalPackages {
		graph[pkg] = append([]string(nil), rowByName[pkg].Deps...)
	}
	if cycle := xdkFindCycle(graph, xdkCanonicalPackages); len(cycle) > 0 {
		add("impl/docs/xdk-packages.tsv", 1, 1, xdkCodeCycle,
			"包依赖环："+strings.Join(cycle, " → "))
	}

	// 资源合同：绑定句柄必须有 close 入口。
	xdkCheckResources(repoRoot, add)

	// 架构文档与包表一致：design 文档必须列出每个单元路径。
	designPath := filepath.Join(repoRoot, "impl", "docs", "xdk-design.md")
	if doc, err := os.ReadFile(designPath); err == nil {
		for _, pkg := range xdkCanonicalPackages {
			if !strings.Contains(string(doc), "impl/lib/xdk/"+pkg+".x") {
				add("impl/docs/xdk-design.md", 1, 1, xdkCodeDocs,
					"架构文档缺少 `impl/lib/xdk/"+pkg+".x` 条目（S6 §3 第 7 条）")
			}
		}
	}

	return sortViolations(out)
}

func sortViolations(v []XDKContractViolation) []XDKContractViolation {
	sort.Slice(v, func(i, j int) bool {
		if v[i].File != v[j].File {
			return v[i].File < v[j].File
		}
		if v[i].Line != v[j].Line {
			return v[i].Line < v[j].Line
		}
		if v[i].Col != v[j].Col {
			return v[i].Col < v[j].Col
		}
		return v[i].Code < v[j].Code
	})
	return v
}

func loadXDKPackageTable(path string) ([]xdkPackageRow, []XDKContractViolation) {
	var out []xdkPackageRow
	var diags []XDKContractViolation
	add := func(line int, msg string) {
		diags = append(diags, XDKContractViolation{
			File: "impl/docs/xdk-packages.tsv", Line: line, Col: 1,
			Code: xdkCodeTable, Message: msg,
		})
	}
	src, err := os.ReadFile(path)
	if err != nil {
		add(1, "无法读取包表："+err.Error())
		return nil, diags
	}
	for i, raw := range strings.Split(string(src), "\n") {
		line := strings.TrimSuffix(raw, "\r")
		if strings.TrimSpace(line) == "" || strings.HasPrefix(strings.TrimSpace(line), "#") {
			continue
		}
		cols := strings.Split(line, "\t")
		if len(cols) != 5 {
			add(i+1, "包表行必须是 5 列（package/stability/deps/runtime_services/ffi_boundary）")
			continue
		}
		name := strings.TrimSpace(cols[0])
		if name == "" {
			add(i+1, "包表行缺包名")
			continue
		}
		row := xdkPackageRow{
			Name:      name,
			Stability: strings.TrimSpace(cols[1]),
			Runtime:   strings.TrimSpace(cols[3]),
			FFI:       strings.TrimSpace(cols[4]),
			Line:      i + 1,
		}
		deps := strings.TrimSpace(cols[2])
		if deps != "" && deps != "-" {
			for _, d := range strings.Split(deps, ",") {
				d = strings.TrimSpace(d)
				if d != "" {
					row.Deps = append(row.Deps, d)
				}
			}
		}
		out = append(out, row)
	}
	return out, diags
}

func xdkFirstLine(text string) string {
	for _, line := range strings.Split(text, "\n") {
		if strings.TrimSpace(line) != "" {
			return line
		}
	}
	return ""
}

// xdkStabilityMarker 返回源码注释中的 @stable/@preview/@internal 标记。
func xdkStabilityMarker(text string) (string, int) {
	found := ""
	foundLine := 0
	for i, line := range strings.Split(text, "\n") {
		idx := strings.Index(line, "//")
		if idx < 0 {
			continue
		}
		comment := line[idx:]
		for _, m := range []string{"@stable", "@preview", "@internal"} {
			if !strings.Contains(comment, m) {
				continue
			}
			marker := strings.TrimPrefix(m, "@")
			if found == "" {
				found, foundLine = marker, i+1
			} else if found != marker {
				// 同一单元多个稳定性标记：按不一致处理。
				return marker, i + 1
			}
		}
	}
	return found, foundLine
}

func xdkValidStability(s string) bool {
	return s == "stable" || s == "preview" || s == "internal"
}

func xdkCheckDecl(d xfront.TopDecl, rel string, add func(string, int, int, string, string)) {
	switch n := d.(type) {
	case *xfront.TopFunc:
		if n.Name != "main" && !xdkLowerCamel(n.Name) {
			add(rel, n.P.Line, n.P.Col, xdkCodeNaming, "顶层函数 `"+n.Name+"` 不是 lowerCamel（S6 §3 第 4 条）")
		}
		xdkCheckParams(n.Params, rel, add)
		xdkCheckAnnos(n.Annos, rel, n.P.Line, n.P.Col, add)
	case *xfront.TopField:
		if !xdkLowerCamel(n.Name) {
			add(rel, n.P.Line, n.P.Col, xdkCodeNaming, "顶层字段 `"+n.Name+"` 不是 lowerCamel（S6 §3 第 4 条）")
		}
		if !n.Final && !n.Const {
			add(rel, n.P.Line, n.P.Col, xdkCodeImplicit, "XDK 顶层字段 `"+n.Name+"` 必须 final/const（S6 §3 第 5 条）")
		}
		xdkCheckAnnos(n.Annos, rel, n.P.Line, n.P.Col, add)
	case *xfront.ClassDecl:
		xdkCheckTypeName(n.Name, rel, n.P, add)
		xdkCheckAnnos(n.Annos, rel, n.P.Line, n.P.Col, add)
		if n.Primary != nil {
			xdkCheckParams(n.Primary.Params, rel, add)
		}
		xdkCheckFields(n.Fields, false, rel, add)
		xdkCheckMethods(n.Methods, rel, add)
		for _, c := range n.Ctors {
			xdkCheckParams(c.Params, rel, add)
		}
	case *xfront.StructDecl:
		xdkCheckTypeName(n.Name, rel, n.P, add)
		xdkCheckFields(n.Fields, false, rel, add)
		xdkCheckMethods(n.Methods, rel, add)
		for _, c := range n.Ctors {
			xdkCheckParams(c.Params, rel, add)
		}
	case *xfront.ProtocolDecl:
		xdkCheckTypeName(n.Name, rel, n.P, add)
		for _, s := range n.Sigs {
			if !xdkLowerCamel(s.Name) {
				add(rel, s.P.Line, s.P.Col, xdkCodeNaming, "协议方法 `"+s.Name+"` 不是 lowerCamel（S6 §3 第 4 条）")
			}
			if xdkBoolGetter(s.Name, s.Void, xdkTypeKey(s.Ret), s.Params) {
				add(rel, s.P.Line, s.P.Col, xdkCodeNaming, "布尔读方法 `"+s.Name+"` 必须以 is/has 开头（S6 §3 第 4 条）")
			}
			xdkCheckParams(s.Params, rel, add)
		}
	case *xfront.EnumDecl:
		xdkCheckTypeName(n.Name, rel, n.P, add)
		for _, it := range n.Items {
			if !xdkPascal(it.Name) {
				add(rel, it.P.Line, it.P.Col, xdkCodeNaming, "枚举项 `"+it.Name+"` 不是 PascalCase（S6 §3 第 4 条）")
			}
		}
		xdkCheckFields(n.Fields, false, rel, add)
		xdkCheckMethods(n.Methods, rel, add)
	case *xfront.SingletonDecl:
		xdkCheckTypeName(n.Name, rel, n.P, add)
		xdkCheckFields(n.Fields, true, rel, add)
		xdkCheckMethods(n.Methods, rel, add)
		for _, c := range n.Ctors {
			xdkCheckParams(c.Params, rel, add)
		}
	case *xfront.FactoryDecl:
		xdkCheckTypeName(n.Name, rel, n.P, add)
		xdkCheckMethods(n.Methods, rel, add)
	case *xfront.ExtensionDecl:
		xdkCheckMethods(n.Methods, rel, add)
	case *xfront.AnnotationDecl:
		xdkCheckTypeName(n.Name, rel, n.P, add)
		xdkCheckFields(n.Fields, false, rel, add)
	}
}

func xdkCheckTypeName(name, rel string, p xfront.Pos, add func(string, int, int, string, string)) {
	if !xdkPascal(name) {
		add(rel, p.Line, p.Col, xdkCodeNaming, "类型 `"+name+"` 不是 PascalCase（S6 §3 第 4 条）")
	}
}

func xdkCheckParams(ps []*xfront.Param, rel string, add func(string, int, int, string, string)) {
	for _, p := range ps {
		if p.Name != "" && !xdkLowerCamel(p.Name) {
			add(rel, p.P.Line, p.P.Col, xdkCodeNaming, "参数 `"+p.Name+"` 不是 lowerCamel（S6 §3 第 4 条）")
		}
	}
}

func xdkCheckFields(fs []*xfront.FieldDecl, singleton bool, rel string, add func(string, int, int, string, string)) {
	for _, f := range fs {
		if f.Mod.Vis == "private" && !strings.HasPrefix(f.Name, "_") {
			add(rel, f.P.Line, f.P.Col, xdkCodeNaming, "私有字段 `"+f.Name+"` 必须以 `_` 开头（S6 §3 第 4 条）")
		} else if !strings.HasPrefix(f.Name, "_") && !xdkLowerCamel(f.Name) {
			add(rel, f.P.Line, f.P.Col, xdkCodeNaming, "字段 `"+f.Name+"` 不是 lowerCamel（S6 §3 第 4 条）")
		}
		if singleton && !f.Mod.Final && !f.Mod.Const {
			add(rel, f.P.Line, f.P.Col, xdkCodeImplicit, "singleton 字段 `"+f.Name+"` 必须 final/const（S6 §3 第 5 条）")
		}
	}
}

func xdkCheckMethods(ms []*xfront.MethodDecl, rel string, add func(string, int, int, string, string)) {
	for _, m := range ms {
		if m.IsDeinit || m.Name == "deinit" {
			xdkCheckAnnos(m.Annos, rel, m.P.Line, m.P.Col, add)
			continue
		}
		if m.Mod.Vis == "private" && !strings.HasPrefix(m.Name, "_") {
			add(rel, m.P.Line, m.P.Col, xdkCodeNaming, "私有方法 `"+m.Name+"` 必须以 `_` 开头（S6 §3 第 4 条）")
		} else if !xdkLowerCamel(m.Name) {
			add(rel, m.P.Line, m.P.Col, xdkCodeNaming, "方法 `"+m.Name+"` 不是 lowerCamel（S6 §3 第 4 条）")
		}
		if xdkBoolGetter(m.Name, m.Void, xdkTypeKey(m.Ret), m.Params) {
			add(rel, m.P.Line, m.P.Col, xdkCodeNaming, "布尔读方法 `"+m.Name+"` 必须以 is/has 开头（S6 §3 第 4 条）")
		}
		xdkCheckParams(m.Params, rel, add)
		xdkCheckAnnos(m.Annos, rel, m.P.Line, m.P.Col, add)
	}
}

func xdkBoolGetter(name string, void bool, ret string, params []*xfront.Param) bool {
	if void || ret != "Bool" || len(params) != 0 {
		return false
	}
	return !strings.HasPrefix(name, "is") && !strings.HasPrefix(name, "has")
}

func xdkCheckAnnos(annos []*xfront.AnnotationNode, rel string, line, col int, add func(string, int, int, string, string)) {
	for _, a := range annos {
		switch a.Name {
		case "init", "cleanup", "finalize", "threadLocal", "tls", "onInit", "onExit":
			add(rel, a.P.Line, a.P.Col, xdkCodeImplicit,
				"隐式初始化/清理/线程局部注解 `@"+a.Name+"` 禁止（S6 §3 第 5 条）")
		}
	}
}

func xdkPascal(s string) bool {
	if s == "" {
		return false
	}
	for i, r := range s {
		if i == 0 {
			if r < 'A' || r > 'Z' {
				return false
			}
			continue
		}
		if !xdkIdentRune(r) {
			return false
		}
	}
	return true
}

func xdkLowerCamel(s string) bool {
	if s == "" {
		return false
	}
	for i, r := range s {
		if i == 0 {
			if r < 'a' || r > 'z' {
				return false
			}
			continue
		}
		if !xdkIdentRune(r) {
			return false
		}
	}
	return true
}

func xdkIdentRune(r rune) bool {
	return r == '_' || (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9')
}

func xdkFindCycle(graph map[string][]string, order []string) []string {
	const (
		gray  = 1
		black = 2
	)
	state := map[string]int{}
	var stack []string
	var found []string
	var visit func(string) bool
	visit = func(n string) bool {
		state[n] = gray
		stack = append(stack, n)
		for _, m := range graph[n] {
			if state[m] == 0 {
				if visit(m) {
					return true
				}
			} else if state[m] == gray {
				idx := 0
				for i, s := range stack {
					if s == m {
						idx = i
						break
					}
				}
				found = append(append([]string(nil), stack[idx:]...), m)
				return true
			}
		}
		stack = stack[:len(stack)-1]
		state[n] = black
		return false
	}
	for _, n := range order {
		if state[n] == 0 && visit(n) {
			return found
		}
	}
	return nil
}

func xdkCheckResources(repoRoot string, add func(string, int, int, string, string)) {
	root := filepath.Join(repoRoot, "bindings")
	if _, err := os.Stat(root); err != nil {
		if os.IsNotExist(err) {
			return
		}
		add("bindings", 1, 1, xdkCodeResource, "无法读取绑定目录："+err.Error())
		return
	}
	reg, diags, err := ffi.Load(root)
	if err != nil {
		add("bindings", 1, 1, xdkCodeResource, "绑定加载失败："+err.Error())
		return
	}
	for _, d := range diags {
		add(d.File, d.Line, d.Col, xdkCodeResource, "绑定合同失败："+d.Message)
	}
	if reg == nil {
		return
	}
	byName := map[string]ffi.Entry{}
	for _, e := range reg.Entries {
		byName[e.Name] = e
	}
	handleNames := map[string]bool{}
	for _, h := range reg.Handles {
		handleNames[h.Name] = true
		if h.Close == "" {
			add("bindings", 1, 1, xdkCodeResource,
				"句柄 `"+h.Name+"` 未声明 close 入口（S6 §3 第 2 条）")
			continue
		}
		e, ok := byName[h.Close]
		if !ok {
			add("bindings", 1, 1, xdkCodeResource,
				"句柄 `"+h.Name+"` 的 close 入口 `"+h.Close+"` 不存在（S6 §3 第 2 条）")
			continue
		}
		if e.CloseOf != h.Name {
			add("bindings", 1, 1, xdkCodeResource,
				"入口 `"+h.Close+"` 未登记为句柄 `"+h.Name+"` 的 close（S6 §3 第 2 条）")
		}
	}
	if len(handleNames) == 0 {
		return
	}
	// XDK 源码类若持有句柄字段，必须提供 close()。
	xdkDir := filepath.Join(repoRoot, "impl", "lib", "xdk")
	for _, pkg := range xdkCanonicalPackages {
		path := filepath.Join(xdkDir, pkg+".x")
		src, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		u, diags := xfront.ParseUnit(path, string(src))
		if len(diags) > 0 || u == nil {
			continue
		}
		for _, d := range u.Decls {
			cls, ok := d.(*xfront.ClassDecl)
			if !ok {
				continue
			}
			hasHandle := false
			for _, f := range cls.Fields {
				if handleNames[xdkBaseTypeName(xdkTypeKey(f.Type))] {
					hasHandle = true
					break
				}
			}
			if !hasHandle {
				continue
			}
			hasClose := false
			for _, m := range cls.Methods {
				if m.Name == "close" && len(m.Params) == 0 {
					hasClose = true
					break
				}
			}
			if !hasClose {
				add("impl/lib/xdk/"+pkg+".x", cls.P.Line, cls.P.Col, xdkCodeResource,
					"类 `"+cls.Name+"` 持有句柄字段但未声明 close()（S6 §3 第 2 条）")
			}
		}
	}
}

func xdkBaseTypeName(key string) string {
	for strings.HasSuffix(key, "?") {
		key = strings.TrimSuffix(key, "?")
	}
	if i := strings.Index(key, "<"); i > 0 {
		key = key[:i]
	}
	return key
}

// xdkTypeKey 渲染 TypeRef 为类型串（仅用于命名/资源检查，不参与 codegen）。
func xdkTypeKey(t xfront.TypeRef) string {
	switch n := t.(type) {
	case nil:
		return ""
	case *xfront.NamedType:
		base := strings.Join(n.Qual, ".")
		if len(n.Args) == 0 {
			return base
		}
		parts := make([]string, len(n.Args))
		for i, a := range n.Args {
			parts[i] = xdkTypeKey(a)
		}
		return base + "<" + strings.Join(parts, ",") + ">"
	case *xfront.SuffixedType:
		return xdkTypeKey(n.Base) + strings.Join(n.Suffixes, "")
	case *xfront.FuncTypeRef:
		parts := make([]string, len(n.Params))
		for i, p := range n.Params {
			parts[i] = xdkTypeKey(p)
		}
		return xdkTypeKey(n.Ret) + "(" + strings.Join(parts, ",") + ")"
	case *xfront.TupleTypeRef:
		parts := make([]string, len(n.Elems))
		for i, e := range n.Elems {
			parts[i] = xdkTypeKey(e)
		}
		return "(" + strings.Join(parts, ",") + ")"
	default:
		return ""
	}
}
