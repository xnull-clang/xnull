package devtool

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
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
