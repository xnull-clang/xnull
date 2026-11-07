package codegen

import (
	"bytes"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/interp"
	"xnull.dev/xnull/internal/sema"
)

// M6-B0-03：跨包 import 闭环（两包/三包，编译与解释逐字节一致）。

// TestMultiPackageThreeFiles：入口 -> b -> a 三级依赖，跨包顶层函数可调用。
func TestMultiPackageThreeFiles(t *testing.T) {
	dir := writeTree(t, map[string]string{
		"main.x":  "import lib.b\n\nstatic Int main() {\n    print(banner(\"x\"))\n    print(twice(3))\n    return 0\n}\n",
		"lib/b.x": "package b\n\nimport lib.a\n\nstatic String banner(String s) {\n    return \"[\" + s + \"]\"\n}\n\nstatic Int twice(Int n) {\n    return inc(n) * 2\n}\n",
		"lib/a.x": "package a\n\nstatic Int inc(Int n) {\n    return n + 1\n}\n",
	})
	entry := filepath.Join(dir, "main.x")
	u, diags := LoadUnits(entry)
	if len(diags) != 0 {
		t.Fatalf("加载诊断：%v（跨包不应再报 RES-109）", diags)
	}
	if sd := sema.Analyze(entry, u); len(sd) != 0 {
		t.Fatalf("语义诊断：%v", sd)
	}
	var want strings.Builder
	wantCode, err := interp.Run(u, &want, nil)
	if err != nil {
		t.Fatalf("解释执行失败：%v", err)
	}

	bin := filepath.Join(t.TempDir(), "prog")
	rt := filepath.Join("..", "..", "..", "impl", "runtime")
	var stderr bytes.Buffer
	if code := Build(entry, bin, rt, &stderr); code != 0 {
		t.Fatalf("编译失败：code=%d\n%s", code, stderr.String())
	}
	var got bytes.Buffer
	cmd := exec.Command(bin)
	cmd.Stdout = &got
	gotCode := 0
	if err := cmd.Run(); err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			gotCode = ee.ExitCode()
		} else {
			t.Fatal(err)
		}
	}
	if got.String() != want.String() {
		t.Fatalf("编译路径 %q 与解释 %q 不一致", got.String(), want.String())
	}
	if gotCode != wantCode {
		t.Fatalf("退出码 %d，期望 %d", gotCode, wantCode)
	}
	if got.String() != "[x]\n8\n" {
		t.Fatalf("样例输出 %q，期望 [x]\\n8\\n", got.String())
	}
}

// 默认包符号不能被其他包导入（§3.3）：被导入文件缺 package 声明 → RES-110。
func TestMultiPackageDefaultImportedRejected(t *testing.T) {
	dir := writeTree(t, map[string]string{
		"main.x":  "package app\n\nimport lib.a\n\nstatic Int main() { return inc(1) }\n",
		"lib/a.x": "static Int inc(Int n) { return n + 1 }\n",
	})
	_, diags := LoadUnits(filepath.Join(dir, "main.x"))
	if len(diags) == 0 {
		t.Fatal("默认包被跨包导入应报错")
	}
	if diags[0].Code != codeSubFileNotNamed {
		t.Fatalf("诊断码 %s，期望 %s", diags[0].Code, codeSubFileNotNamed)
	}
}

// 跨包同名顶层函数不得静默合并（B0-03 起步形态：显式报错）。
func TestMultiPackageNameClashExplicit(t *testing.T) {
	dir := writeTree(t, map[string]string{
		"main.x":  "import lib.a\nimport lib.b\n\nstatic Int main() { return 0 }\n",
		"lib/a.x": "package a\n\nstatic Int helper() { return 1 }\n",
		"lib/b.x": "package b\n\nstatic Int helper() { return 2 }\n",
	})
	u, diags := LoadUnits(filepath.Join(dir, "main.x"))
	if len(diags) != 0 {
		t.Fatalf("加载不应报错：%v", diags)
	}
	if _, err := EmitC(u); err == nil || !strings.Contains(err.Error(), "重名") && !strings.Contains(err.Error(), "重载") {
		t.Fatalf("跨包同名应显式报错，实际：%v", err)
	}
}
