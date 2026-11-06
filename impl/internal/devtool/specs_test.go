package devtool

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

const testIndex = "# 索引\n\n无待定项。\n"

func writePart(t *testing.T, dir, name, body string) {
	t.Helper()
	writeFile(t, filepath.Join(dir, name), []byte(body))
}

func newSpecFixture(t *testing.T, withEn bool) string {
	t.Helper()
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "impl"), 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(root, indexName), []byte(testIndex))
	writePart(t, root, "XNull解决方案-第1部分-测试-v1.0.0.md",
		"# 第1部分\n\n| 文档版本 | 1.0.0 |\n| 规范状态 | 正式 |\n\n## 1 概述\n\n见 §1。\n")
	writeFile(t, filepath.Join(root, ledgerName), []byte("# 台账\n"))
	if withEn {
		en := filepath.Join(root, "en")
		writeFile(t, filepath.Join(en, "S1-test-v1.0.0.md"), []byte("# Part 1\n"))
		writeFile(t, filepath.Join(en, "Conformance-Ledger-v1.0.0.md"), []byte("# Ledger\n"))
		// 确保母本不晚于英译：先写母本，再触及英译。
		touch(t, filepath.Join(en, "S1-test-v1.0.0.md"))
		touch(t, filepath.Join(en, "Conformance-Ledger-v1.0.0.md"))
	}
	return root
}

func setMtime(t *testing.T, path string, ts time.Time) {
	t.Helper()
	if err := os.Chtimes(path, ts, ts); err != nil {
		t.Fatal(err)
	}
}

func touch(t *testing.T, path string) {
	t.Helper()
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(path, info.ModTime(), info.ModTime().Add(1e9)); err != nil {
		t.Fatal(err)
	}
}

func runCheck(t *testing.T, root string) (int, string) {
	t.Helper()
	var out bytes.Buffer
	code, err := CheckSpecs(root, &out)
	if err != nil {
		t.Fatalf("CheckSpecs 返回错误：%v", err)
	}
	return code, out.String()
}

func TestCheckSpecsPassesCleanLayout(t *testing.T) {
	code, out := runCheck(t, newSpecFixture(t, true))
	if code != 0 {
		t.Fatalf("干净布局应通过，实际退出码 %d：\n%s", code, out)
	}
	if !strings.Contains(out, "全部通过：零待定、引用零悬空、头部一致、根目录纯 Markdown、EN 快照同步") {
		t.Fatalf("缺少通过结论：\n%s", out)
	}
	if !strings.Contains(out, "EN 快照同步（2 份对照）") {
		t.Fatalf("EN 对照计数不符：\n%s", out)
	}
}

func TestCheckSpecsMissingEn(t *testing.T) {
	code, out := runCheck(t, newSpecFixture(t, false))
	if code != 1 {
		t.Fatalf("缺 EN 应返回 1，实际 %d", code)
	}
	if !strings.Contains(out, "  - en 目录不存在") || !strings.Contains(out, "共 1 处缺陷") {
		t.Fatalf("缺 EN 诊断不符：\n%s", out)
	}
}

func TestCheckSpecsPendingAndDanglingRef(t *testing.T) {
	root := newSpecFixture(t, true)
	writePart(t, root, "XNull解决方案-第2部分-测试-v1.0.0.md",
		"# 第2部分\n\n| 文档版本 | 1.0.0 |\n| 规范状态 | 正式 |\n\n## 1 概述\n\n此项待确认，引用 §9.9。\n")
	code, out := runCheck(t, root)
	if code != 1 {
		t.Fatalf("应返回 1，实际 %d", code)
	}
	if !strings.Contains(out, "此项待确认") {
		t.Fatalf("未命中待定措辞：\n%s", out)
	}
	if !strings.Contains(out, "§9.9 未命中任何章节") {
		t.Fatalf("未命中悬空引用：\n%s", out)
	}
}

func TestCheckSpecsHeaderMismatch(t *testing.T) {
	root := newSpecFixture(t, true)
	writePart(t, root, "XNull解决方案-第1部分-测试-v1.0.0.md",
		"# 第1部分\n\n| 文档版本 | 1.0.1 |\n| 规范状态 | 正式 |\n\n## 1 概述\n")
	code, out := runCheck(t, root)
	if code != 1 || !strings.Contains(out, "文件名版本 1.0.0 ≠ 头部 1.0.1") {
		t.Fatalf("头部不一致未被发现（code=%d）：\n%s", code, out)
	}
}

