package manifest

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"xnull.dev/xnull/internal/diag"
)

const (
	codeGraphCycle = "XPD-409" // 依赖环
	codeGraphMeta  = "XPD-408" // 依赖元数据非法（清单语义错误）
)

// Graph 是解析后的依赖图（传递闭包 + 仲裁结果）。
type Graph struct {
	Selected map[string]string   // 坐标 → 仲裁后版本
	Depth    map[string]int      // 坐标 → 最近深度
	Paths    map[string][]string // 坐标 → 选中路径（root 依赖 → … → 坐标@版本）
}

type cand struct {
	version string
	depth   int
	path    []string
}

type gitem struct {
	coord   string
	version string
	depth   int
	path    []string
	scope   string
	excl    map[string]bool
}

// ResolveGraph 构建传递依赖图并做仲裁（S8 §4.2）：
// 最近优先；同深度多版本 → XPD-403 并输出全部路径；management 版本恒优先。
func ResolveGraph(res *Resolved, repoRoot string) (*Graph, []diag.Diagnostic) {
	var ds []diag.Diagnostic
	cands := map[string][]cand{}
	queue := []gitem{}

	coords := sortedKeys(res.Dependencies)
	for _, coord := range coords {
		scope := res.Scopes[coord]
		if scope == "" {
			scope = "compile"
		}
		excl := map[string]bool{}
		for _, e := range res.Exclusions[coord] {
			excl[e] = true
		}
		queue = append(queue, gitem{coord: coord, version: res.Dependencies[coord], depth: 1,
			path: []string{coord + "@" + res.Dependencies[coord]}, scope: scope, excl: excl})
	}

	for len(queue) > 0 {
		it := queue[0]
		queue = queue[1:]
		if len(it.path) > 64 {
			continue
		}
		if countInPath(it.path, it.coord+"@"+it.version) > 1 {
			ds = append(ds, diag.Diagnostic{File: "xnull.graph", Line: 1, Col: 1, Code: codeGraphCycle,
				Message: fmt.Sprintf("依赖环：%s（S8 §4.5）", strings.Join(it.path, " -> "))})
			continue
		}
		cands[it.coord] = append(cands[it.coord], cand{version: it.version, depth: it.depth, path: it.path})

		// 传递：test/provided 不传递；其自身仍出现在锁中（直接依赖）。
		if it.scope != "compile" && it.scope != "runtime" {
			continue
		}
		projPath := repoManifestPath(repoRoot, it.coord, it.version)
		if projPath == "" {
			continue
		}
		if _, err := os.Stat(projPath); err != nil {
			continue // 无元数据：视为叶子（不构造虚假子依赖）
		}
		depRes, dds, err := ResolveDependencies(projPath, Options{})
		if err != nil || len(dds) > 0 {
			m := fmt.Sprintf("依赖 %s@%s 的清单非法", it.coord, it.version)
			if err != nil {
				m += "：" + err.Error()
			} else if len(dds) > 0 {
				m += "：" + dds[0].Message
			}
			ds = append(ds, diag.Diagnostic{File: projPath, Line: 1, Col: 1, Code: codeGraphMeta, Message: m})
			continue
		}
		childCoords := sortedKeys(depRes.Dependencies)
		for _, cc := range childCoords {
			ver := depRes.Dependencies[cc]
			if ver == "" {
				ver = depRes.Managed[cc]
			}
			if ver == "" {
				ds = append(ds, diag.Diagnostic{File: projPath, Line: 1, Col: 1, Code: codeDepVersion,
					Message: fmt.Sprintf("传递依赖 %s 无版本（S8 §3.5）", cc)})
				continue
			}
			if it.excl[cc] {
				continue
			}
			childExcl := map[string]bool{}
			for k := range it.excl {
				childExcl[k] = true
			}
			for _, e := range depRes.Exclusions[cc] {
				childExcl[e] = true
			}
			childScope := depRes.Scopes[cc]
			if childScope == "" {
				childScope = "compile"
			}
			if it.scope == "runtime" {
				childScope = "runtime"
			}
			path := append(append([]string{}, it.path...), cc+"@"+ver)
			queue = append(queue, gitem{coord: cc, version: ver, depth: it.depth + 1,
				path: path, scope: childScope, excl: childExcl})
		}
	}

	g := &Graph{Selected: map[string]string{}, Depth: map[string]int{}, Paths: map[string][]string{}}
	for _, coord := range sortedKeysCands(cands) {
		list := cands[coord]
		if pin, ok := res.Managed[coord]; ok && pin != "" {
			g.Selected[coord] = pin
			g.Depth[coord] = 0
			best := list[0]
			for _, c := range list {
				if c.version == pin {
					best = c
					break
				}
			}
			g.Paths[coord] = best.path
			continue
		}
		minDepth := list[0].depth
		for _, c := range list {
			if c.depth < minDepth {
				minDepth = c.depth
			}
		}
		versions := map[string]bool{}
		var chosen cand
		for _, c := range list {
			if c.depth != minDepth {
				continue
			}
			versions[c.version] = true
			chosen = c
		}
		if len(versions) > 1 {
			var lines []string
			for _, c := range list {
				if c.depth != minDepth {
					continue
				}
				lines = append(lines, fmt.Sprintf("%s@%s <- %s", coord, c.version, strings.Join(c.path, " -> ")))
			}
			sort.Strings(lines)
			ds = append(ds, diag.Diagnostic{File: "xnull.graph", Line: 1, Col: 1, Code: codeDepConflict,
				Message: fmt.Sprintf("同深度依赖冲突（不取第一个，S8 §4.2）：%s", strings.Join(lines, "；"))})
			continue
		}
		g.Selected[coord] = chosen.version
		g.Depth[coord] = minDepth
		g.Paths[coord] = chosen.path
	}
	if len(ds) > 0 {
		return nil, ds
	}
	return g, nil
}

