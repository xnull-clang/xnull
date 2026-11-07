package devtool

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func sh(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command(args[0], args[1:]...)
	cmd.Dir = dir
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("%v: %v\n%s", args, err, out)
	}
}

func newBoardRepo(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	sh(t, root, "git", "init", "-q")
	sh(t, root, "git", "config", "user.email", "e6@test")
	sh(t, root, "git", "config", "user.name", "E6")
	sh(t, root, "git", "config", "commit.gpgsign", "false")

	writeFile(t, filepath.Join(root, "impl", "docs", "conformance", "status.tsv"),
		[]byte("# 编号\t用例文件\t状态\nA-01\ta_test.go\tPASS\nA-02\ta_test.go\tPASS\nA-03\ta_test.go\t部分\n"))
	writeFile(t, filepath.Join(root, "evidence", "CARD-A", "out.txt"), []byte("x"))
	sh(t, root, "git", "add", ".")
	sh(t, root, "git", "commit", "-q", "-m", "first")

	writeFile(t, filepath.Join(root, "impl", "docs", "conformance", "status.tsv"),
		[]byte("# 编号\t用例文件\t状态\nA-01\ta_test.go\tPASS\nA-02\ta_test.go\tPASS\nA-03\ta_test.go\tPASS\n"))
	sh(t, root, "git", "add", ".")
	sh(t, root, "git", "commit", "-q", "-m", "flip one anchor")
	return root
}

func TestGenerateBoardSSOT(t *testing.T) {
	root := newBoardRepo(t)
	var buf bytes.Buffer
	opts := BoardOptions{Since: 24 * 60 * 60 * 1e9, RunTests: false}
	if err := GenerateBoard(root, filepath.Join(root, "impl"), opts, &buf); err != nil {
		t.Fatalf("GenerateBoard：%v", err)
	}
	out := buf.String()
	for _, want := range []string{
		"SSOT 看板（脚本生成，手改即作废）",
		"| 1 | 窗口内 commit 数 | 2 |",
		"| 2 | 锚点翻转（PASS） | 3（起点 2，Δ+1） |",
		"未运行（--no-test）",
		"| CARD-A | 1 |",
		"生产线进度",
		"手工编辑无效",
	} {
		if !strings.Contains(out, want) {
			t.Fatalf("看板缺少 %q：\n%s", want, out)
		}
	}
}

func TestLineOf(t *testing.T) {
	cases := []struct {
		files []string
		want  string
	}{
		{[]string{"impl/internal/sema/x.go"}, "前端线"},
		{[]string{"impl/internal/xnfmt/x.go"}, "自举线"},
		{[]string{"impl/cmd/xnfmt/main.go"}, "自举线"},
		{[]string{"impl/runtime/rt.c"}, "运行时线"},
		{[]string{"bindings/xdk/sys.xfb"}, "运行时线"},
		{[]string{"evidence/B0-02/x"}, "QA 线"},
		{[]string{"docs/x.md"}, "其它"},
	}
	for _, c := range cases {
		if got := lineOf(c.files); got != c.want {
			t.Fatalf("lineOf(%v)=%s，期望 %s", c.files, got, c.want)
		}
	}
}

func TestCountPass(t *testing.T) {
	tsv := "# h\nA\tf\tPASS\nB\tf\t部分\nC\tf\tPASS\n"
	if n := countPass(tsv); n != 2 {
		t.Fatalf("countPass=%d，期望 2", n)
	}
}

func TestGenerateBoardNotGit(t *testing.T) {
	root := t.TempDir()
	if err := GenerateBoard(root, root, BoardOptions{}, &bytes.Buffer{}); err == nil {
		t.Fatal("非 git 目录应报错")
	}
	_ = os.RemoveAll(root)
}

