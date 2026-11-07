package devtool

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestGenerateResourcesSortedAndNested(t *testing.T) {
	src := t.TempDir()
	writeFixture(t, filepath.Join(src, "b.bin"), string([]byte{0x01, 0x02, 0xFF}))
	writeFixture(t, filepath.Join(src, "a.txt"), "hello")
	writeFixture(t, filepath.Join(src, "templates", "a.html"), "<p>x</p>")

	out := filepath.Join(t.TempDir(), "res_table.c")
	if err := GenerateResources(src, out); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(out)
	if err != nil {
		t.Fatal(err)
	}
	got := string(data)

	// 按名称升序：a.txt < b.bin < templates/a.html。
	ia := strings.Index(got, `"a.txt"`)
	ib := strings.Index(got, `"b.bin"`)
	it := strings.Index(got, `"templates/a.html"`)
	if ia < 0 || ib < 0 || it < 0 || !(ia < ib && ib < it) {
		t.Fatalf("资源未按名称升序生成：\n%s", got)
	}
	if !strings.Contains(got, "0x01, 0x02, 0xFF") {
		t.Fatalf("二进制字节未正确生成：\n%s", got)
	}
	if !strings.Contains(got, "xrt_resource_get") {
		t.Fatalf("缺少查找函数：\n%s", got)
	}
}

func TestGenerateResourcesEmpty(t *testing.T) {
	src := t.TempDir()
	out := filepath.Join(t.TempDir(), "res_table.c")
	if err := GenerateResources(src, out); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(out)
	if err != nil {
		t.Fatal(err)
	}
	got := string(data)
	if !strings.Contains(got, "空表：无资源的工程零成本") || !strings.Contains(got, "return 0") {
		t.Fatalf("空表输出不符：\n%s", got)
	}
}

func TestGenerateResourcesDeterministic(t *testing.T) {
	src := t.TempDir()
	writeFixture(t, filepath.Join(src, "b.txt"), "b")
	writeFixture(t, filepath.Join(src, "a.txt"), "a")

	out1 := filepath.Join(t.TempDir(), "1.c")
	out2 := filepath.Join(t.TempDir(), "2.c")
	if err := GenerateResources(src, out1); err != nil {
		t.Fatal(err)
	}
	if err := GenerateResources(src, out2); err != nil {
		t.Fatal(err)
	}
	d1, _ := os.ReadFile(out1)
	d2, _ := os.ReadFile(out2)
	if string(d1) != string(d2) {
		t.Fatal("两次生成结果不一致")
	}
}

func TestGenerateResourcesRejectsInvalidName(t *testing.T) {
	src := t.TempDir()
	writeFixture(t, filepath.Join(src, "bad name.txt"), "x")
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
