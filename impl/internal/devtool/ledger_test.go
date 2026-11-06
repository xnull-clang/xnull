package devtool

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// goldenLedgerRows 是迁移基线固化的台账行数（101）与 PASS 数（10）。
const (
	goldenLedgerRows = 101
	goldenLedgerPass = 10
)

func newLedgerFixture(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "impl", "docs", "conformance"), 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(root, indexName), []byte(testIndex))
	stems := []string{
		"第1部分-基础语法", "第2部分-对象编程", "第3部分-内存管理", "第4部分-错误处理",
		"第5部分-运行时任务与并发", "第6部分-标准库XDK", "第7部分-FFI", "第8部分-工程配置",
	}
	for i, stem := range stems {
		body := "# " + stem + "\n\n"
		if i == 0 {
			body += "| LEX-01 | 词法 | 关键字与标识符<br>含转义 |\n" +
				"| ZZ-02 | 未知前缀 | 落默认里程碑 |\n"
		}
		if i == 1 {
			// 与 S1 重复的编号：应按首次出现去重。
			body += "| LEX-01 | 词法 | 重复项 |\n"
			body += "| EXPR-03 | 表达式 | 优先级 |\n"
		}
		writeFile(t, filepath.Join(root, "XNull解决方案-"+stem+"-v1.0.0.md"), []byte(body))
	}
	writeFile(t, filepath.Join(root, "impl", "docs", "conformance", "status.tsv"),
		[]byte("LEX-01\ttests/lex.xt\tPASS\nEXPR-03\ttests/expr.xt\t部分\n"))
	return root
}

func TestBuildLedgerRowsAndStats(t *testing.T) {
	root := newLedgerFixture(t)
	data, err := BuildLedger(root)
	if err != nil {
		t.Fatal(err)
	}
	got := string(data)

	if !strings.Contains(got, "# XNull 一致性用例台账") {
		t.Fatalf("缺标题：\n%s", got)
	}
	if !strings.Contains(got, "> 由 `xnull dev ledger` 自动生成") {
		t.Fatalf("头部生成器名称未切换：\n%s", got)
	}
	if !strings.Contains(got, "| 总计 | 3 条（PASS 1） |") {
		t.Fatalf("统计行不符（应去重为 3 条）：\n%s", got)
	}
	if !strings.Contains(got, "| LEX-01 | S1 | 词法；关键字与标识符；含转义 | M1 | tests/lex.xt | PASS |") {
		t.Fatalf("LEX-01 行不符：\n%s", got)
	}
	if strings.Contains(got, "重复项") {
		t.Fatalf("重复编号未去重：\n%s", got)
	}
	if !strings.Contains(got, "| ZZ-02 | S1 | 未知前缀；落默认里程碑 | M3 | — | 未实现 |") {
		t.Fatalf("未知前缀未落 M3：\n%s", got)
	}
	if !strings.HasSuffix(got, "|\n") {
		t.Fatalf("台账结尾应为单个换行：%q", got[len(got)-4:])
	}
}

// 仓库级集成：固化迁移基线的 golden 规模，防止抽取规则回归。
func TestBuildLedgerRepoGoldenScale(t *testing.T) {
	root, err := filepath.Abs(filepath.Join("..", "..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	if !fileExists(filepath.Join(root, indexName)) {
		t.Skip("仓库布局不可用，跳过集成用例")
	}
	data, err := BuildLedger(root)
	if err != nil {
		t.Fatal(err)
	}
	rows := 0
	pass := 0
	for _, line := range strings.Split(string(data), "\n") {
		if !ledgerRowRe.MatchString(strings.TrimSpace(line)) {
			continue
		}
		rows++
		if strings.HasSuffix(line, " PASS |") {
			pass++
		}
	}
	if rows != goldenLedgerRows || pass != goldenLedgerPass {
		t.Fatalf("台账规模偏离 golden：行数 %d（期望 %d），PASS %d（期望 %d）",
			rows, goldenLedgerRows, pass, goldenLedgerPass)
	}
}
