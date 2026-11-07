package sema

// PKG-01（S1 §3 包与导入）：跨文件/跨包符号表与导入诊断。
//
// 实现落点：
//   - Package 是导入解析所需的最小包符号表（只含公开顶层符号）；
//   - NewPackage 从编译单元提取符号表（public 默认；private/protected 不导出）；
//   - AnalyzeWithDeps 在给定依赖包表时执行严格导入解析；
//     Analyze（无依赖表）保持旧行为：用户包导入无法解析时延后未定义检查。
//
// 诊断码（§3.5）：
//   RES-103 导入别名冲突
//   RES-104 未消歧的简单名
//   RES-105 XDK 包未显式导入
//   RES-106 包或符号不存在
//   RES-107 非冲突场景使用 as 别名（含禁止的包别名）
//   RES-108 包导入环
//   RES-111 默认包被跨包导入（本文件新增）

import (
	"sort"
	"strings"

	"xnull.dev/xnull/internal/diag"
	"xnull.dev/xnull/internal/xfront"
)

const (
	// ResImportCycle 包导入环（§3.4）。
	ResImportCycle = "RES-108"
	// ResDefaultPkg 默认包被其他包导入（§3.1/§3.5）。
	ResDefaultPkg = "RES-111"
)

// Package 是一个被导入包的最小符号表。
type Package struct {
	Path    []string        // 导入路径（点分段）
	Name    []string        // package 声明；nil 表示默认包
	Symbols map[string]bool // 公开顶层符号
	Imports [][]string      // 该包自身的导入路径（环检测用）
}

// NewPackage 从编译单元提取包符号表。
// 只登记公开顶层符号：顶层 private/protected 等价于不可跨包导入（§3.1/§3.5）。
func NewPackage(path []string, u *xfront.CompilationUnit) *Package {
	p := &Package{Path: path, Symbols: map[string]bool{}}
	if u == nil {
		return p
	}
	if u.Package != nil {
		p.Name = u.Package.Name
	}
	for _, imp := range u.Imports {
		if len(imp.Path) > 0 {
			p.Imports = append(p.Imports, imp.Path)
		}
	}
	for _, d := range u.Decls {
		switch n := d.(type) {
		case *xfront.TopFunc:
			if importableVis(n.Private, n.Protected) {
				p.Symbols[n.Name] = true
			}
		case *xfront.TopField:
			if importableVis(n.Private, n.Protected) {
				p.Symbols[n.Name] = true
			}
		case *xfront.ClassDecl:
			if importableTypeVis(n.Mod.Vis) {
				p.Symbols[n.Name] = true
			}
		case *xfront.StructDecl:
			if importableTypeVis(n.Mod.Vis) {
				p.Symbols[n.Name] = true
			}
		case *xfront.ProtocolDecl:
			// ProtocolDecl 当前无 Mod 字段（G-P1），按默认 public 处理。
			p.Symbols[n.Name] = true
		case *xfront.EnumDecl:
			if importableTypeVis(n.Mod.Vis) {
				p.Symbols[n.Name] = true
			}
		}
	}
	return p
}

func importableVis(private, protected bool) bool { return !private && !protected }

func importableTypeVis(vis string) bool { return vis != "private" && vis != "protected" }

// AnalyzeWithDeps 在给定依赖包符号表时执行语义分析。
// deps 必须覆盖入口文件全部非 xdk 导入；缺项按"包不存在"（RES-106）诊断。
func AnalyzeWithDeps(file string, u *xfront.CompilationUnit, deps []*Package) (*Result, []diag.Diagnostic) {
	m := make(map[string]*Package, len(deps))
	for _, d := range deps {
		if d == nil || len(d.Path) == 0 {
			continue
		}
		m[strings.Join(d.Path, ".")] = d
	}
	return analyzeWith(file, u, m, nil)
}

