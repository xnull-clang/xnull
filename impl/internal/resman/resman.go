// Package resman 实现 S8 §5.6 资源收割器（清单侧）：
// 资源根 + includes/excludes glob、制品内 `resources/` 前缀、同路径冲突点名、
// 依赖资源合并、starter/pom 规则、符号链接与测试资源隔离。诊断码 XPD-8xx。
package resman

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"xnull.dev/xnull/internal/diag"
)

// 诊断码（S8 附录 C.6：8xx = 资源与打包）。
const (
	codeRoot        = "XPD-801" // 资源根不存在/非法
	codeGlob        = "XPD-802" // glob 语法错误
	codeConflict    = "XPD-803" // 制品内同路径冲突
	codePomResource = "XPD-804" // pom 声明资源
	codeSymlink     = "XPD-805" // 符号链接断链/指向目录
)

// Root 是一个资源根声明。
type Root struct {
	Path     string
	Includes []string // 缺省 ["**"]
	Excludes []string
	Owner    string // 归属（groupId:artifactId）；空则用路径
}

// Entry 是制品内的一项资源。
type Entry struct {
	ArtifactPath string // `resources/<相对路径>`
	SourcePath   string // 源文件绝对路径
	Origin       string // 来源归属（owner 或根路径）
	Data         []byte
}

// Set 是资源集合（ArtifactPath → Entry）。
type Set struct {
	Entries map[string]Entry
}

func newSet() Set { return Set{Entries: map[string]Entry{}} }

// Collect 收割一组资源根；冲突、非法根、断链、非法 glob 均返回诊断。
func Collect(roots []Root) (Set, []diag.Diagnostic) {
	set := newSet()
	var ds []diag.Diagnostic
	for _, root := range roots {
		ds = append(ds, collectRoot(root, set)...)
	}
	sort.Slice(ds, func(i, j int) bool {
		if ds[i].File != ds[j].File {
			return ds[i].File < ds[j].File
		}
		return ds[i].Message < ds[j].Message
	})
	return set, ds
}

// CollectForPhase 收割指定阶段可见的资源：main 只含主资源，test 额外并入测试资源。
func CollectForPhase(phase string, mainRoots, testRoots []Root) (Set, []diag.Diagnostic) {
	set, ds := Collect(mainRoots)
	if phase != "test" {
		return set, ds
	}
	tset, tds := Collect(testRoots)
	ds = append(ds, tds...)
	for path, e := range tset.Entries {
		if prev, ok := set.Entries[path]; ok {
			ds = append(ds, diag.Diagnostic{File: e.SourcePath, Line: 1, Col: 1, Code: codeConflict,
				Message: fmt.Sprintf("测试资源与主资源同路径冲突：%s（%s 与 %s）", path, prev.Origin, e.Origin)})
			continue
		}
		set.Entries[path] = e
	}
	return set, ds
}

// CollectForPackaging 校验 packaging 规则：pom 声明任何资源根/资源条即失败。
func CollectForPackaging(packaging string, roots []Root) (Set, []diag.Diagnostic) {
	if packaging == "pom" && len(roots) > 0 {
		return newSet(), []diag.Diagnostic{{File: "xnull.project", Line: 1, Col: 1, Code: codePomResource,
			Message: "pom 不得声明资源根或 build.resources（S8 §5.6）"}}
	}
	return Collect(roots)
}

// MergeDependency 把依赖的资源并入 app；starter 的资源不合并（只随其元数据发布）。
// 同路径冲突点名两个 groupId:artifactId。
func MergeDependency(app Set, depOwner string, dep Set, depPackaging string) (Set, []diag.Diagnostic) {
	if depPackaging == "starter" {
		return cloneSet(app), nil
	}
	merged := cloneSet(app)
	app = merged
	var ds []diag.Diagnostic
	paths := make([]string, 0, len(dep.Entries))
	for p := range dep.Entries {
		paths = append(paths, p)
	}
	sort.Strings(paths)
	for _, p := range paths {
		e := dep.Entries[p]
		if prev, ok := app.Entries[p]; ok {
			ds = append(ds, diag.Diagnostic{File: e.SourcePath, Line: 1, Col: 1, Code: codeConflict,
				Message: fmt.Sprintf("依赖资源同路径冲突：%s（%s 与 %s）", p, prev.Origin, depOwner)})
			continue
		}
		app.Entries[p] = e
	}
	return app, ds
}

func cloneSet(s Set) Set {
	out := newSet()
	for k, v := range s.Entries {
		out.Entries[k] = v
	}
	return out
}

