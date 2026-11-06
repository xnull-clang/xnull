package ffi

import (
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// Load 解析并校验 root 下全部 .xfb 绑定声明文件。
//
//   - 无 .xfb：返回空注册表、无诊断、nil error（无 FFI 的空路径零成本）；
//   - 有诊断：返回 nil 注册表 + 全部诊断（构建按错误处理），error 仅为 IO 故障；
//   - 结果确定性：注册表按名称排序、诊断按文件/行/列/码排序（DET-01）。
func Load(root string) (*Registry, []Diagnostic, error) {
	files, err := findXfb(root)
	if err != nil {
		return nil, nil, err
	}
	if len(files) == 0 {
		return &Registry{}, nil, nil
	}
	reg := &Registry{}
	var diags []Diagnostic
	for _, path := range files {
		src, err := os.ReadFile(path)
		if err != nil {
			return nil, nil, err
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			rel = path
		}
		rel = filepath.ToSlash(rel)
		regions, pdiags := parseFile(string(src), rel)
		diags = append(diags, pdiags...)
		if len(pdiags) > 0 {
			continue // 语法错误：该文件不进入合同校验
		}
		for _, rg := range regions {
			diags = append(diags, newChecker(rel, rg, reg).run()...)
		}
	}
	fillSnippets(root, diags)
	sortDiags(diags)
	if len(diags) > 0 {
		return nil, diags, nil
	}
	reg.sortAll()
	return reg, nil, nil
}

// findXfb 收集 .xfb 文件（跳过隐藏目录与构建产物目录），返回排序后的路径。
func findXfb(root string) ([]string, error) {
	var out []string
	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			name := d.Name()
			if path != root && (strings.HasPrefix(name, ".") || name == "target") {
				return fs.SkipDir
			}
			return nil
		}
		if strings.HasSuffix(d.Name(), ".xfb") {
			out = append(out, path)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.Strings(out)
	return out, nil
}

// fillSnippets 为诊断补源码行与插入符宽度（渲染格式与前端一致）。
func fillSnippets(root string, ds []Diagnostic) {
	cache := map[string][]string{}
	for i := range ds {
		if ds[i].Snippet != "" {
			continue
		}
		lines, ok := cache[ds[i].File]
		if !ok {
			b, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(ds[i].File)))
			if err == nil {
				lines = strings.Split(string(b), "\n")
			}
			cache[ds[i].File] = lines
		}
		if ds[i].Line >= 1 && ds[i].Line <= len(lines) {
			ds[i].Snippet = strings.TrimRight(lines[ds[i].Line-1], "\r")
			ds[i].Width = 1
		}
	}
}
