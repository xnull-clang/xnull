package codegen

import (
	"bytes"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// S7-04：@unsafe 门禁（S7 §8 / FFI-04 / S8 §7）。
// 声明层「仅 bindings/ + 合同文本必填」由 ffi.Load 校验；本卡补 link.unsafe 构建门禁。

const s704Xfb = `ffi native704 {
  @ffiEntry(cName = "native_danger")
  @lease(p = .borrow)
  @blocking(.aware)
  @unsafe(contract = "调用方必须保证 p 指向有效内存；违约将越界访问并终止进程")
  Int64 ffiDanger(Int64 p);
}
`

const s704Native = `#include <stdint.h>
int64_t native_danger(int64_t p) { return p + 41; }
`

const s704Main = `static Int main() {
    print(ffiDanger(1))
    return 0
}
`

func s704Manifest(unsafeLine string) string {
	return `project {
  groupId    = com.example
  artifactId = unsafe-app
  version    = 1.0.0
  packaging  = app

  link {
    ` + unsafeLine + `
  }
}
`
}

func s704Project(t *testing.T, manifest string) (mainPath, native string) {
	t.Helper()
	dir := t.TempDir()
	writeFFIFile(t, filepath.Join(dir, "bindings", "native704.xfb"), s704Xfb)
	writeFFIFile(t, filepath.Join(dir, "main.x"), s704Main)
	native = filepath.Join(dir, "native704.c")
	writeFFIFile(t, native, s704Native)
	if manifest != "" {
		writeFFIFile(t, filepath.Join(dir, "xnull.project"), manifest)
	}
	return filepath.Join(dir, "main.x"), native
}

func s704Build(t *testing.T, mainPath, native string) (int, string) {
	t.Helper()
	dir := t.TempDir()
	bin := filepath.Join(dir, "prog")
	var stderr bytes.Buffer
	code := BuildWithOptions(mainPath, bin, filepath.Join("..", "..", "runtime"),
		Options{LinkArgs: []string{native}}, &stderr)
	return code, stderr.String()
}

func TestS704UnsafeGateEnabled(t *testing.T) {
	mainPath, native := s704Project(t, s704Manifest("unsafe = true"))
	code, stderr := s704Build(t, mainPath, native)
	if code != 0 {
		t.Fatalf("link.unsafe=true 应构建成功，code=%d\n%s", code, stderr)
	}
	if !strings.Contains(stderr, "link.unsafe=true") || !strings.Contains(stderr, "ffiDanger") {
		t.Fatalf("启用 link.unsafe 后必须记录构建日志（S8 §7）：%q", stderr)
	}
}

func TestS704UnsafeGateRejectsDefault(t *testing.T) {
	cases := []struct {
		name     string
		manifest string
		want     string
	}{
		{"无工程清单", "", "link.unsafe"},
		{"link.unsafe=false", s704Manifest("unsafe = false"), "link.unsafe 未开启"},
		{"缺省 unsafe", "project {\n  groupId = com.example\n  artifactId = a\n  version = 1.0.0\n  packaging = app\n}\n", "link.unsafe 未开启"},
		{"非法值", s704Manifest("unsafe = maybe"), "非法"},
		{"重复字段", s704Manifest("unsafe = true\n    unsafe = true"), "重复声明"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			mainPath, native := s704Project(t, tc.manifest)
			code, stderr := s704Build(t, mainPath, native)
			if code == 0 {
				t.Fatalf("未开启 link.unsafe 时构建必须失败：%s", stderr)
			}
			if !strings.Contains(stderr, tc.want) {
				t.Fatalf("失败原因未指明 %q：%s", tc.want, stderr)
			}
		})
	}
}

func TestS704UnsafeOnlyInBindings(t *testing.T) {
	// 应用代码目录（非 bindings/）中的 @unsafe 入口必须被声明层拒绝（S7 §8 第 2 条）。
	dir := t.TempDir()
	writeFFIFile(t, filepath.Join(dir, "src", "evil.xfb"), s704Xfb)
	writeFFIFile(t, filepath.Join(dir, "xnull.project"), s704Manifest("unsafe = true"))
	_, diags, err := LoadFFI(dir)
	if err != nil {
		t.Fatalf("LoadFFI: %v", err)
	}
	joined := ""
	for _, d := range diags {
		joined += d.Code + " "
	}
	if !strings.Contains(joined, "FFI-110") {
		t.Fatalf("@unsafe 出现在 bindings/ 之外应报 FFI-110，得到 %v", joined)
	}
}

func TestS704UnsafeContractRequired(t *testing.T) {
	// 合同文本必填（S7 §8 第 1 条）：无 contract 的 @unsafe 必须拒绝。
	dir := t.TempDir()
	writeFFIFile(t, filepath.Join(dir, "bindings", "native.xfb"), `ffi native {
  @ffiEntry(cName = "native_danger")
  @lease(p = .borrow)
  @blocking(.aware)
  @unsafe
  Int64 ffiDanger(Int64 p);
}
`)
	writeFFIFile(t, filepath.Join(dir, "xnull.project"), s704Manifest("unsafe = true"))
	_, diags, err := LoadFFI(dir)
	if err != nil {
		t.Fatalf("LoadFFI: %v", err)
	}
	joined := ""
	for _, d := range diags {
		joined += d.Code + " "
	}
	if !strings.Contains(joined, "FFI-110") {
		t.Fatalf("缺合同文本应报 FFI-110，得到 %v", joined)
	}
}

func TestS704RunUnsafeEntry(t *testing.T) {
	mainPath, native := s704Project(t, s704Manifest("unsafe = true"))
	dir := t.TempDir()
	bin := filepath.Join(dir, "prog")
	var stderr bytes.Buffer
	if code := BuildWithOptions(mainPath, bin, filepath.Join("..", "..", "runtime"),
		Options{LinkArgs: []string{native}}, &stderr); code != 0 {
		t.Fatalf("构建失败：%s", stderr.String())
	}
	out, err := exec.Command(bin).CombinedOutput()
	if err != nil {
		t.Fatalf("运行失败：%v\n%s", err, out)
	}
	if strings.TrimSpace(string(out)) != "42" {
		t.Fatalf("@unsafe 入口调用输出 %q，期望 42", out)
	}
}
