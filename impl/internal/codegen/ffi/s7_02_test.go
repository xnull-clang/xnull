package ffi

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

// S7-02：错误码映射的运行时契约（不仅是字符串生成）。
// 已知码 → ErrorKind；未知码 → Internal；Cancelled/Timeout 不降级。
func TestS7_02ErrorKindMappingRuntime(t *testing.T) {
	gen := emitErrorKind("native", []ErrRule{
		{Code: 5, Kind: "NotFound"},
		{Code: 14, Kind: "Cancelled"},
		{Code: 15, Kind: "Timeout"},
	})
	src := `#include "xrt.h"
#include <stdio.h>
#include <string.h>
` + gen + `
int main(void) {
    if (xn_ffi_native_error_kind_id(5) != XRT_ERR_NOT_FOUND) return 1;
    if (xn_ffi_native_error_kind_id(99) != XRT_ERR_INTERNAL) return 2;
    if (xn_ffi_native_error_kind_id(14) != XRT_ERR_CANCELLED) return 3;
    if (xn_ffi_native_error_kind_id(15) != XRT_ERR_TIMEOUT) return 4;
    if (strcmp(xn_ffi_native_error_kind(5), "NotFound") != 0) return 5;
    if (strcmp(xn_ffi_native_error_kind(99), "Internal") != 0) return 6;
    printf("ok\n");
    return 0;
}
`
	rt, err := filepath.Abs(filepath.Join("..", "..", "..", "runtime"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(rt, "xrt.h")); err != nil {
		t.Skipf("runtime/xrt.h 不存在：%v", err)
	}
	cc, err := exec.LookPath("cc")
	if err != nil {
		t.Skip("无 C 编译器")
	}
	dir := t.TempDir()
	cfile := filepath.Join(dir, "mapping.c")
	if err := os.WriteFile(cfile, []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
	bin := filepath.Join(dir, "mapping")
	var ccErr bytes.Buffer
	cmd := exec.Command(cc, "-std=c11", "-I", rt, "-o", bin, cfile)
	cmd.Stderr = &ccErr
	if err := cmd.Run(); err != nil {
		t.Fatalf("cc 失败：%v\n%s", err, ccErr.String())
	}
	var out bytes.Buffer
	run := exec.Command(bin)
	run.Stdout = &out
	if err := run.Run(); err != nil {
		t.Fatalf("运行失败：%v（stdout=%q）", err, out.String())
	}
	if got, want := out.String(), "ok\n"; got != want {
		t.Fatalf("stdout=%q，期望 %q", got, want)
	}
}