// ADR-003：ADR 生效后产生证据的卡片缺接力棒 → 看板告警；接力棒缺字段同样告警。
func TestBoardHandoffWarnings(t *testing.T) {
	root := newBoardRepo(t)
	writeFile(t, filepath.Join(root, "ADR", "ADR-003-断链恢复协议.md"), []byte("# adr\n"))
	old := time.Now().Add(-48 * time.Hour)
	if err := os.Chtimes(filepath.Join(root, "ADR", "ADR-003-断链恢复协议.md"), old, old); err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(root, "evidence", "NEW-CARD", "out.txt"), []byte("x"))
	writeFile(t, filepath.Join(root, "handoff", "NEW-CARD.md"), []byte(
		"# 接力棒：NEW-CARD\n\n- **卡片ID**：NEW-CARD\n- **输入**：x\n- **输出文件**：y\n- **commit**：abc\n- **验证命令**：true\n- **已知缺口/风险**：无\n- **下一步**：集成\n"))
	writeFile(t, filepath.Join(root, "handoff", "BROKEN.md"), []byte("# 接力棒：BROKEN\n\n- **卡片ID**：BROKEN\n- **输入**：\n"))
	sh(t, root, "git", "add", ".")
	sh(t, root, "git", "commit", "-q", "-m", "handoff fixture")

	var buf bytes.Buffer
	if err := GenerateBoard(root, filepath.Join(root, "impl"), BoardOptions{Since: 24 * time.Hour, RunTests: false}, &buf); err != nil {
		t.Fatal(err)
	}
	out := buf.String()
	if !strings.Contains(out, "接力棒（handoff/）") {
		t.Fatalf("缺少接力棒区：\n%s", out)
	}
	if strings.Contains(out, "接力棒缺失：NEW-CARD") {
		t.Fatalf("NEW-CARD 已有接力棒，不应报缺失：\n%s", out)
	}
	if !strings.Contains(out, "接力棒缺字段：BROKEN") {
		t.Fatalf("BROKEN 缺字段未告警：\n%s", out)
	}
	if !strings.Contains(out, "缺 last-green") {
		t.Fatalf("缺 last-green 未告警：\n%s", out)
	}
}

func TestRecordAndLoadLastGreen(t *testing.T) {
	root := t.TempDir()
	now := time.Date(2026, 11, 7, 14, 30, 0, 0, time.UTC)
	if _, err := recordLastGreen(root, "abc1234", root, now); err != nil {
		t.Fatal(err)
	}
	got := loadLastGreen(filepath.Join(root, "handoff", "last-green.tsv"))
	for _, ln := range boardLines {
		if e, ok := got[ln.name]; !ok || e.sha != "abc1234" {
			t.Fatalf("%s 的 last-green 未记录（非 git 仓库时退回 HEAD）：%+v", ln.name, got)
		}
	}
}

// ADR-003：每条生产线的 last-green 必须独立（各自最近提交），支撑线记全量绿点。
func TestRecordLastGreenPerLine(t *testing.T) {
	root := newBoardRepo(t)
	// first 提交含 sema/runtime，second 含 codegen → 三线应得出不同 sha。
	writeFile(t, filepath.Join(root, "impl", "internal", "sema", "a.go"), []byte("package sema\n"))
	writeFile(t, filepath.Join(root, "impl", "runtime", "rt.c"), []byte("/* rt */\n"))
	sh(t, root, "git", "add", ".")
	sh(t, root, "git", "commit", "-q", "-m", "frontend+runtime")
	writeFile(t, filepath.Join(root, "impl", "internal", "codegen", "a.go"), []byte("package codegen\n"))
	sh(t, root, "git", "add", ".")
	sh(t, root, "git", "commit", "-q", "-m", "bootstrap")
	head, err := gitLine(root, "rev-parse", "--short", "HEAD")
	if err != nil {
		t.Fatal(err)
	}
	orig := runLineTestsFn
	runLineTestsFn = func(string, string, string) (bool, string) { return true, "" }
	defer func() { runLineTestsFn = orig }()
	if _, err := recordLastGreen(root, head, filepath.Join(root, "impl"), time.Now()); err != nil {
		t.Fatal(err)
	}
	got := loadLastGreen(filepath.Join(root, "handoff", "last-green.tsv"))
	if got["自举线"].sha == got["前端线"].sha || got["自举线"].sha == got["运行时线"].sha {
		t.Fatalf("自举线应与其它生产线的 last-green 不同：%+v", got)
	}
	if got["QA 线"].sha == "" || got["发布线"].sha == "" {
		t.Fatalf("支撑线也必须有 last-green：%+v", got)
	}
}

func TestCanonicalCardAndGates(t *testing.T) {
	cases := map[string]string{
		"M6-B0-05-sema":  "B0-05",
		"M6-B0-01":       "B0-01",
		"B0-07b":         "B0-07b",
		"B1-03":          "B1-03",
		"M1-ENTRY-01-qa": "M1-ENTRY-01",
	}
	for in, want := range cases {
		if got := canonicalCard(in); got != want {
			t.Fatalf("canonicalCard(%q)=%q，期望 %q", in, got, want)
		}
	}
	ev := []evidenceInfo{{name: "M6-B0-01"}, {name: "B0-02"}, {name: "M6-B0-05-sema"}, {name: "M6-B1-03"}}
	root := t.TempDir()
	writeFile(t, filepath.Join(root, "handoff", "B0-03.md"), []byte("# x\n"))
	got := gateProgress(ev, root)
	if !strings.Contains(got[0], "B0 6 卡（有证据 4）") || !strings.Contains(got[0], "B1 3 卡（有证据 1）") {
		t.Fatalf("门卡数不符：%v", got)
	}
}
