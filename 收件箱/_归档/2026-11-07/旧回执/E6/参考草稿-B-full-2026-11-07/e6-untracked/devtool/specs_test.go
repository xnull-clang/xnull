package devtool

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func writeFixture(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

// validSpecFixture 构造一个满足五项检查的最小仓库。
func validSpecFixture(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	writeFixture(t, filepath.Join(root, "impl", ".keep"), "")
	writeFixture(t, filepath.Join(root, indexName), "# 规范索引\n")

	part := "XNull解决方案-第1部分-基础语法-v1.0.0.md"
	writeFixture(t, filepath.Join(root, part),
		"# 基础语法\n\n| 项 | 值 |\n| --- | --- |\n| 文档版本 | 1.0.0 |\n| 规范状态 | 正式 |\n\n## 1 总则\n")
	writeFixture(t, filepath.Join(root, ledgerName), "# 台账\n")
	writeFixture(t, filepath.Join(root, "en", "S1-Basic-v1.0.0.md"), "# Basic\n")
	writeFixture(t, filepath.Join(root, "en", "Conformance-Ledger-v1.0.0.md"), "# Ledger\n")

	old := time.Now().Add(-2 * time.Hour)
	for _, name := range []string{part, ledgerName} {
		if err := os.Chtimes(filepath.Join(root, name), old, old); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func TestCheckSpecsPassesValidFixture(t *testing.T) {
	root := validSpecFixture(t)
	var out bytes.Buffer
	code, err := CheckSpecs(root, &out)
	if err != nil {
		t.Fatal(err)
	}
	if code != 0 {
		t.Fatalf("exit = %d, want 0\n%s", code, out.String())
	}
	if !strings.Contains(out.String(), "全部通过") {
		t.Fatalf("缺少通过标记：%s", out.String())
	}
}

func TestCheckSpecsDetectsDefects(t *testing.T) {
	cases := []struct {
		name    string
		mutate  func(t *testing.T, root string)
		wantMsg string
	}{
		{
			name: "待定措辞",
			mutate: func(t *testing.T, root string) {
				part := filepath.Join(root, "XNull解决方案-第1部分-基础语法-v1.0.0.md")
				f, err := os.OpenFile(part, os.O_APPEND|os.O_WRONLY, 0o644)
				if err != nil {
					t.Fatal(err)
				}
				defer f.Close()
				f.WriteString("\n待定项\n")
			},
			wantMsg: "待定内容扫描",
		},
		{
			name: "悬空引用",
			mutate: func(t *testing.T, root string) {
				part := filepath.Join(root, "XNull解决方案-第1部分-基础语法-v1.0.0.md")
				f, err := os.OpenFile(part, os.O_APPEND|os.O_WRONLY, 0o644)
				if err != nil {
					t.Fatal(err)
				}
				defer f.Close()
				f.WriteString("\n见 §9.9\n")
			},
			wantMsg: "§ 引用悬空",
		},
		{
			name: "头部版本不一致",
			mutate: func(t *testing.T, root string) {
				part := filepath.Join(root, "XNull解决方案-第1部分-基础语法-v1.0.0.md")
				s, err := os.ReadFile(part)
				if err != nil {
					t.Fatal(err)
				}
				s = bytes.Replace(s, []byte("| 文档版本 | 1.0.0 |"), []byte("| 文档版本 | 2.0.0 |"), 1)
				if err := os.WriteFile(part, s, 0o644); err != nil {
					t.Fatal(err)
				}
			},
			wantMsg: "头部三方一致",
		},
		{
			name: "根目录二进制文档",
			mutate: func(t *testing.T, root string) {
				writeFixture(t, filepath.Join(root, "spec.pdf"), "x")
			},
			wantMsg: "二进制文档拦截",
		},
		{
			name: "EN 快照滞后",
			mutate: func(t *testing.T, root string) {
				part := filepath.Join(root, "XNull解决方案-第1部分-基础语法-v1.0.0.md")
				now := time.Now()
				if err := os.Chtimes(part, now, now); err != nil {
					t.Fatal(err)
				}
			},
			wantMsg: "EN 快照同步",
		},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			root := validSpecFixture(t)
			c.mutate(t, root)
			var out bytes.Buffer
			code, err := CheckSpecs(root, &out)
			if err != nil {
				t.Fatal(err)
			}
			if code != 1 {
				t.Fatalf("exit = %d, want 1\n%s", code, out.String())
			}
			if !strings.Contains(out.String(), c.wantMsg) {
				t.Fatalf("输出缺少 %q：%s", c.wantMsg, out.String())
			}
		})
	}
}

func TestCheckSpecsRejectsMissingIndex(t *testing.T) {
	root := t.TempDir()
	if _, err := CheckSpecs(root, &bytes.Buffer{}); err == nil {
		t.Fatal("缺少索引时应返回错误")
	}
}
