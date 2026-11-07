package ffi

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// M6-B0-07b：文本变体 API —— readFileText/writeFileText（B0-06 文本变体签名）。
func TestXDKTextFileAPI(t *testing.T) {
	reg, diags, err := Load(repoBindingsDir(t))
	if err != nil || len(diags) != 0 {
		t.Fatalf("Load 失败：%v %v", err, codeList(diags))
	}
	for name, cname := range map[string]string{
		"readFileText":  "xdkc_read_file_text",
		"writeFileText": "xdkc_write_file_text",
	} {
		e, ok := reg.Entry(name)
		if !ok {
			t.Fatalf("绑定缺少 %s（B0-06 文本变体）", name)
		}
		if e.CName != cname {
			t.Fatalf("%s 的 cName 不符：%s", name, e.CName)
		}
	}

	sup := reg.EmitSupport()
	if len(sup.Problems) != 0 {
		t.Fatalf("Problems=%v", sup.Problems)
	}
	for _, sym := range []string{"xn_ffi_readFileText", "xn_ffi_writeFileText"} {
		if !strings.Contains(sup.Text, sym) {
			t.Fatalf("支撑代码缺少 %s", sym)
		}
	}

	const harness = `
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(void) {
    const char *path = "/tmp/xnull_b007b_text.txt";
    remove(path);

    const char *text = "hello\ntext\n";
    int64_t rc = -1;
    int32_t wr = xn_ffi_writeFileText(path, strlen(path), text, strlen(text), &rc);
    printf("write wr=%d rc=%lld\n", wr, (long long)rc);

    xrt_string *s = NULL;
    int32_t r = xn_ffi_readFileText(path, strlen(path), &s);
    printf("read r=%d null=%d\n", r, s == NULL);
    if (s != NULL) {
        printf("text len=%zu body=%.*s\n", xrt_string_len(s), (int)xrt_string_len(s), xrt_string_bytes(s));
        xrt_release(s);
    }

    const char *missing = "/tmp/xnull_b007b_missing.txt";
    remove(missing);
    s = NULL;
    r = xn_ffi_readFileText(missing, strlen(missing), &s);
    printf("missing r=%d null=%d\n", r, s == NULL);
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
		"rt_std_runtime.c", "rt_std_text.c", "rt_std_sys.c",
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
	for _, want := range []string{
		"write wr=0 rc=0",
		"read r=0 null=0",
		"text len=11 body=hello",
		"missing r=0 null=1",
	} {
		if !strings.Contains(string(out), want) {
			t.Fatalf("输出缺少 %q：\n%s", want, out)
		}
	}
}
