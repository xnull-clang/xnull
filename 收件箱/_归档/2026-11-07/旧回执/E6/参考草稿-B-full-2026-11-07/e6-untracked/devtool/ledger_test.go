package devtool

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func ledgerFixture(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	writeFixture(t, filepath.Join(root, indexName), "# 索引\n")
	writeFixture(t, filepath.Join(root, "impl", "docs", "conformance", "status.tsv"),
		"# 编号\t用例文件\t状态\nLEX-01\tinternal/xfront/lexer_test.go\tPASS\nTYPE-01\tinternal/sema/ty_test.go\t部分\n")

	for _, d := range ledgerDocs {
		content := "# " + d.id + "\n"
		switch d.id {
		case "S1":
			content += "\n| LEX-01 | 词法要点 | 说明 |\n| LEX-01 | 词法重复行 | 应被去重 |\n"
		case "S2":
			content += "\n| TYPE-01 | 类型要点<br>第二行 |\n"
		}
		writeFixture(t, filepath.Join(root, "XNull解决方案-"+d.stem+"-v1.0.0.md"), content)
	}
	return root
}

func TestGenerateLedger(t *testing.T) {
	root := ledgerFixture(t)
	var out bytes.Buffer
	if err := GenerateLedger(root, &out); err != nil {
		t.Fatal(err)
	}

	data, err := os.ReadFile(filepath.Join(root, ledgerName))
	if err != nil {
		t.Fatal(err)
	}
	got := string(data)

	for _, want := range []string{
		"| 总计 | 2 条（PASS 1） |",
		"| LEX-01 | S1 | 词法要点；说明 | M1 | internal/xfront/lexer_test.go | PASS |",
		"| TYPE-01 | S2 | 类型要点；第二行 | M1 | internal/sema/ty_test.go | 部分 |",
		"由 `xnull dev ledger` 自动生成",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("台账缺少 %q：\n%s", want, got)
		}
	}
	if strings.Count(got, "| LEX-01 |") != 1 {
		t.Fatalf("LEX-01 未去重：\n%s", got)
	}
	if !strings.Contains(out.String(), "已生成") {
		t.Fatalf("缺少生成摘要：%s", out.String())
	}
}

func TestGenerateLedgerMissingDoc(t *testing.T) {
	root := ledgerFixture(t)
	if err := os.Remove(filepath.Join(root, "XNull解决方案-第8部分-工程配置-v1.0.0.md")); err != nil {
		t.Fatal(err)
	}
	if err := GenerateLedger(root, &bytes.Buffer{}); err == nil {
		t.Fatal("缺少母本时应报错，不能静默生成残缺台账")
	}
}
