// Package reactor 实现 S8 §2.1/附录 A.3 的聚合工程：pom/modules 解析、模块图与拓扑排序、
// library → app 构建顺序、starter 传递依赖、失败即停。诊断码沿用 XPD 段位。
package reactor

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"

	"xnull.dev/xnull/internal/diag"
	"xnull.dev/xnull/internal/manifest"
	"xnull.dev/xnull/internal/xpd"
)

// Options 是聚合解析参数。
type Options struct {
	ToolchainVersion string
	Platform         string
	Profiles         []string
}

// Module 是聚合中的一个模块。
type Module struct {
	Rel        string // 相对聚合根的目录
	Dir        string
	GroupID    string
	ArtifactID string
	Version    string
	Packaging  string
	Deps       map[string]string // 依赖坐标 → 版本（含 starter 展开）
}

// Plan 是聚合构建计划。
type Plan struct {
	Root    string
	Managed map[string]string // 聚合根 dependencyManagement
	Modules []Module
	Order   []string // 模块目录，拓扑序
}

// Result 是单模块构建结果。
type Result struct {
	Module   string
	Artifact string
}

// Load 解析聚合根与模块，校验规则并给出拓扑序。
func Load(root string, opts Options) (*Plan, []diag.Diagnostic, error) {
	rootManifest := filepath.Join(root, "xnull.project")
	res, ds, err := manifest.ResolveDependencies(rootManifest, manifest.Options{
		ToolchainVersion: opts.ToolchainVersion,
		Platform:         opts.Platform,
		Profiles:         opts.Profiles,
	})
	if err != nil {
		return nil, nil, err
	}
	if len(ds) > 0 {
		return nil, ds, nil
	}
	if res.Packaging != "pom" {
		return nil, []diag.Diagnostic{{File: rootManifest, Line: 1, Col: 1, Code: "XPD-201",
			Message: "聚合根必须是 packaging = pom（S8 §2.1）"}}, nil
	}

	rels, rds, rerr := readModules(root)
	if rerr != nil {
		return nil, nil, rerr
	}
	if len(rds) > 0 {
		return nil, rds, nil
	}
	plan := &Plan{Root: root, Managed: res.Managed}
	ds = nil
	for _, rel := range rels {
		dir := filepath.Join(root, filepath.FromSlash(rel))
		mres, mds, merr := manifest.ResolveDependencies(filepath.Join(dir, "xnull.project"), manifest.Options{
			ToolchainVersion: opts.ToolchainVersion,
			Platform:         opts.Platform,
			Profiles:         opts.Profiles,
			ManagedFallback:  res.Managed,
		})
		if merr != nil {
			return nil, nil, merr
		}
		if len(mds) > 0 {
			ds = append(ds, mds...)
			continue
		}
		switch mres.Packaging {
		case "library", "starter", "app":
		default:
			ds = append(ds, diag.Diagnostic{File: filepath.Join(dir, "xnull.project"), Line: 1, Col: 1, Code: "XPD-201",
				Message: fmt.Sprintf("聚合模块 %s 的 packaging 不支持：%s（限 library/starter/app，S8 §2.1）", rel, mres.Packaging)})
			continue
		}
		if mres.Packaging == "starter" {
			if st, serr := os.Stat(filepath.Join(dir, "src")); serr == nil && st.IsDir() {
				ds = append(ds, diag.Diagnostic{File: filepath.Join(dir, "xnull.project"), Line: 1, Col: 1, Code: "XPD-201",
					Message: fmt.Sprintf("starter 模块 %s 不得含源码目录 src/（S8 §2.1）", rel)})
				continue
			}
		}
		plan.Modules = append(plan.Modules, Module{
			Rel: rel, Dir: dir,
			GroupID: mres.GroupID, ArtifactID: mres.ArtifactID, Version: mres.Version,
			Packaging: mres.Packaging,
			Deps:      cloneDeps(mres.Dependencies),
		})
	}
	if len(ds) > 0 {
		return nil, ds, nil
	}

	// GAV 唯一
	seen := map[string]string{}
	for _, m := range plan.Modules {
		gav := m.GroupID + ":" + m.ArtifactID + ":" + m.Version
		if prev, ok := seen[gav]; ok {
			ds = append(ds, diag.Diagnostic{File: m.Dir, Line: 1, Col: 1, Code: "XPD-302",
				Message: fmt.Sprintf("同一次构建内 GAV 重复：%s（%s 与 %s，S8 §2.2）", gav, prev, m.Rel)})
		}
		seen[gav] = m.Rel
	}
	if len(ds) > 0 {
		return nil, ds, nil
	}

	// starter 传递依赖：把 starter 的依赖并入使用者（递归；starter 只带依赖不带代码）。
	idx := map[string]int{}
	for i, m := range plan.Modules {
		idx[m.GroupID+":"+m.ArtifactID] = i
	}
	for i := range plan.Modules {
		if err := expandStarters(plan, idx, i, map[int]bool{}); err != nil {
			ds = append(ds, diag.Diagnostic{File: plan.Modules[i].Dir, Line: 1, Col: 1, Code: "XPD-409",
				Message: fmt.Sprintf("starter 依赖成环：%v（S8 §4.5）", err)})
		}
	}
	if len(ds) > 0 {
		return nil, ds, nil
	}

	// 版本一致性（模块间依赖）
	for i, m := range plan.Modules {
		for coord, ver := range m.Deps {
			j, ok := idx[coord]
			if !ok {
				continue
			}
			if plan.Modules[j].Version != ver {
				ds = append(ds, diag.Diagnostic{File: m.Dir, Line: 1, Col: 1, Code: "XPD-403",
					Message: fmt.Sprintf("模块 %s 依赖 %s 版本 %s ≠ 模块版本 %s（S8 §4.2）",
						m.Rel, coord, ver, plan.Modules[j].Version)})
			}
		}
		if m.Packaging == "app" {
			continue
		}
		_ = i
	}
	if len(ds) > 0 {
		return nil, ds, nil
	}

	order, tds := topoOrder(plan, idx)
	if len(tds) > 0 {
		return nil, tds, nil
	}
	plan.Order = order
	return plan, nil, nil
}

