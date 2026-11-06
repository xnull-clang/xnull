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

// S8 §5.6：目录内全部常规文件按相对资源根的路径收录，子目录合法。
func TestGenerateResourcesIncludesSubdirectories(t *testing.T) {
	src := t.TempDir()
	writeFile(t, filepath.Join(src, "b.txt"), []byte("b"))
	writeFile(t, filepath.Join(src, "a.txt"), []byte("a"))
	writeFile(t, filepath.Join(src, "sub", "x.txt"), []byte("x"))
	writeFile(t, filepath.Join(src, "sub", "multi", "deep.bin"), []byte("deep"))
	writeFile(t, filepath.Join(src, "templates", "mail", "welcome.html"), []byte("<p>hi</p>"))

	got := generate(t, src)
	for _, want := range []string{`"a.txt"`, `"b.txt"`, `"sub/x.txt"`, `"sub/multi/deep.bin"`, `"templates/mail/welcome.html"`} {
		if !strings.Contains(got, want) {
			t.Fatalf("子目录资源未收录 %s：\n%s", want, got)
		}
	}
	// 稳定排序：a.txt < b.txt < sub/multi/deep.bin < sub/x.txt < templates/mail/welcome.html（字节序）。
	order := []string{`"a.txt"`, `"b.txt"`, `"sub/multi/deep.bin"`, `"sub/x.txt"`, `"templates/mail/welcome.html"`}
	last := -1
	for _, name := range order {
		idx := strings.Index(got, name)
		if idx < last {
			t.Fatalf("资源未按相对路径升序：%s 位置 %d 小于前项 %d\n%s", name, idx, last, got)
		}
		last = idx
	}
}

// 空目录不产生条目（§5.6「空目录不产生条目」）。
func TestGenerateResourcesEmptySubdirectoryProducesNoEntry(t *testing.T) {
	src := t.TempDir()
	writeFile(t, filepath.Join(src, "a.txt"), []byte("a"))
	if err := os.MkdirAll(filepath.Join(src, "empty", "nested"), 0o755); err != nil {
		t.Fatal(err)
	}
	got := generate(t, src)
	if strings.Contains(got, "empty") {
		t.Fatalf("空目录不应产生条目：\n%s", got)
	}
}

func TestValidateResourceName(t *testing.T) {
	valid := []string{"a.txt", "sub/x.txt", "a/b/c.bin", "a..b.txt", ".hidden", "sub/.keep"}
	for _, name := range valid {
		if err := validateResourceName(name); err != nil {
			t.Fatalf("%q 应合法，实际报错：%v", name, err)
		}
	}
	invalid := map[string]string{
		"":             "资源名为空",
		"/abs.txt":     "不得以 /",
		"trail/":       "不得以 /",
		"a//b.txt":     "空路径段",
		"./a.txt":      "非法路径段",
		"../a.txt":     "非法路径段",
		"a/../b.txt":   "非法路径段",
		"a/./b.txt":    "非法路径段",
		`a\b.txt`:      "反斜杠",
		"bad name.txt": "资源名非法",
		"a/*.txt":      "资源名非法",
	}
	for name, want := range invalid {
		err := validateResourceName(name)
		if err == nil || !strings.Contains(err.Error(), want) {
			t.Fatalf("%q 应报「%s」，实际：%v", name, want, err)
		}
	}
}

func TestGenerateResourcesRejectsInvalidNameInSubdirectory(t *testing.T) {
	src := t.TempDir()
	writeFile(t, filepath.Join(src, "sub", "bad name.txt"), []byte("x"))
	err := GenerateResources(src, filepath.Join(t.TempDir(), "res.c"))
	if err == nil || !strings.Contains(err.Error(), "资源名非法（每段限 [A-Za-z0-9_.-]）：sub/bad name.txt") {
		t.Fatalf("子目录非法名应被拒绝且点名相对路径，实际：%v", err)
	}
}

// §5.6「符号链接」：按目标内容读取；断链失败；越界与指向目录拒绝。
func TestGenerateResourcesSymlinkToFile(t *testing.T) {
	src := t.TempDir()
	writeFile(t, filepath.Join(src, "real.txt"), []byte("linked-content"))
	if err := os.Symlink(filepath.Join(src, "real.txt"), filepath.Join(src, "alias.txt")); err != nil {
		t.Skipf("无法创建符号链接：%v", err)
	}
	got := generate(t, src)
	if !strings.Contains(got, `"alias.txt"`) {
		t.Fatalf("指向文件的符号链接应按目标内容收录：\n%s", got)
	}
}

func TestGenerateResourcesRejectsBrokenSymlink(t *testing.T) {
	src := t.TempDir()
	if err := os.Symlink(filepath.Join(src, "gone.txt"), filepath.Join(src, "broken.txt")); err != nil {
		t.Skipf("无法创建符号链接：%v", err)
	}
	err := GenerateResources(src, filepath.Join(t.TempDir(), "res.c"))
	if err == nil || !strings.Contains(err.Error(), "符号链接断链：broken.txt") {
		t.Fatalf("断链应失败，实际：%v", err)
	}
}

func TestGenerateResourcesRejectsSymlinkOutsideRoot(t *testing.T) {
	outside := t.TempDir()
	writeFile(t, filepath.Join(outside, "secret.txt"), []byte("s"))
	src := t.TempDir()
	if err := os.Symlink(filepath.Join(outside, "secret.txt"), filepath.Join(src, "escape.txt")); err != nil {
		t.Skipf("无法创建符号链接：%v", err)
	}
	err := GenerateResources(src, filepath.Join(t.TempDir(), "res.c"))
	if err == nil || !strings.Contains(err.Error(), "符号链接指向资源根之外：escape.txt") {
		t.Fatalf("越界符号链接应失败，实际：%v", err)
	}
}

func TestGenerateResourcesRejectsSymlinkToDir(t *testing.T) {
	src := t.TempDir()
	if err := os.MkdirAll(filepath.Join(src, "sub"), 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(src, "sub", "x.txt"), []byte("x"))
	if err := os.Symlink(filepath.Join(src, "sub"), filepath.Join(src, "dirlink")); err != nil {
		t.Skipf("无法创建符号链接：%v", err)
	}
	err := GenerateResources(src, filepath.Join(t.TempDir(), "res.c"))
	if err == nil || !strings.Contains(err.Error(), "符号链接指向目录") {
		t.Fatalf("指向目录的符号链接应失败，实际：%v", err)
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
