package codegen

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/codegen/ffi"
)

// FFI-07：.unaware + @longRunning 调用点路由 xrt_companion_submit/wait；
// 清单 companion 只认注册表（不按命名推导）。

const ffi07Xfb = `ffi native {
  @ffiEntry(cName = "native_exec")
  @lease(x = .borrow)
  @longRunning
  @blocking(.unaware)
  Int64 ffiExec(Int64 x);

  @ffiEntry(cName = "native_exec_companion")
  @lease(x = .borrow)
  @blocking(.aware)
  Int64 submitffiExec(Int64 x);
}
`

const ffi07Native = `#include <stdint.h>
#include "xrt.h"

int64_t native_exec(int64_t x) {
    /* 伴生 worker 上运行；主/载体线程为 0。 */
    return xrt_companion_on_worker() ? x : -1;
}

int64_t native_exec_companion(int64_t x) { return x; }
`

const ffi07Main = `static Int main() {
    Int64 v = ffiExec(7)
    print(str(v))
    return 0
}
`

func TestFFI07CompanionRoutingEndToEnd(t *testing.T) {
	dir := t.TempDir()
	writeFFIFile(t, filepath.Join(dir, "bindings", "native.xfb"), ffi07Xfb)
	writeFFIFile(t, filepath.Join(dir, "main.x"), ffi07Main)
	native := filepath.Join(dir, "native.c")
	writeFFIFile(t, native, ffi07Native)

	reg, diags, err := LoadFFI(dir)
	if err != nil || len(diags) != 0 {
		t.Fatalf("LoadFFI: err=%v diags=%v", err, diags)
	}
	sup := reg.EmitSupport()
	if len(sup.Problems) != 0 {
		t.Fatalf("支撑代码生成失败：%v", sup.Problems)
	}
	for _, sym := range []string{
		"xn_companion_ffiExec_args", "xn_companion_ffiExec_thunk",
		"a->rc = xn_ffi_ffiExec(a->p0, &a->out);",
	} {
		if !strings.Contains(sup.Text, sym) {
			t.Fatalf("支撑代码缺少 %q：\n%s", sym, sup.Text)
		}
	}

	bin := filepath.Join(t.TempDir(), "prog")
	var stderr bytes.Buffer
	if code := BuildWithOptions(filepath.Join(dir, "main.x"), bin, filepath.Join("..", "..", "runtime"),
		Options{LinkArgs: []string{native}}, &stderr); code != 0 {
		t.Fatalf("构建失败 code=%d\n%s", code, stderr.String())
	}
	csrc, err := os.ReadFile(bin + ".c")
	if err != nil {
		t.Fatalf("读取生成 C：%v", err)
	}
	for _, want := range []string{
		"xrt_companion_submit(", "xrt_companion_wait(", "xn_companion_ffiExec_thunk",
		"xrt_release(", "xn_companion_ffiExec_args",
	} {
		if !strings.Contains(string(csrc), want) {
			t.Fatalf("调用点未路由 companion，缺少 %q", want)
		}
	}

	cmd := exec.Command(bin)
	cmd.Env = append(os.Environ(), "XNULL_COMPANIONS=1")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("运行失败：%v\n%s", err, out)
	}
	if got := strings.TrimSpace(string(out)); got != "7" {
		t.Fatalf("stdout=%q，期望伴生 worker 返回 7", got)
	}
}

func TestFFI07ManifestCompanionRegistry(t *testing.T) {
	t.Run("companion 存在", func(t *testing.T) {
		dir := t.TempDir()
		writeFFIFile(t, filepath.Join(dir, "bindings", "native.xfb"), ffi07Xfb)
		reg, diags, err := LoadFFI(dir)
		if err != nil || len(diags) != 0 {
			t.Fatalf("LoadFFI: err=%v diags=%v", err, diags)
		}
		rows := reg.BlockingManifest()
		found := false
		for _, r := range rows {
			if r.Entry == "ffiExec" {
				found = true
				if !r.LongRunning || r.Class != ".unaware" || r.Companion != "submitffiExec" {
					t.Fatalf("清单行不符：%+v", r)
				}
			}
		}
		if !found {
			t.Fatal("清单缺少 ffiExec")
		}
	})

	t.Run("companion 缺失拒绝", func(t *testing.T) {
		dir := t.TempDir()
		writeFFIFile(t, filepath.Join(dir, "bindings", "native.xfb"), `ffi native {
  @ffiEntry(cName = "native_exec")
  @lease(x = .borrow)
  @longRunning
  @blocking(.unaware)
  Int64 ffiExec(Int64 x);
}
`)
		_, diags, err := LoadFFI(dir)
		if err != nil {
			t.Fatalf("LoadFFI: %v", err)
		}
		if len(diags) == 0 || diags[0].Code != "FFI-107" {
			t.Fatalf("缺 companion 应报 FFI-107，得到 %v", diags)
		}
	})

	t.Run("跨文件 companion 可见", func(t *testing.T) {
		dir := t.TempDir()
		writeFFIFile(t, filepath.Join(dir, "bindings", "a.xfb"), `ffi a {
  @ffiEntry(cName = "native_exec")
  @lease(x = .borrow)
  @longRunning
  @blocking(.unaware)
  Int64 ffiExec(Int64 x);
}
`)
		writeFFIFile(t, filepath.Join(dir, "bindings", "b.xfb"), `ffi b {
  @ffiEntry(cName = "native_exec_companion")
  @lease(x = .borrow)
  @blocking(.aware)
  Int64 submitffiExec(Int64 x);
}
`)
		_, diags, err := LoadFFI(dir)
		if err != nil || len(diags) != 0 {
			t.Fatalf("跨文件 companion 应通过：err=%v diags=%v", err, diags)
		}
	})

	t.Run("清单不按命名推导", func(t *testing.T) {
		reg := &ffi.Registry{Entries: []ffi.Entry{{
			Name: "ffiExec", LongRunning: true, Blocking: ffi.BlockingUnaware,
		}}}
		rows := reg.BlockingManifest()
		if len(rows) != 1 || rows[0].Companion != "" {
			t.Fatalf("未注册 companion 不得出现在清单：%+v", rows)
		}
	})
}