func cloneDeps(src map[string]string) map[string]string {
	out := make(map[string]string, len(src))
	for k, v := range src {
		out[k] = v
	}
	return out
}

// readModules 解析聚合根的 modules 列表（顺序即声明顺序）。
func readModules(root string) ([]string, []diag.Diagnostic, error) {
	src, err := os.ReadFile(filepath.Join(root, "xnull.project"))
	if err != nil {
		return nil, nil, err
	}
	f, sdiags := xpd.Parse("xnull.project", string(src))
	if len(sdiags) > 0 {
		return nil, sdiags, nil
	}
	proj := f.Find("project")
	if proj == nil {
		return nil, []diag.Diagnostic{{File: "xnull.project", Line: 1, Col: 1, Code: "XPD-201", Message: "缺 project 块"}}, nil
	}
	var rels []string
	var ds []diag.Diagnostic
	for _, n := range proj.Children {
		b, ok := n.(*xpd.Block)
		if !ok || b.Name != "modules" {
			continue
		}
		for _, mn := range b.Children {
			mb, ok := mn.(*xpd.Block)
			if !ok || mb.Name != "module" || len(mb.Args) == 0 {
				continue
			}
			rel := mb.Args[0].Text
			if filepath.IsAbs(rel) || rel == "" || rel == "." || rel == ".." {
				ds = append(ds, diag.Diagnostic{File: "xnull.project", Line: mb.Pos.Line, Col: mb.Pos.Col, Code: "XPD-201",
					Message: "module 必须是聚合根下的相对目录（S8 §2.3）：" + rel})
				continue
			}
			rels = append(rels, rel)
		}
	}
	return rels, ds, nil
}

// expandStarters 把 starter 依赖递归并入使用者（只展开 starter）。
func expandStarters(plan *Plan, idx map[string]int, i int, visiting map[int]bool) error {
	if visiting[i] {
		return fmt.Errorf("%s", plan.Modules[i].Rel)
	}
	visiting[i] = true
	defer delete(visiting, i)
	for coord, ver := range cloneDeps(plan.Modules[i].Deps) {
		j, ok := idx[coord]
		if !ok || plan.Modules[j].Packaging != "starter" {
			continue
		}
		if err := expandStarters(plan, idx, j, visiting); err != nil {
			return err
		}
		for depCoord, depVer := range plan.Modules[j].Deps {
			if _, exists := plan.Modules[i].Deps[depCoord]; !exists {
				plan.Modules[i].Deps[depCoord] = depVer
			}
		}
		_ = ver
	}
	return nil
}

// topoOrder 用 Kahn 算法排序；同层按 modules 声明顺序（确定性）。
func topoOrder(plan *Plan, idx map[string]int) ([]string, []diag.Diagnostic) {
	n := len(plan.Modules)
	indeg := make([]int, n)
	edges := make([][]int, n)
	for i, m := range plan.Modules {
		for coord := range m.Deps {
			j, ok := idx[coord]
			if !ok || j == i {
				continue
			}
			edges[j] = append(edges[j], i) // j 先于 i
			indeg[i]++
		}
	}
	ready := []int{}
	for i := 0; i < n; i++ {
		if indeg[i] == 0 {
			ready = append(ready, i)
		}
	}
	sort.Ints(ready)
	var order []string
	for len(ready) > 0 {
		i := ready[0]
		ready = ready[1:]
		order = append(order, plan.Modules[i].Rel)
		for _, next := range edges[i] {
			indeg[next]--
			if indeg[next] == 0 {
				ready = append(ready, next)
				sort.Ints(ready)
			}
		}
	}
	if len(order) != n {
		var left []string
		for i := 0; i < n; i++ {
			if indeg[i] > 0 {
				left = append(left, plan.Modules[i].Rel)
			}
		}
		return nil, []diag.Diagnostic{{File: plan.Root, Line: 1, Col: 1, Code: "XPD-409",
			Message: fmt.Sprintf("模块依赖环：%v（S8 §4.5）", left)}}
	}
	return order, nil
}

// Build 按拓扑序逐模块构建；首个失败即停（fail-fast）。
func Build(plan *Plan, build func(Module) (string, error)) ([]Result, []diag.Diagnostic) {
	byRel := map[string]Module{}
	for _, m := range plan.Modules {
		byRel[m.Rel] = m
	}
	var results []Result
	for _, rel := range plan.Order {
		m := byRel[rel]
		artifact, err := build(m)
		if err != nil {
			return results, []diag.Diagnostic{{File: m.Dir, Line: 1, Col: 1, Code: "XPD-201",
				Message: fmt.Sprintf("模块 %s 构建失败：%v（失败即停，S8 §5.1）", rel, err)}}
		}
		results = append(results, Result{Module: rel, Artifact: artifact})
	}
	return results, nil
}
