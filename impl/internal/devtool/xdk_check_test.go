package devtool

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// S8-11：xnull dev check 的第六检（XDK 8 包合同）接入。
func xdkDevFixture(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	xdkDir := filepath.Join(root, "impl", "lib", "xdk")
	if err := os.MkdirAll(xdkDir, 0o755); err != nil {
		t.Fatal(err)
	}
	for _, pkg := range []string{"errors", "tasks", "sync", "runtime", "collections", "text", "sys", "net"} {
		src := "// xdk." + pkg + "\n// 稳定性：@preview\n\nstatic Int fixture() { return 0 }\n"
		if pkg == "errors" {
			src = "// xdk.errors\n// 稳定性：@preview\n\nimport xdk.runtime\n\nstatic Int fixture() { return 0 }\n"
		}
		if pkg == "text" {
			src = "// xdk.text\n// 稳定性：@preview\n\nimport xdk.errors\n\nstatic Int fixture() { return 0 }\n"
		}
		if err := os.WriteFile(filepath.Join(xdkDir, pkg+".x"), []byte(src), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	table := "# package\tstability\tdeps\truntime_services\tffi_boundary\n" +
		"errors\tpreview\truntime\tdiagnose\txdkc_runtime\n" +
		"tasks\tpreview\terrors,runtime\tscheduler\t-\n" +
		"sync\tpreview\terrors,runtime\tscheduler\t-\n" +
		"runtime\tpreview\t-\tdiagnose\txdkc_runtime\n" +
		"collections\tpreview\t-\tmemory\t-\n" +
		"text\tpreview\terrors\tmemory\txdkc_text\n" +
		"sys\tpreview\terrors\thandle\txdkc_sys\n" +
		"net\tpreview\terrors,tasks,sync\thandle\t-\n"
	if err := os.MkdirAll(filepath.Join(root, "impl", "docs"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "impl", "docs", "xdk-packages.tsv"), []byte(table), 0o644); err != nil {
		t.Fatal(err)
	}
	design := ""
	for _, pkg := range []string{"errors", "tasks", "sync", "runtime", "collections", "text", "sys", "net"} {
		design += "impl/lib/xdk/" + pkg + ".x\n"
	}
	if err := os.WriteFile(filepath.Join(root, "impl", "docs", "xdk-design.md"), []byte(design), 0o644); err != nil {
		t.Fatal(err)
	}
	return root
}

func TestCheckXDKContractPass(t *testing.T) {
	root := xdkDevFixture(t)
	r, ok := checkXDK(root)
	if !ok {
		t.Fatal("8 包齐备时应执行第六检")
	}
	if len(r.fails) != 0 {
		t.Fatalf("正例不应失败：%v", r.fails)
	}
}

func TestCheckXDKContractViolation(t *testing.T) {
	root := xdkDevFixture(t)
	textPath := filepath.Join(root, "impl", "lib", "xdk", "text.x")
	src, err := os.ReadFile(textPath)
	if err != nil {
		t.Fatal(err)
	}
	src = []byte(strings.Replace(string(src), "import xdk.errors", "import xdk.sys", 1))
	if err := os.WriteFile(textPath, src, 0o644); err != nil {
		t.Fatal(err)
	}
	r, ok := checkXDK(root)
	if !ok {
		t.Fatal("应执行第六检")
	}
	if len(r.fails) == 0 {
		t.Fatal("依赖违约应使 dev check 失败")
	}
	joined := strings.Join(r.fails, "\n")
	if !strings.Contains(joined, "XDK-003") {
		t.Fatalf("缺少依赖违约码：%s", joined)
	}
}

func TestCheckXDKContractSkipWithoutUnits(t *testing.T) {
	root := t.TempDir()
	if _, ok := checkXDK(root); ok {
		t.Fatal("8 包未齐时应跳过而非失败")
	}
}