func countInPath(path []string, node string) int {
	n := 0
	for _, p := range path {
		if p == node {
			n++
		}
	}
	return n
}

func repoManifestPath(repoRoot, coord, version string) string {
	if repoRoot == "" {
		return ""
	}
	parts := strings.SplitN(coord, ":", 2)
	if len(parts) != 2 {
		return ""
	}
	return filepath.Join(repoRoot, filepath.FromSlash(strings.ReplaceAll(parts[0], ".", "/")), parts[1], version, "xnull.project")
}

func sortedKeys(m map[string]string) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

func sortedKeysCands(m map[string][]cand) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

// GenerateLockForGraph 依据依赖图（含传递依赖）生成锁。
func GenerateLockForGraph(res *Resolved, g *Graph, repoRoot string, prev *Lock) (*Lock, []diag.Diagnostic) {
	var ds []diag.Diagnostic
	out := &Lock{Version: 1}
	for _, coord := range sortedKeys(g.Selected) {
		ver := g.Selected[coord]
		sum := ""
		if prev != nil {
			if e, ok := prev.entry(coord); ok && e.Version == ver {
				sum = e.SHA256
			}
		}
		if sum == "" && repoRoot != "" {
			if got, ok := artifactSHA(repoRoot, coord, ver); ok {
				sum = got
			}
		}
		if sum == "" {
			ds = append(ds, diag.Diagnostic{File: "xnull.lock", Line: 1, Col: 1, Code: codeLockMismatch,
				Message: fmt.Sprintf("无法取得 %s %s 的制品摘要：请设置 XNULL_REPO（S8 §4.4）", coord, ver)})
			continue
		}
		out.Entries = append(out.Entries, LockEntry{Coordinate: coord, Version: ver, Kind: "dependency",
			Repository: "central", SHA256: sum})
	}
	if len(ds) > 0 {
		return nil, ds
	}
	return out, nil
}

// ValidateLockForGraph 校验锁与依赖图一致（传递依赖必须全部在锁中）。
func ValidateLockForGraph(lock *Lock, g *Graph, repoRoot string) []diag.Diagnostic {
	var ds []diag.Diagnostic
	manifestCoords := map[string]bool{}
	for _, coord := range sortedKeys(g.Selected) {
		ver := g.Selected[coord]
		manifestCoords[coord] = true
		e, ok := lock.entry(coord)
		if !ok {
			ds = append(ds, diag.Diagnostic{File: "xnull.lock", Line: 1, Col: 1, Code: codeLockMismatch,
				Message: fmt.Sprintf("锁缺少依赖 %s %s（请 --update-lock，S8 §4.4）", coord, ver)})
			continue
		}
		if e.Version != ver {
			ds = append(ds, diag.Diagnostic{File: "xnull.lock", Line: 1, Col: 1, Code: codeLockMismatch,
				Message: fmt.Sprintf("锁与依赖图不一致：%s 锁 %s，解析 %s（S8 §4.4）", coord, e.Version, ver)})
			continue
		}
		if !isHex64(e.SHA256) {
			ds = append(ds, diag.Diagnostic{File: "xnull.lock", Line: 1, Col: 1, Code: codeLockDigest,
				Message: fmt.Sprintf("锁摘要格式非法：%s", coord)})
			continue
		}
		if repoRoot != "" {
			if got, ok := artifactSHA(repoRoot, coord, ver); ok && got != e.SHA256 {
				ds = append(ds, diag.Diagnostic{File: "xnull.lock", Line: 1, Col: 1, Code: codeLockDigest,
					Message: fmt.Sprintf("制品摘要不符：%s %s（S8 §4.4）", coord, ver)})
			}
		}
	}
	for _, e := range lock.Entries {
		if !manifestCoords[e.Coordinate] {
			ds = append(ds, diag.Diagnostic{File: "xnull.lock", Line: 1, Col: 1, Code: codeLockExtra,
				Message: fmt.Sprintf("锁中坐标在依赖图中不存在：%s（S8 §4.4）", e.Coordinate)})
		}
	}
	return ds
}