// EN 滞后判定不得依赖 mtime。
func TestCheckSpecsMtimeShuffleDeterministic(t *testing.T) {
	root := newSpecFixture(t, true)
	cn := filepath.Join(root, "XNull解决方案-第1部分-测试-v1.0.0.md")
	en := filepath.Join(root, "en", "S1-test-v1.0.0.md")
	ledCn := filepath.Join(root, ledgerName)
	ledEn := filepath.Join(root, "en", "Conformance-Ledger-v1.0.0.md")

	base := time.Date(2026, 11, 7, 0, 0, 0, 0, time.UTC)
	var outs []string
	for i := 0; i < 3; i++ {
		// 每次打乱中英两侧时间戳，且方向不同（母本更旧/更新/相同）。
		offset := time.Duration((i-1)*3600) * time.Second
		setMtime(t, cn, base.Add(offset))
		setMtime(t, ledCn, base.Add(offset))
		setMtime(t, en, base.Add(-offset))
		setMtime(t, ledEn, base.Add(-offset))
		code, out := runCheck(t, root)
		if code != 0 {
			t.Fatalf("第 %d 次打乱 mtime 后应通过，实际 %d：\n%s", i+1, code, out)
		}
		outs = append(outs, out)
	}
	for i := 1; i < len(outs); i++ {
		if outs[i] != outs[0] {
			t.Fatalf("第 %d 次输出与首次不一致：\n--- first ---\n%s\n--- now ---\n%s", i+1, outs[0], outs[i])
		}
	}
}

func writeEnSource(t *testing.T, root, cnName, hash string) {
	t.Helper()
	writeFile(t, filepath.Join(root, "impl", "docs", "conformance", "en-source.sha256"),
		[]byte("# 母本文件\t母本内容 SHA-256\n"+cnName+"\t"+hash+"\n"))
}

func TestCheckSpecsDigestStaleDetected(t *testing.T) {
	root := newSpecFixture(t, true)
	cn := filepath.Join(root, "XNull解决方案-第1部分-测试-v1.0.0.md")
	src, err := os.ReadFile(cn)
	if err != nil {
		t.Fatal(err)
	}
	writeEnSource(t, root, "XNull解决方案-第1部分-测试-v1.0.0.md", contentSHA256(src))

	if code, out := runCheck(t, root); code != 0 {
		t.Fatalf("哈希一致时应通过，实际 %d：\n%s", code, out)
	}

	// 真实内容变更（母本文本改变）→ 清单哈希不再匹配，必须报滞后。
	writePart(t, root, "XNull解决方案-第1部分-测试-v1.0.0.md",
		"# 第1部分\n\n| 文档版本 | 1.0.0 |\n| 规范状态 | 正式 |\n\n## 1 概述\n\n新增一段正文。\n")
	code, out := runCheck(t, root)
	if code != 1 || !strings.Contains(out, "内容哈希不符——母本 XNull解决方案-第1部分-测试-v1.0.0.md 变更后英译未同步重译") {
		t.Fatalf("内容变更未被判滞后（code=%d）：\n%s", code, out)
	}
}

func TestCheckSpecsDigestMismatchFailsRegardlessOfMtime(t *testing.T) {
	root := newSpecFixture(t, true)
	writeEnSource(t, root, "XNull解决方案-第1部分-测试-v1.0.0.md", strings.Repeat("0", 64))
	// 让英译 mtime 远新于母本：旧实现会放过，新实现必须红。
	setMtime(t, filepath.Join(root, "XNull解决方案-第1部分-测试-v1.0.0.md"),
		time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC))
	setMtime(t, filepath.Join(root, "en", "S1-test-v1.0.0.md"),
		time.Date(2030, 1, 1, 0, 0, 0, 0, time.UTC))
	code, out := runCheck(t, root)
	if code != 1 || !strings.Contains(out, "内容哈希不符") {
		t.Fatalf("哈希不符应报滞后（code=%d）：\n%s", code, out)
	}
}
