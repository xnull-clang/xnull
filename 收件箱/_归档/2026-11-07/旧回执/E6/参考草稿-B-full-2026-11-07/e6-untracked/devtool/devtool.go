// Package devtool 汇集仓库维护工具：规范守门、台账生成、资源表生成。
//
// 这些工具原先由 impl/tools/*.py 承担；按用户裁决统一改为 Go，
// 使开发工具链只需要 Go 与 C，不再依赖 Python。
package devtool

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const (
	indexName  = "XNull规范索引-v1.0.0.md"
	ledgerName = "XNull一致性用例台账-v1.0.0.md"
)

// layout 是一次仓库布局探测结果。
type layout struct {
	Root    string // 仓库根
	SpecDir string // 规范母本目录（工作区布局为 Root，公开布局为 Root/spec）
}

// findLayout 从 start 向上查找规范索引，返回仓库根与母本目录。
//
// 双布局自适应：
//   - 工作区布局：索引在仓库根，母本目录 = Root；
//   - 公开仓库布局：索引在 Root/spec，母本目录 = Root/spec。
//
// 优先选择同时存在 impl/ 的候选，避免从 Root/spec 启动时把 spec 误当仓库根。
func findLayout(start string) (layout, error) {
	abs, err := filepath.Abs(start)
	if err != nil {
		return layout{}, err
	}

	var fallback *layout
	for dir := abs; ; dir = filepath.Dir(dir) {
		for _, cand := range []layout{
			{Root: dir, SpecDir: dir},
			{Root: dir, SpecDir: filepath.Join(dir, "spec")},
		} {
			if !fileExists(filepath.Join(cand.SpecDir, indexName)) {
				continue
			}
			if fallback == nil {
				c := cand
				fallback = &c
			}
			if dirExists(filepath.Join(cand.Root, "impl")) {
				return cand, nil
			}
		}
		if parent := filepath.Dir(dir); parent == dir {
			break
		}
	}

	if fallback != nil {
		return *fallback, nil
	}
	return layout{}, fmt.Errorf("找不到 %s（从 %s 向上）", indexName, abs)
}

// enDir 返回 EN 快照目录，兼容两种布局。
func (l layout) enDir() string {
	primary := filepath.Join(l.SpecDir, "en")
	if dirExists(primary) {
		return primary
	}
	secondary := filepath.Join(l.Root, "xnull", "spec", "en")
	if dirExists(secondary) {
		return secondary
	}
	return primary
}

func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}

func dirExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}

// relDisplay 返回相对 root 的展示路径；同一目录显示 "."。
func relDisplay(path, root string) string {
	rel, err := filepath.Rel(root, path)
	if err != nil || rel == "" {
		return "."
	}
	return filepath.ToSlash(rel)
}

func readText(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

// splitLines 按 Python str.splitlines 的常用语义切行（兼容 CRLF 与单独 CR）。
func splitLines(s string) []string {
	s = strings.ReplaceAll(s, "\r\n", "\n")
	s = strings.ReplaceAll(s, "\r", "\n")
	return strings.Split(s, "\n")
}

// truncateRunes 按字符（而不是字节）截断，避免切断 UTF-8。
func truncateRunes(s string, n int) string {
	runes := []rune(s)
	if len(runes) <= n {
		return s
	}
	return string(runes[:n])
}
