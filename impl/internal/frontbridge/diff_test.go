package frontbridge

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/diag"
	"xnull.dev/xnull/internal/xfront"
)

// TestB2Differential 是 Go 测试内的 B2 三层差分器：
//
//	L1 xlex.x token dump ↔ xfront.PrintTokens
//	L2 xparser.x AST dump ↔ xfront.PrintUnitPos（并验证反序列化往返）
//	L3 xparser.x --diags 的 (code,line,col) ↔ Go oracle
//
// 默认 go test 不启用（依赖自举执行器）。设置 XNULL_SELFHOST_BIN（或 XNULL_BIN）
// 或在 interp 支持 xparser 时自动走进程内执行器。
func TestB2Differential(t *testing.T) {
	if os.Getenv("XNULL_B2_DIFF") != "1" {
		t.Skip("设置 XNULL_B2_DIFF=1 启用全语料三层差分")
	}
	root := repoRoot(t)
	xlex, err := parserFile("xlex.x", "XNULL_SELFHOST_XLEX")
	if err != nil {
		t.Skip("找不到 xlex.x：" + err.Error())
	}
	xparse, err := parserFile("xparser.x", "XNULL_SELFHOST_XPARSER")
	if err != nil {
		t.Skip("找不到 xparser.x：" + err.Error())
	}
	// 能力探测：外部二进制未配置且 interp 跑不动自举前端时跳过。
	if _, err := RunSelfhost(xlex, "1\n"); err != nil {
		t.Skip("自举执行器不可用：" + err.Error())
	}

	pass := 0
	failf := func(format string, args ...any) { t.Helper(); t.Errorf(format, args...) }

	// L1：语料 + lex_extra
	l1Files := corpusSources(t)
	if extra, _ := filepath.Glob(filepath.Join(root, "tests", "b2", "lex_extra", "*.x")); len(extra) > 0 {
		l1Files = append(l1Files, extra...)
	}
	for _, path := range l1Files {
		src, err := os.ReadFile(path)
		if err != nil {
			failf("L1 %s: %v", path, err)
			continue
		}
		toks, _ := xfront.Lex(path, string(src))
		want := xfront.PrintTokens(toks)
		got, err := RunSelfhost(xlex, string(src))
		if err != nil {
			failf("L1 %s: %v", path, err)
			continue
		}
		if got != want {
			failf("L1 %s: 首个差异 @%d\n want: %s\n  got: %s", path, firstDiff(want, got), clip(want, firstDiff(want, got)), clip(got, firstDiff(want, got)))
			continue
		}
		pass++
	}

	// L1 负例：xlex --diags ↔ 冻结 .diag
	lexNeg, _ := filepath.Glob(filepath.Join(root, "tests", "b2", "lex_neg", "*.x"))
	for _, path := range lexNeg {
		src, err := os.ReadFile(path)
		if err != nil {
			failf("L1NEG %s: %v", path, err)
			continue
		}
		got, err := RunSelfhost(xlex, "--diags", string(src))
		if err != nil {
			failf("L1NEG %s: %v", path, err)
			continue
		}
		want, _ := os.ReadFile(strings.TrimSuffix(path, ".x") + ".diag")
		if trimDiagHeader(got) != strings.TrimSpace(string(want)) {
			failf("L1NEG %s: got=%q want=%q", path, trimDiagHeader(got), strings.TrimSpace(string(want)))
			continue
		}
		pass++
	}

	// L2：语料 + parser_cases
	l2Files := corpusSources(t)
	if extra, _ := filepath.Glob(filepath.Join(root, "tests", "b2", "parser_cases", "*.x")); len(extra) > 0 {
		l2Files = append(l2Files, extra...)
	}
	for _, path := range l2Files {
		src, err := os.ReadFile(path)
		if err != nil {
			failf("L2 %s: %v", path, err)
			continue
		}
		u, ds := xfront.ParseUnit(path, string(src))
		if len(ds) > 0 {
			failf("L2 %s: oracle 诊断非空：%s", path, ds[0].String())
			continue
		}
		want := xfront.PrintUnitPos(u)
		got, err := RunSelfhost(xparse, string(src))
		if err != nil {
			failf("L2 %s: %v", path, err)
			continue
		}
		if strings.TrimRight(got, "\n") != want {
			got = strings.TrimRight(got, "\n")
			failf("L2 %s: 首个差异 @%d\n want: %s\n  got: %s", path, firstDiff(want, got), clip(want, firstDiff(want, got)), clip(got, firstDiff(want, got)))
			continue
		}
		if !strings.Contains(want, "(depth-limit)") {
			decoded, err := Deserialize(got)
			if err != nil {
				failf("L2 %s: 反序列化失败：%v", path, err)
				continue
			}
			if re := xfront.PrintUnitPos(decoded); re != want {
				failf("L2 %s: 反序列化往返不一致 @%d", path, firstDiff(want, re))
				continue
			}
		}
		pass++
	}

	// L3：parser_neg 诊断序列 ↔ Go oracle
	negFiles, _ := filepath.Glob(filepath.Join(root, "tests", "b2", "parser_neg", "*.x"))
	for _, path := range negFiles {
		src, err := os.ReadFile(path)
		if err != nil {
			failf("L3 %s: %v", path, err)
			continue
		}
		_, ds := xfront.ParseUnit(path, string(src))
		want := oracleDiagSeq(ds)
		got, err := RunSelfhost(xparse, "--diags", string(src))
		if err != nil {
			failf("L3 %s: %v", path, err)
			continue
		}
		if trimDiagHeader(got) != want {
			failf("L3 %s: got=%q want=%q", path, trimDiagHeader(got), want)
			continue
		}
		pass++
	}

	t.Logf("B2 差分 PASS=%d", pass)
}

func trimDiagHeader(s string) string {
	lines := strings.Split(strings.TrimSpace(s), "\n")
	if len(lines) > 0 && strings.HasPrefix(lines[0], "xnast-diags") {
		lines = lines[1:]
	}
	return strings.TrimSpace(strings.Join(lines, "\n"))
}

func oracleDiagSeq(ds []diag.Diagnostic) string {
	var b strings.Builder
	for _, d := range ds {
		if b.Len() > 0 {
			b.WriteByte('\n')
		}
		b.WriteString(fmt.Sprintf("%s %d %d", d.Code, d.Line, d.Col))
	}
	return b.String()
}

func firstDiff(a, b string) int {
	i := 0
	for i < len(a) && i < len(b) && a[i] == b[i] {
		i++
	}
	return i
}