// analyzeWith 是 AnalyzeWith/AnalyzeWithDeps 的共同实现。
func analyzeWith(file string, u *xfront.CompilationUnit, deps map[string]*Package, opts *Options) (*Result, []diag.Diagnostic) {
	a := &analyzer{file: file, tops: map[string]bool{}, seenTop: map[string]bool{},
		imported: map[string]bool{}, ambiguous: map[string]bool{}, deps: deps,
		typeParamNames: map[string]bool{}, mustUse: "error"}
	if opts != nil && opts.MustUse != "" {
		a.mustUse = opts.MustUse
	}
	a.collectTypeParamNames(u)
	a.analyzeImports(u)
	a.checkTypeDecls(u)
	for _, d := range u.Decls {
		switch n := d.(type) {
		case *xfront.TopFunc:
			a.collectTop(n.Name, n.P)
			for _, p := range n.Params {
				a.collectTopParam(p.Name)
			}
		case *xfront.TopField:
			a.collectTop(n.Name, n.P)
		}
	}
	for _, d := range u.Decls {
		if fn, ok := d.(*xfront.TopFunc); ok {
			sc := &nscope{parent: nil}
			for _, tp := range fn.TypePars { // 类型参数进入第 1 级名字空间（§8.1）
				if sc.declaredHere(tp) {
					a.errf(fn.P, ResRedecl, "类型参数 `"+tp+"` 重复声明（§8.1）", "同一泛型声明内类型参数名必须唯一")
				}
				sc.define(tp)
			}
			for _, p := range fn.Params {
				sc.define(p.Name)
			}
			a.walkBlock(fn.Body, sc)
		}
	}
	// M2-B：确定赋值与返回路径（§5.3、§6.1）——名称解析之后。
	for _, d := range u.Decls {
		if fn, ok := d.(*xfront.TopFunc); ok {
			a.analyzeAssign(file, fn)
		}
	}
	// M2-C：类型检查（§2.6/§2.10/§6.1）——最后（依赖前两遍的环境）。
	a.analyzeTypes(file, u)
	return &Result{a: a}, a.diags
}

// topLevelNames 扫描当前文件的顶层声明名（函数/字段/类型）。
// analyzeImports 早于 collectTop/类型登记，别名与遮蔽判定需要独立扫描（§3.3）。
func topLevelNames(u *xfront.CompilationUnit) map[string]bool {
	names := map[string]bool{}
	for _, d := range u.Decls {
		switch n := d.(type) {
		case *xfront.TopFunc:
			names[n.Name] = true
		case *xfront.TopField:
			names[n.Name] = true
		case *xfront.ClassDecl:
			names[n.Name] = true
		case *xfront.StructDecl:
			names[n.Name] = true
		case *xfront.ProtocolDecl:
			names[n.Name] = true
		case *xfront.EnumDecl:
			names[n.Name] = true
		}
	}
	return names
}

// resolveUserImport 把导入路径解析为依赖包：
//   - 整段命中依赖包 → 包导入，sym 为空；
//   - 去掉末段命中依赖包 → 符号导入，sym 为末段；
//   - 其余 → 未找到。
func (a *analyzer) resolveUserImport(p []string) (*Package, string, bool) {
	if len(p) == 0 {
		return nil, "", false
	}
	if d, ok := a.deps[strings.Join(p, ".")]; ok {
		return d, "", true
	}
	if len(p) >= 2 {
		if d, ok := a.deps[strings.Join(p[:len(p)-1], ".")]; ok {
			return d, p[len(p)-1], true
		}
	}
	return nil, "", false
}

// samePackage 判断依赖是否属于当前编译单元（同包分片，§3.4 起步形态）。
func samePackage(u *xfront.CompilationUnit, dep *Package) bool {
	if u.Package == nil {
		return len(dep.Name) == 0
	}
	return len(dep.Name) > 0 && strings.Join(u.Package.Name, ".") == strings.Join(dep.Name, ".")
}

// checkImportCycle 检查包导入图是否有环（§3.4）。只报告第一个环。
func (a *analyzer) checkImportCycle(u *xfront.CompilationUnit) {
	if a.deps == nil {
		return
	}
	const (
		gray  = 1
		black = 2
	)
	state := map[string]int{}
	var stack []string
	reported := false

	var visit func(p []string, pos xfront.Pos)
	visit = func(p []string, pos xfront.Pos) {
		if reported || len(p) == 0 || p[0] == "xdk" {
			return
		}
		dep, _, ok := a.resolveUserImport(p)
		if !ok {
			return
		}
		k := strings.Join(dep.Path, ".")
		switch state[k] {
		case gray:
			chain := append(append([]string{}, stack...), k)
			a.errf(pos, ResImportCycle, "包导入图存在环（§3.4）："+strings.Join(chain, " → "),
				"拆出公共依赖包，消除互相 import")
			reported = true
			return
		case black:
			return
		}
		state[k] = gray
		stack = append(stack, k)
		for _, imp := range dep.Imports {
			visit(imp, pos)
			if reported {
				return
			}
		}
		stack = stack[:len(stack)-1]
		state[k] = black
	}
	for _, imp := range u.Imports {
		visit(imp.Path, imp.P)
		if reported {
			return
		}
	}
}

// sortedKeys 返回确定性排序的符号名（诊断顺序稳定，DET-01）。
func sortedKeys(m map[string]bool) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}
