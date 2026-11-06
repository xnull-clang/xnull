package devtool

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// 迁移前 gen_resources.py（Python 3.12.14 / LC_ALL=C）输出的 sha256，作为固定对照。
// 用哈希而不是内嵌文本：既保证逐字节一致，也避免把旧生成器署名文本复制到测试里。
const (
	goldenTwoFilesSHA256 = "9f934bd261bdf8a24499f1d2234cb606f611fd2a3803838251dc0fa53994ab09"
	goldenEmptySHA256    = "ca00666cdbebd979f91d9243a699cfb6eb5a38da748970def0270c2f1698d5ce"
)

func sha256Hex(s string) string {
	sum := sha256.Sum256([]byte(s))
	return hex.EncodeToString(sum[:])
}

func writeFile(t *testing.T, path string, data []byte) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, data, 0o644); err != nil {
		t.Fatal(err)
	}
}

func generate(t *testing.T, src string) string {
	t.Helper()
	out := filepath.Join(t.TempDir(), "res_table.c")
	if err := GenerateResources(src, out); err != nil {
		t.Fatalf("生成失败：%v", err)
	}
	data, err := os.ReadFile(out)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func TestGenerateResourcesMatchesPythonGolden(t *testing.T) {
	src := t.TempDir()
	// 故意按乱序写入，验证按名排序；c.bin 20 字节用来验证 16 字节分行。
	b := make([]byte, 20)
	for i := range b {
		b[i] = byte(i)
	}
	writeFile(t, filepath.Join(src, "c.bin"), b)
	writeFile(t, filepath.Join(src, "a.txt"), []byte("hello"))

	got := generate(t, src)
	if h := sha256Hex(got); h != goldenTwoFilesSHA256 {
		t.Fatalf("与 Python golden 的 sha256 不一致：got %s want %s\n%s", h, goldenTwoFilesSHA256, got)
	}
	if !strings.Contains(got, `"a.txt"`) || !strings.Contains(got, `"c.bin"`) {
		t.Fatalf("资源未收录：\n%s", got)
	}
	if strings.Index(got, `"a.txt"`) > strings.Index(got, `"c.bin"`) {
		t.Fatalf("资源未按名称升序：\n%s", got)
	}
}

func TestGenerateResourcesEmptyMatchesPythonGolden(t *testing.T) {
	got := generate(t, t.TempDir())
	if h := sha256Hex(got); h != goldenEmptySHA256 {
		t.Fatalf("空表与 Python golden 的 sha256 不一致：got %s want %s\n%s", h, goldenEmptySHA256, got)
	}
	if !strings.Contains(got, "空表：无资源的工程零成本") || !strings.Contains(got, "return 0") {
		t.Fatalf("空表输出不符：\n%s", got)
	}
}

// 迁移期必须复现旧实现的「拒绝子目录」行为；放开子目录另行排期。
func TestGenerateResourcesRejectsSubdirectory(t *testing.T) {
	src := t.TempDir()
	writeFile(t, filepath.Join(src, "sub", "x.txt"), []byte("x"))
	err := GenerateResources(src, filepath.Join(t.TempDir(), "res.c"))
	if err == nil || !strings.Contains(err.Error(), "资源名非法（限 [A-Za-z0-9_.-]）：sub/x.txt") {
		t.Fatalf("子目录应被拒绝且点名相对路径，实际：%v", err)
	}
}

func TestGenerateResourcesRejectsInvalidName(t *testing.T) {
	src := t.TempDir()
	writeFile(t, filepath.Join(src, "bad name.txt"), []byte("x"))
	err := GenerateResources(src, filepath.Join(t.TempDir(), "res.c"))
	if err == nil || !strings.Contains(err.Error(), "资源名非法") {
		t.Fatalf("非法名应报错，实际：%v", err)
	}
}

func TestGenerateResourcesRejectsMissingDir(t *testing.T) {
	err := GenerateResources(filepath.Join(t.TempDir(), "nope"), filepath.Join(t.TempDir(), "res.c"))
	if err == nil || !strings.Contains(err.Error(), "资源目录不存在") {
		t.Fatalf("目录不存在应报错，实际：%v", err)
	}
}

func TestGenerateResourcesDeterministic(t *testing.T) {
	src := t.TempDir()
	writeFile(t, filepath.Join(src, "b.txt"), []byte("b"))
	writeFile(t, filepath.Join(src, "a.txt"), []byte("a"))
	first := generate(t, src)
	for i := 0; i < 3; i++ {
		if got := generate(t, src); got != first {
			t.Fatalf("第 %d 次生成结果不一致", i+2)
		}
	}
}
