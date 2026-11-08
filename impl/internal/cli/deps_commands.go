// deps_commands.go：S8-17 依赖命令（install / tree / why），复用 artifact 与 manifest 图。
package cli

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"xnull.dev/xnull/internal/artifact"
	"xnull.dev/xnull/internal/exitcode"
	"xnull.dev/xnull/internal/manifest"
)

// runDepsCommand 分派 install/tree/why。
func runDepsCommand(env Env, name string, rest []string) int {
	switch name {
	case "install":
		return runInstall(env, rest)
	case "tree":
		return runTree(env, rest)
	case "why":
		return runWhy(env, rest)
	}
	return exitcode.Usage
}

func depsTarget(env Env, rest []string) (root, profile string, rest2 []string) {
	dir := env.Dir
	if dir == "" {
		dir = "."
	}
	profile = flagValue(rest, "--profile")
	for _, a := range rest {
		if strings.HasPrefix(a, "-") {
			continue
		}
		if _, err := os.Stat(a); err == nil {
			dir = a
			continue
		}
		rest2 = append(rest2, a)
	}
	root = findManifestRoot(dir)
	return root, profile, rest2
}

func loadGraph(env Env, root, profile string) (*projectManifest, *manifest.Resolved, *manifest.Graph, int) {
	m, res, mds := loadProjectManifest(root, profile, nil)
	if len(mds) > 0 {
		printDiags(env, mds)
		return nil, nil, nil, exitcode.BuildFail
	}
	graph, gds := manifest.ResolveGraph(res, os.Getenv("XNULL_REPO"))
	if len(gds) > 0 {
		printDiags(env, gds)
		return nil, nil, nil, exitcode.BuildFail
	}
	return m, res, graph, exitcode.Success
}

// runInstall：构建并安装到本地仓库（library → .xlib；app → 可执行体 + .xmeta）。
func runInstall(env Env, rest []string) int {
	root, _, _ := depsTarget(env, rest)
	if root == "" {
		fmt.Fprintln(env.Stderr, "xnull: 找不到 xnull.project")
		return exitcode.Usage
	}
	repo := os.Getenv("XNULL_REPO")
	if repo == "" {
		if home, err := os.UserHomeDir(); err == nil {
			repo = filepath.Join(home, ".xnull", "repository")
		}
	}
	if repo == "" {
		fmt.Fprintln(env.Stderr, "xnull: 无法确定本地仓库（设置 XNULL_REPO）")
		return exitcode.BuildFail
	}
	built, code := buildManifestManaged(env, nil, root, nil)
	if code != exitcode.Success {
		return code
	}
	data, err := os.ReadFile(built)
	if err != nil {
		fmt.Fprintf(env.Stderr, "xnull: 读取产物失败：%v\n", err)
		return exitcode.BuildFail
	}
	sum := sha256.Sum256(data)
	// library 的 install 阶段已在构建内完成；app 在此复制产物与 .xmeta。
	if !strings.HasSuffix(built, ".xlib") {
		m, _, _, c := loadGraph(env, root, flagValue(rest, "--profile"))
		if c != exitcode.Success {
			return c
		}
		dir := artifact.RepoDir(repo, m.GroupID, m.ArtifactID, m.Version)
		if err := os.MkdirAll(dir, 0o755); err != nil {
			fmt.Fprintf(env.Stderr, "xnull: %v\n", err)
			return exitcode.BuildFail
		}
		dst := filepath.Join(dir, filepath.Base(built))
		if err := os.WriteFile(dst, data, 0o755); err != nil {
			fmt.Fprintf(env.Stderr, "xnull: %v\n", err)
			return exitcode.BuildFail
		}
		if meta, merr := os.ReadFile(built + ".xmeta"); merr == nil {
			_ = os.WriteFile(dst+".xmeta", meta, 0o644)
		}
		if src, serr := os.ReadFile(filepath.Join(root, "xnull.project")); serr == nil {
			_ = os.WriteFile(filepath.Join(dir, "xnull.project"), src, 0o644)
		}
	}
	fmt.Fprintf(env.Stdout, "已安装 %s（sha256 %s）\n", built, hex.EncodeToString(sum[:]))
	return exitcode.Success
}

// runTree：输出依赖树（坐标@版本，缩进表示层级）。
func runTree(env Env, rest []string) int {
	root, profile, _ := depsTarget(env, rest)
	if root == "" {
		fmt.Fprintln(env.Stderr, "xnull: 找不到 xnull.project")
		return exitcode.Usage
	}
	m, _, graph, code := loadGraph(env, root, profile)
	if code != exitcode.Success {
		return code
	}
	children := map[string][]string{}
	for coord := range graph.Selected {
		path := graph.Paths[coord]
		if len(path) == 0 {
			continue
		}
		parent := ""
		if len(path) >= 2 {
			parent = stripVersion(path[len(path)-2])
		}
		children[parent] = append(children[parent], coord)
	}
	for k := range children {
		sort.Strings(children[k])
	}
	fmt.Fprintf(env.Stdout, "%s:%s@%s\n", m.GroupID, m.ArtifactID, m.Version)
	var walk func(parent string, depth int)
	walk = func(parent string, depth int) {
		for _, coord := range children[parent] {
			fmt.Fprintf(env.Stdout, "%s%s@%s\n", strings.Repeat("  ", depth+1), coord, graph.Selected[coord])
			walk(coord, depth+1)
		}
	}
	walk("", 0)
	return exitcode.Success
}

// runWhy：解释某依赖为何被引入（路径 + 版本来源 + 深度）。
func runWhy(env Env, rest []string) int {
	root, profile, positional := depsTarget(env, rest)
	if root == "" {
		fmt.Fprintln(env.Stderr, "xnull: 找不到 xnull.project")
		return exitcode.Usage
	}
	if len(positional) == 0 {
		fmt.Fprintln(env.Stderr, "xnull: why 需要坐标（groupId:artifactId）")
		return exitcode.Usage
	}
	coord := positional[0]
	_, res, graph, code := loadGraph(env, root, profile)
	if code != exitcode.Success {
		return code
	}
	version, ok := graph.Selected[coord]
	if !ok {
		fmt.Fprintf(env.Stderr, "xnull: 依赖 %s 未被解析（不在依赖图中）\n", coord)
		return exitcode.Usage
	}
	path := graph.Paths[coord]
	fmt.Fprintf(env.Stdout, "坐标：%s\n", coord)
	fmt.Fprintf(env.Stdout, "版本：%s\n", version)
	labels := make([]string, 0, len(path))
	for _, p := range path {
		labels = append(labels, p)
	}
	fmt.Fprintf(env.Stdout, "路径：%s\n", strings.Join(labels, " -> "))
	source := "最近优先（路径最短）"
	if len(path) <= 1 {
		source = "直接依赖"
	} else if pin, ok := res.Managed[coord]; ok && pin == version {
		source = "dependencyManagement 固定"
	}
	fmt.Fprintf(env.Stdout, "来源：%s\n", source)
	fmt.Fprintf(env.Stdout, "深度：%d\n", len(path))
	return exitcode.Success
}

func stripVersion(node string) string {
	if i := strings.LastIndex(node, "@"); i > 0 {
		return node[:i]
	}
	return node
}