func collectRoot(root Root, set Set) []diag.Diagnostic {
	var ds []diag.Diagnostic
	st, err := os.Stat(root.Path)
	if err != nil || !st.IsDir() {
		return []diag.Diagnostic{{File: root.Path, Line: 1, Col: 1, Code: codeRoot,
			Message: fmt.Sprintf("资源根不存在或不是目录：%s（S8 §5.6）", root.Path)}}
	}
	includes := root.Includes
	if len(includes) == 0 {
		includes = []string{"**"}
	}
	for _, pat := range append(append([]string{}, includes...), root.Excludes...) {
		if err := validateGlob(pat); err != nil {
			return []diag.Diagnostic{{File: root.Path, Line: 1, Col: 1, Code: codeGlob,
				Message: fmt.Sprintf("glob 语法错误 %q：%v（S8 §5.6）", pat, err)}}
		}
	}
	origin := root.Owner
	if origin == "" {
		origin = root.Path
	}
	walkErr := filepath.WalkDir(root.Path, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		rel, rerr := filepath.Rel(root.Path, path)
		if rerr != nil {
			return rerr
		}
		rel = filepath.ToSlash(rel)
		if d.Type()&os.ModeSymlink != 0 {
			target, serr := os.Stat(path)
			if serr != nil {
				ds = append(ds, diag.Diagnostic{File: path, Line: 1, Col: 1, Code: codeSymlink,
					Message: fmt.Sprintf("符号链接断链：%s（S8 §5.6）", rel)})
				return nil
			}
			if target.IsDir() {
				ds = append(ds, diag.Diagnostic{File: path, Line: 1, Col: 1, Code: codeSymlink,
					Message: fmt.Sprintf("符号链接指向目录（不支持）：%s（S8 §5.6）", rel)})
				return nil
			}
		}
		if !included(rel, includes, root.Excludes) {
			return nil
		}
		data, rerr := os.ReadFile(path)
		if rerr != nil {
			ds = append(ds, diag.Diagnostic{File: path, Line: 1, Col: 1, Code: codeRoot,
				Message: fmt.Sprintf("读取资源失败：%v", rerr)})
			return nil
		}
		artifact := "resources/" + rel
		if prev, ok := set.Entries[artifact]; ok {
			ds = append(ds, diag.Diagnostic{File: path, Line: 1, Col: 1, Code: codeConflict,
				Message: fmt.Sprintf("制品内同路径冲突：%s（%s 与 %s）", artifact, prev.SourcePath, path)})
			return nil
		}
		set.Entries[artifact] = Entry{ArtifactPath: artifact, SourcePath: path, Origin: origin, Data: data}
		return nil
	})
	if walkErr != nil {
		ds = append(ds, diag.Diagnostic{File: root.Path, Line: 1, Col: 1, Code: codeRoot,
			Message: fmt.Sprintf("遍历资源根失败：%v", walkErr)})
	}
	return ds
}

func included(rel string, includes, excludes []string) bool {
	ok := false
	for _, pat := range includes {
		if Match(pat, rel) {
			ok = true
			break
		}
	}
	if !ok {
		return false
	}
	for _, pat := range excludes {
		if Match(pat, rel) {
			return false
		}
	}
	return true
}

func validateGlob(pat string) error {
	if pat == "" {
		return fmt.Errorf("空模式")
	}
	if strings.ContainsAny(pat, "[]") {
		return fmt.Errorf("不支持字符类（[ ]）")
	}
	if strings.Contains(pat, "\\") {
		return fmt.Errorf("只接受 / 分隔")
	}
	if strings.HasPrefix(pat, "/") {
		return fmt.Errorf("模式不得以 / 开头")
	}
	for _, seg := range strings.Split(pat, "/") {
		if seg == "" {
			return fmt.Errorf("出现空段")
		}
	}
	return nil
}

// Match 实现 S8 §5.6 的 glob：`*` 单段内任意、`**` 跨段（可消费零段）、`?` 单字符。
func Match(pattern, path string) bool {
	return matchSegs(strings.Split(pattern, "/"), strings.Split(path, "/"))
}

func matchSegs(pat, path []string) bool {
	if len(pat) == 0 {
		return len(path) == 0
	}
	if pat[0] == "**" {
		if len(pat) == 1 {
			return true
		}
		for i := 0; i <= len(path); i++ {
			if matchSegs(pat[1:], path[i:]) {
				return true
			}
		}
		return false
	}
	if len(path) == 0 {
		return false
	}
	if !matchSegment(pat[0], path[0]) {
		return false
	}
	return matchSegs(pat[1:], path[1:])
}

func matchSegment(pat, s string) bool {
	// 逐字节通配（* 任意串、? 单字符）
	if pat == "" {
		return s == ""
	}
	switch pat[0] {
	case '*':
		for i := 0; i <= len(s); i++ {
			if matchSegment(pat[1:], s[i:]) {
				return true
			}
		}
		return false
	case '?':
		if s == "" {
			return false
		}
		return matchSegment(pat[1:], s[1:])
	default:
		if s == "" || pat[0] != s[0] {
			return false
		}
		return matchSegment(pat[1:], s[1:])
	}
}
