package codegen

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

// S7-05：弱表 bindings-only 构建检查（S7 §6.2）。
// 应用层 TU 不定义 XRT_BINDINGS_LAYER 时引用 xrt_weak_* 必须编译失败；
// 绑定层 TU 定义宏后必须编译成功。
func TestS7_05WeakTableBindingsOnly(t *testing.T) {
	rt, err := filepath.Abs(filepath.Join("..", "..", "runtime"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(rt, "xrt.h")); err != nil {
		t.Skipf("runtime/xrt.h 不存在：%v", err)
	}
	dir := t.TempDir()

	compile := func(name, src string) error {
		srcPath := filepath.Join(dir, name+".c")
		objPath := filepath.Join(dir, name+".o")
		if err := os.WriteFile(srcPath, []byte(src), 0o644); err != nil {
			t.Fatal(err)
		}
		cmd := exec.Command("cc", "-std=c11", "-I", rt, "-c", srcPath, "-o", objPath)
		var stderr bytes.Buffer
		cmd.Stderr = &stderr
		if err := cmd.Run(); err != nil {
			return &compileError{err: err, stderr: stderr.String()}
		}
		return nil
	}

	const appSrc = `#include "xrt.h"
int main(void) { return xrt_weak_bind(0) != 0; }
`
	if err := compile("app", appSrc); err == nil {
		t.Fatalf("应用层引用 xrt_weak_* 应编译失败（S7 §6.2）")
	}

	const bindSrc = `#define XRT_BINDINGS_LAYER 1
#include "xrt.h"
int main(void) { return xrt_weak_bind(0) != 0; }
`
	if err := compile("bind", bindSrc); err != nil {
		t.Fatalf("绑定层定义 XRT_BINDINGS_LAYER 后应编译成功：%v", err)
	}
}

type compileError struct {
	err    error
	stderr string
}

func (e *compileError) Error() string { return e.err.Error() + ": " + e.stderr }
