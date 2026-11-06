package codegen

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/interp"
	"xnull.dev/xnull/internal/sema"
	"xnull.dev/xnull/internal/xfront"
)

// writeTree 在临时目录写出多文件源码树（相对路径 → 内容）。
func writeTree(t *testing.T, files map[string]string) string {
	t.Helper()
	dir := t.TempDir()
	for name, src := range files {
		p := filepath.Join(dir, name)
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte(src), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

// TestLoadUnitsOrderDeterministic 依赖在前、入口最后，且重复 import 只加载一次。
func TestLoadUnitsOrderDeterministic(t *testing.T) {
	dir := writeTree(t, map[string]string{
		"main.xn": "import a\nimport b\nstatic Int main() { return 0 }\n",
		"a.xn":    "import c\nstatic Int fa() { return 1 }\n",
		"b.xn":    "import c\nstatic Int fb() { return 2 }\n",
		"c.xn":    "static Int fc() { return 3 }\n",
	})
	u, diags := LoadUnits(filepath.Join(dir, "main.xn"))
	if len(diags) != 0 {
		t.Fatalf("诊断：%v", diags)
	}
	var names []string
	for _, d := range u.Decls {
		if fn, ok := d.(*xfront.TopFunc); ok {
			names = append(names, fn.Name)
		}
	}
	want := "fc,fa,fb,main"
	if got := strings.Join(names, ","); got != want {
		t.Fatalf("合并顺序 %s，期望 %s（依赖在前、确定性）", got, want)
	}
}

// TestLoadUnitsCycle 导入环报 RES-108（§3.4）。
func TestLoadUnitsCycle(t *testing.T) {
	dir := writeTree(t, map[string]string{
		"a.xn": "import b\nstatic Int main() { return 0 }\n",
		"b.xn": "import a\nstatic Int f() { return 0 }\n",
	})
	_, diags := LoadUnits(filepath.Join(dir, "a.xn"))
	if len(diags) == 0 {
		t.Fatal("期望导入环诊断")
	}
	if diags[0].Code != codeImportCycle {
		t.Fatalf("诊断码 %s，期望 %s", diags[0].Code, codeImportCycle)
	}
}

// TestLoadUnitsMissing 缺失包文件报 RES-106（§3.5）。
func TestLoadUnitsMissing(t *testing.T) {
	dir := writeTree(t, map[string]string{
		"a.xn": "import no_such\nstatic Int main() { return 0 }\n",
	})
	_, diags := LoadUnits(filepath.Join(dir, "a.xn"))
	if len(diags) == 0 {
		t.Fatal("期望缺失诊断")
	}
	if diags[0].Code != codeImportFileMiss {
		t.Fatalf("诊断码 %s，期望 %s", diags[0].Code, codeImportFileMiss)
	}
}

// TestMultiFileCrossFileTypeClash 跨文件类型重名由语义层报 RES-102（同包内唯一）。
func TestMultiFileCrossFileTypeClash(t *testing.T) {
	dir := writeTree(t, map[string]string{
		"main.xn": "import x\nclass Point {\n    Int y = 0;\n}\nstatic Int main() { return 0 }\n",
		"x.xn":    "class Point {\n    Int x = 0;\n}\n",
	})
	u, diags := LoadUnits(filepath.Join(dir, "main.xn"))
	if len(diags) != 0 {
		t.Fatalf("加载诊断：%v", diags)
	}
	sd := sema.Analyze(filepath.Join(dir, "main.xn"), u)
	if len(sd) == 0 {
		t.Fatal("期望跨文件类型重名诊断")
	}
	if sd[0].Code != "RES-102" {
		t.Fatalf("诊断码 %s，期望 RES-102", sd[0].Code)
	}
}

// TestMultiFileFnOverloadExplicit 跨文件同名顶层函数在 C 侧冲突 → 显式报错（不落到 cc）。
func TestMultiFileFnOverloadExplicit(t *testing.T) {
	dir := writeTree(t, map[string]string{
		"main.xn": "import y\nstatic Int f(Int a) { return a + 1 }\nstatic Int main() { return 0 }\n",
		"y.xn":    "static Int f(Int a) { return a }\n",
	})
	u, diags := LoadUnits(filepath.Join(dir, "main.xn"))
	if len(diags) != 0 {
		t.Fatalf("加载诊断：%v", diags)
	}
	if _, err := EmitC(u); err == nil {
		t.Fatal("期望重载显式报错")
	} else if !strings.Contains(err.Error(), "重载") {
		t.Fatalf("诊断内容 %v，期望提到重载", err)
	}
}

// TestMultiFileExampleCompileMatchesInterp 多文件示例双路径逐字节一致
// （主文件调子文件函数 + 子文件类被主文件使用 + 二级依赖）。
func TestMultiFileExampleCompileMatchesInterp(t *testing.T) {
	entry := filepath.Join("..", "..", "..", "examples", "multi", "main.xn")
	u, diags := LoadUnits(entry)
	if len(diags) != 0 {
		t.Fatalf("加载诊断：%v", diags)
	}
	if sd := sema.Analyze(entry, u); len(sd) != 0 {
		t.Fatalf("语义诊断：%v", sd)
	}

	// 解释路径
	var want strings.Builder
	wantCode, err := interp.Run(u, &want, nil)
	if err != nil {
		t.Fatalf("解释执行失败：%v", err)
	}

	// 编译路径
	csrc, err := EmitC(u)
	if err != nil {
		t.Fatalf("代码生成失败：%v", err)
	}
	dir := t.TempDir()
	cfile := filepath.Join(dir, "prog.c")
	if err := os.WriteFile(cfile, []byte(csrc), 0o644); err != nil {
		t.Fatal(err)
	}
	bin := filepath.Join(dir, "prog")
	rt := filepath.Join("..", "..", "..", "impl", "runtime")
	cc := exec.Command("cc", "-std=c11", "-I", rt, "-O2", "-o", bin, cfile,
		filepath.Join(rt, "rt.c"), filepath.Join(rt, "rt_gc.c"),
		filepath.Join(rt, "rt_policy.c"), filepath.Join(rt, "rt_weak.c"))
	var ccerr bytes.Buffer
	cc.Stderr = &ccerr
	if err := cc.Run(); err != nil {
		t.Fatalf("cc 编译失败：%v\n%s", err, ccerr.String())
	}
	var got bytes.Buffer
	run := exec.Command(bin)
	run.Stdout = &got
	gotCode := 0
	if err := run.Run(); err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			gotCode = ee.ExitCode()
		} else {
			t.Fatal(err)
		}
	}
	if got.String() != want.String() {
		t.Fatalf("输出不一致：\n--- 编译 ---\n%s\n--- 解释 ---\n%s", got.String(), want.String())
	}
	if gotCode != wantCode {
		t.Fatalf("退出码 %d，期望 %d", gotCode, wantCode)
	}
}
