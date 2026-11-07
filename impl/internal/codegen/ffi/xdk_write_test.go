package ffi

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// M6-B0-02 增补（B0-06 阻塞 #3）：XDK sys 需要 fileOpenWrite ——
// 绑定入口 + C 实现（fopen(path,"wb")），否则「读→解析→写」无法完成。
func TestXDKSysFileOpenWrite(t *testing.T) {
	reg, diags, err := Load(repoBindingsDir(t))
	if err != nil || len(diags) != 0 {
		t.Fatalf("Load 失败：%v %v", err, codeList(diags))
	}
	e, ok := reg.Entry("fileOpenWrite")
	if !ok {
		t.Fatalf("绑定缺少 fileOpenWrite（B0-06 阻塞 #3）")
	}
	if e.CName != "xdkc_file_open_write" {
		t.Fatalf("fileOpenWrite 的 cName 不符：%s", e.CName)
	}
	if e.Region != "xdkc_sys" {
		t.Fatalf("fileOpenWrite 区域不符：%s", e.Region)
	}

	sup := reg.EmitSupport()
	if len(sup.Problems) != 0 {
		t.Fatalf("Problems=%v", sup.Problems)
	}
	if !strings.Contains(sup.Text, "xn_ffi_fileOpenWrite") {
		t.Fatalf("支撑代码缺少 xn_ffi_fileOpenWrite")
	}

	// 端到端：写 → 关 → 读回比对。
	const harness = `
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(void) {
    const char *path = "/tmp/xnull_b002_file_write.txt";
    remove(path);
    xrt_handle *w = NULL;
    if (xn_ffi_fileOpenWrite(path, strlen(path), &w) != 0 || w == NULL) {
        printf("openwrite-fail\n");
        return 1;
    }
    uint8_t data[7] = {'w','r','i','t','e','0','k'};
    int32_t rc = xn_ffi_fileWrite(w, data, 7);
    printf("write rc=%d\n", rc);
    printf("close=%d\n", xn_ffi_fileClose(w));

    FILE *f = fopen(path, "rb");
    if (f == NULL) { printf("readback-fail\n"); return 1; }
    char buf[16] = {0};
    size_t n = fread(buf, 1, sizeof(buf) - 1, f);
    fclose(f);
    printf("readback n=%d text=%s\n", (int)n, buf);
    remove(path);
    return 0;
}
`
	cc := findCC(t)
	rtDir := runtimeDir(t)
	dir := t.TempDir()
	prog := filepath.Join(dir, "prog.c")
	if err := os.WriteFile(prog, []byte(sup.Text+harness), 0o644); err != nil {
		t.Fatalf("写 prog.c：%v", err)
	}
	exe := filepath.Join(dir, "prog")
	args := []string{"-std=c11", "-O2", "-Wall", "-Wno-unused-function", "-I", rtDir, "-o", exe, prog}
	for _, f := range []string{
		"rt.c", "rt_gc.c", "rt_policy.c", "rt_weak.c", "xrt_abi.c",
		"rt_std_runtime.c", "rt_std_text.c", "rt_std_sys.c", "rt_std_bytes.c",
	} {
		args = append(args, filepath.Join(rtDir, f))
	}
	if out, err := exec.Command(cc, args...).CombinedOutput(); err != nil {
		t.Fatalf("cc 失败：%v\n%s", err, out)
	}
	out, err := exec.Command(exe).CombinedOutput()
	if err != nil {
		t.Fatalf("运行失败：%v\n%s", err, out)
	}
	for _, want := range []string{"write rc=0", "close=0", "readback n=7 text=write0k"} {
		if !strings.Contains(string(out), want) {
			t.Fatalf("输出缺少 %q：\n%s", want, out)
		}
	}
}
