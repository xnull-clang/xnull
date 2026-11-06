// Package diag 渲染诊断信息（S9 附录 C.4）。
package diag

import (
	"fmt"
	"strconv"
	"strings"
)

// Diagnostic 是一条带位置与稳定错误码的诊断。
type Diagnostic struct {
	File    string
	Line    int
	Col     int
	Code    string // 形如 XPD-204 / CLI-002
	Message string
	Snippet string // 出错行的原文（不含行号）
	Width   int    // 插入符覆盖宽度；0 表示 1
	Hint    string // 追加说明（可用键、修复建议等）
}

// String 渲染为固定格式：file:line:col: error[CODE]: message + 源码行 + 插入符。
func (d Diagnostic) String() string {
	var b strings.Builder
	fmt.Fprintf(&b, "%s:%d:%d: error[%s]: %s", d.File, d.Line, d.Col, d.Code, d.Message)
	if d.Snippet == "" {
		if d.Hint != "" {
			b.WriteString("\n  " + d.Hint)
		}
		return b.String()
	}
	num := strconv.Itoa(d.Line)
	gutter := strings.Repeat(" ", len(num))
	fmt.Fprintf(&b, "\n %s | %s", num, d.Snippet)
	width := d.Width
	if width < 1 {
		width = 1
	}
	pad := d.Col - 1
	if pad < 0 {
		pad = 0
	}
	fmt.Fprintf(&b, "\n %s | %s%s", gutter, strings.Repeat(" ", pad), strings.Repeat("^", width))
	if d.Hint != "" {
		b.WriteString(" " + d.Hint)
	}
	return b.String()
}
