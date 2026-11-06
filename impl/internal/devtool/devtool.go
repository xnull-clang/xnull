// Package devtool 汇集仓库维护工具：规范守门、台账生成、资源表生成。
//
// 三个工具原由 impl/tools 下的 Python 脚本承担（迁移前）；本包是等价的 Go 实现，
// 目标是让开发工具链只依赖 Go 与 C。输出必须与 Python 参考实现逐字节/逐行一致，
// 差异仅允许台账头部的一行生成器名称。
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
	SpecDir string // 规范母本目录（主仓布局为 Root，公开布局为 Root/spec）
}

// findLayout 自 start 向上查找规范索引，返回仓库根与母本目录。
//
// 双布局：索引可能在仓库根（主仓），也可能在 Root/spec（公开布局）。
// 优先返回同时存在 impl/ 的候选，避免从 spec/ 内部启动时把 spec 当成仓库根。
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

// enDir 返回 EN 快照目录：优先 SpecDir/en；兼容嵌套布局回退。
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

// relDisplay 返回相对 root 的展示路径；同一目录显示 "."（对齐 Python 的 relpath+or "."）。
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

// splitLines 按 Python str.splitlines 的常用语义切行（CRLF / CR / LF）。
func splitLines(s string) []string {
	s = strings.ReplaceAll(s, "\r\n", "\n")
	s = strings.ReplaceAll(s, "\r", "\n")
	return strings.Split(s, "\n")
}

// truncateRunes 按字符截断，避免切断 UTF-8（对齐 Python 切片 [:80]）。
func truncateRunes(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n])
}
