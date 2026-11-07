package xpd

import (
	"strings"

	"xnull.dev/xnull/internal/diag"
)

// S8-10：XPD 规范化（清单/锁/元数据共用文法）。
//
// 只做行级规范化：缩进（2 空格/层）、行尾空白、BOM/CRLF 归一；保留注释、
// 空行与条目顺序。语法错误先由 Parse 报告，格式化不吞错。

// FormatSource 返回规范化文本；诊断非空表示语法错误，文本无意义。
func FormatSource(file, src string) (string, []diag.Diagnostic) {
	_, ds := Parse(file, src)
	if len(ds) > 0 {
		return "", ds
	}
	src = strings.ReplaceAll(src, "\r\n", "\n")
	src = strings.ReplaceAll(src, "\r", "\n")
	src = strings.TrimPrefix(src, "\uFEFF")
	lines := strings.Split(src, "\n")
	var out []string
	depth := 0
	for _, raw := range lines {
		trimmed := strings.TrimSpace(raw)
		if trimmed == "" {
			out = append(out, "")
			continue
		}
		lineDepth := depth
		if strings.HasPrefix(trimmed, "}") && lineDepth > 0 {
			lineDepth--
		}
		out = append(out, strings.Repeat("  ", lineDepth)+trimmed)
		depth += xpdBraceDelta(trimmed)
		if depth < 0 {
			depth = 0
		}
	}
	// 去掉尾部多余空行，保证单末尾换行。
	for len(out) > 0 && out[len(out)-1] == "" {
		out = out[:len(out)-1]
	}
	if len(out) == 0 {
		return "", nil
	}
	return strings.Join(out, "\n") + "\n", nil
}

// xpdBraceDelta 统计一层内未处于字符串/注释中的 `{`/`}` 差值。
func xpdBraceDelta(s string) int {
	delta := 0
	inStr := false
	escaped := false
	for i := 0; i < len(s); i++ {
		c := s[i]
		if inStr {
			if escaped {
				escaped = false
				continue
			}
			if c == '\\' {
				escaped = true
				continue
			}
			if c == '"' {
				inStr = false
			}
			continue
		}
		switch c {
		case '"':
			inStr = true
		case '#':
			return delta
		case '{':
			delta++
		case '}':
			delta--
		}
	}
	return delta
}
