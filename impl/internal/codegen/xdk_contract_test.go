package codegen

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// XDK-02/XDK-10 静态核验回归。测试自身不依赖 E3 分支文件：
//   - 固定夹具验证每条规则的红/绿；
//   - 真仓库检查在 8 个 XDK 单元齐备时运行（main），否则跳过并提示。

func xdkFixtureRoot(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	dirs := []string{
		filepath.Join(root, "impl", "lib", "xdk"),
		filepath.Join(root, "impl", "docs"),
		filepath.Join(root, "bindings", "xdk"),
	}
	for _, d := range dirs {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	for _, pkg := range xdkCanonicalPackages {
		xdkWriteFixtureUnit(t, root, pkg, xdkDefaultFixtureUnit(pkg))
	}
	if err := os.WriteFile(filepath.Join(root, "impl", "docs", "xdk-packages.tsv"), []byte(xdkDefaultFixtureTable()), 0o644); err != nil {
		t.Fatal(err)
	}
	var design strings.Builder
	for _, pkg := range xdkCanonicalPackages {
		design.WriteString("impl/lib/xdk/" + pkg + ".x\n")
	}
	if err := os.WriteFile(filepath.Join(root, "impl", "docs", "xdk-design.md"), []byte(design.String()), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "bindings", "xdk", "sys.xfb"), []byte(xdkFixtureXfb), 0o644); err != nil {
		t.Fatal(err)
	}
	return root
}

func xdkDefaultFixtureUnit(pkg string) string {
	return "// xdk." + pkg + " —— fixture\n" +
		"// 稳定性：@preview\n\n" +
		"static Int fixture() { return 0 }\n"
}

func xdkDefaultFixtureTable() string {
	return "# package\tstability\tdeps\truntime_services\tffi_boundary\n" +
		"errors\tpreview\truntime\tdiagnose\txdkc_runtime\n" +
		"tasks\tpreview\terrors,runtime\tscheduler\t-\n" +
		"sync\tpreview\terrors,runtime\tscheduler\t-\n" +
		"runtime\tpreview\t-\tdiagnose\txdkc_runtime\n" +
		"collections\tpreview\t-\tmemory\t-\n" +
		"text\tpreview\terrors\tmemory\txdkc_text\n" +
		"sys\tpreview\terrors\thandle\txdkc_sys\n" +
		"net\tpreview\terrors,tasks,sync\thandle\t-\n"
}

const xdkFixtureXfb = `ffi xdkc_sys {
  handle File { close = fileClose }

  @ffiEntry(cName = "xdkc_file_close")
  @lease(f = .borrow)
  @blocking(.aware)
  Int32 fileClose(File f);
}
`

func xdkWriteFixtureUnit(t *testing.T, root, pkg, src string) {
	t.Helper()
	path := filepath.Join(root, "impl", "lib", "xdk", pkg+".x")
	if err := os.WriteFile(path, []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
}

func xdkHasCode(vs []XDKContractViolation, code string) bool {
	for _, v := range vs {
		if v.Code == code {
			return true
		}
	}
	return false
}

func xdkWantOnly(t *testing.T, root string, code string) {
	t.Helper()
	vs := CheckXDKContracts(root)
	if !xdkHasCode(vs, code) {
		t.Fatalf("期望 %s，实际：%v", code, vs)
	}
}

func TestXDKContractsFixturePass(t *testing.T) {
	root := xdkFixtureRoot(t)
	if vs := CheckXDKContracts(root); len(vs) != 0 {
		t.Fatalf("正例不应违约：%v", vs)
	}
}

func TestXDKContractsDependencyViolation(t *testing.T) {
	root := xdkFixtureRoot(t)
	xdkWriteFixtureUnit(t, root, "text", `// xdk.text —— fixture
// 稳定性：@preview

import xdk.sys

static Int fixture() { return 0 }
`)
	xdkWantOnly(t, root, xdkCodeDeps)
}

func TestXDKContractsCycle(t *testing.T) {
	root := xdkFixtureRoot(t)
	table := strings.Replace(
		xdkDefaultFixtureTable(),
		"errors\tpreview\truntime\t",
		"errors\tpreview\ttext\t", 1)
	table = strings.Replace(table, "text\tpreview\terrors\t", "text\tpreview\terrors\t", 1)
	if err := os.WriteFile(filepath.Join(root, "impl", "docs", "xdk-packages.tsv"), []byte(table), 0o644); err != nil {
		t.Fatal(err)
	}
	xdkWriteFixtureUnit(t, root, "errors", `// xdk.errors —— fixture
// 稳定性：@preview

import xdk.text

static Int fixture() { return 0 }
`)
	xdkWantOnly(t, root, xdkCodeCycle)
}

func TestXDKContractsNaming(t *testing.T) {
	root := xdkFixtureRoot(t)
	xdkWriteFixtureUnit(t, root, "text", `// xdk.text —— fixture
// 稳定性：@preview

class bad_name {
}

static Int fixture() { return 0 }
`)
	xdkWantOnly(t, root, xdkCodeNaming)
}

func TestXDKContractsStabilityMismatch(t *testing.T) {
	root := xdkFixtureRoot(t)
	table := strings.Replace(
		xdkDefaultFixtureTable(),
		"text\tpreview\t", "text\tstable\t", 1)
	if err := os.WriteFile(filepath.Join(root, "impl", "docs", "xdk-packages.tsv"), []byte(table), 0o644); err != nil {
		t.Fatal(err)
	}
	xdkWantOnly(t, root, xdkCodeStability)
}

func TestXDKContractsImplicitGlobal(t *testing.T) {
	root := xdkFixtureRoot(t)
	xdkWriteFixtureUnit(t, root, "text", `// xdk.text —— fixture
// 稳定性：@preview

Int counter = 0

static Int fixture() { return counter }
`)
	xdkWantOnly(t, root, xdkCodeImplicit)
}

func TestXDKContractsResourceClose(t *testing.T) {
	root := xdkFixtureRoot(t)
	xfb := strings.Replace(xdkFixtureXfb, "close = fileClose", "close = missingClose", 1)
	if err := os.WriteFile(filepath.Join(root, "bindings", "xdk", "sys.xfb"), []byte(xfb), 0o644); err != nil {
		t.Fatal(err)
	}
	xdkWantOnly(t, root, xdkCodeResource)
}

// 真仓库检查：main 合入 8 个 XDK 单元后必须零违约；当前分支缺单元时跳过。
// 可用 XNULL_XDK_REPO 指向 main 快照做本地预检。
func TestXDKContractsRepo(t *testing.T) {
	root := os.Getenv("XNULL_XDK_REPO")
	if root == "" {
		root = filepath.Join("..", "..", "..")
	}
	if _, err := os.Stat(filepath.Join(root, "impl", "lib", "xdk", "errors.x")); err != nil {
		t.Skip("XDK 单元未合入当前分支（需 main 的 S6-06/07/08）；已用夹具覆盖规则")
	}
	if vs := CheckXDKContracts(root); len(vs) != 0 {
		for _, v := range vs {
			t.Errorf("%s", v)
		}
	}
}
