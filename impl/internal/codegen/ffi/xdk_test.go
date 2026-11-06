package ffi

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// 本测试验证 M4.6 的绑定面：仓库内 bindings/xdk/*.xfb 经合同校验后，
// 生成包装代码并与 C 层原语（rt_std_*）联合编译运行。

func repoBindingsDir(t *testing.T) string {
	t.Helper()
	p, err := filepath.Abs(filepath.Join("..", "..", "..", "..", "bindings"))
	if err != nil {
		t.Fatalf("bindings 目录解析失败：%v", err)
	}
	if _, err := os.Stat(filepath.Join(p, "xdk", "runtime.xfb")); err != nil {
		t.Skipf("bindings/xdk 不存在（%s），跳过", p)
	}
	return p
}

func TestXdkBindingsLoadAndEmit(t *testing.T) {
	reg, diags, err := Load(repoBindingsDir(t))
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if len(diags) != 0 {
		t.Fatalf("仓库绑定不应有诊断：%v", codeList(diags))
	}
	want := []string{"diagnose", "dirClose", "dirOpen", "dirRead", "exit", "fileClose", "fileOpenRead", "fileRead", "fileWrite", "nowMono", "nowWall", "pathExists"}
	got := make([]string, 0, len(reg.Entries))
	for _, e := range reg.Entries {
		got = append(got, e.Name)
	}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatalf("入口清单/排序不符\n got=%v\nwant=%v", got, want)
	}

	sup := reg.EmitSupport()
	if len(sup.Problems) != 0 {
		t.Fatalf("XDK 绑定应可全部编组，Problems=%v", sup.Problems)
	}
	for _, sym := range []string{
		"xn_ffi_diagnose", "xn_ffi_nowMono", "xn_ffi_fileOpenRead", "xn_ffi_fileClose",
		"xn_ffi_dirOpen", "xn_ffi_dirRead", "xn_ffi_pathExists",
		"xn_ffi_xdkc_sys_error_kind", "xn_ffi_xdkc_runtime_error_kind",
	} {
		if !strings.Contains(sup.Text, sym) {
			t.Fatalf("支撑代码缺少 %s", sym)
		}
	}
	if !strings.Contains(sup.Text, "case 1: return \"Invalid\";") {
		t.Fatalf("错误映射未生成")
	}
}

const xdkHarness = `
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

int main(void) {
    int64_t mono = 0, wall = 0;
    if (xn_ffi_nowMono(&mono) != 0) { printf("mono-fail\n"); return 1; }
    if (xn_ffi_nowWall(&wall) != 0) { printf("wall-fail\n"); return 1; }
    printf("mono_ok=%d\n", mono > 0);
    printf("wall_ok=%d\n", wall > 1700000000000LL);

    xn_ffi_diagnose("xdk-diagnose", 12);

    const char *path = "/tmp/xnull_xdk_ffi_test.txt";
    FILE *f = fopen(path, "wb");
    if (f == NULL) { printf("write-fail\n"); return 1; }
    fwrite("xdk-io", 1, 6, f);
    fclose(f);

    xrt_handle *h = NULL;
    if (xn_ffi_fileOpenRead(path, strlen(path), &h) != 0 || h == NULL) {
        printf("open-fail\n");
        return 1;
    }
    printf("native_present=%d\n", xrt_handle_native(h) != NULL);

    char buf[8] = {0};
    int64_t n = 0;
    int32_t rc = xn_ffi_fileRead(h, buf, 6, &n);
    printf("read rc=%d n=%lld text=%s\n", rc, (long long)n, buf);

    printf("close1=%d close2=%d\n", xn_ffi_fileClose(h), xn_ffi_fileClose(h));
    printf("native_after_close=%d\n", xrt_handle_native(h) == NULL);

    /* 目录绑定面：开 → 迭代 → 幂等关；路径存在性 */
    const char *dd = "/tmp/xnull_xdk_dir_test";
    mkdir(dd, 0755);
    char fpath[128];
    snprintf(fpath, sizeof(fpath), "%s/a.txt", dd);
    f = fopen(fpath, "wb");
    if (f != NULL) {
        fclose(f);
    }

    xrt_handle *dh = NULL;
    if (xn_ffi_dirOpen(dd, strlen(dd), &dh) != 0 || dh == NULL) {
        printf("diropen-fail\n");
        return 1;
    }
    int entries = 0;
    for (;;) {
        xrt_string *ent = NULL;
        if (xn_ffi_dirRead(dh, &ent) != 0) {
            printf("dirread-fail\n");
            return 1;
        }
        if (ent == NULL) {
            break;
        }
        entries++;
        xrt_release(ent);
    }
    printf("dir_entries>=3=%d\n", entries >= 3);
    printf("dirclose=%d\n", xn_ffi_dirClose(dh));

    uint8_t ex = 0;
    xn_ffi_pathExists(fpath, strlen(fpath), &ex);
    printf("exists=%d\n", (int)ex);

    remove(fpath);
    rmdir(dd);
    return 0;
}
`

func TestXdkWrappersRun(t *testing.T) {
	cc := findCC(t)
	rtDir := runtimeDir(t)
	reg, diags, err := Load(repoBindingsDir(t))
	if err != nil || len(diags) != 0 {
		t.Fatalf("Load 失败：%v %v", err, codeList(diags))
	}
	sup := reg.EmitSupport()
	if len(sup.Problems) != 0 {
		t.Fatalf("Problems=%v", sup.Problems)
	}

	dir := t.TempDir()
	prog := filepath.Join(dir, "prog.c")
	if err := os.WriteFile(prog, []byte(sup.Text+xdkHarness), 0o644); err != nil {
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
	text := string(out)
	for _, want := range []string{
		"mono_ok=1",
		"wall_ok=1",
		"native_present=1",
		"read rc=0 n=6 text=xdk-io",
		"close1=0 close2=0",
		"native_after_close=1",
		"xdk-diagnose",
		"dir_entries>=3=1",
		"dirclose=0",
		"exists=1",
	} {
		if !strings.Contains(text, want) {
			t.Fatalf("输出缺少 %q：\n%s", want, text)
		}
	}
}

func TestBlockingClassificationDocInSync(t *testing.T) {
	reg, diags, err := Load(repoBindingsDir(t))
	if err != nil || len(diags) != 0 {
		t.Fatalf("Load 失败：%v %v", err, codeList(diags))
	}
	docPath, err := filepath.Abs(filepath.Join("..", "..", "..", "docs", "blocking-classification.md"))
	if err != nil {
		t.Fatalf("文档路径解析失败：%v", err)
	}
	data, err := os.ReadFile(docPath)
	if err != nil {
		t.Fatalf("读取阻塞分类清单失败：%v", err)
	}
	doc := string(data)
	for _, row := range reg.BlockingManifest() {
		long := "否"
		if row.LongRunning {
			long = "是"
		}
		companion := row.Companion
		if companion == "" {
			companion = "—"
		}
		line := "| " + row.Entry + " | " + row.CName + " | " + row.Region + " | " + row.Class + " | " + long + " | " + companion + " |"
		if !strings.Contains(doc, line) {
			t.Fatalf("清单未与注册表同步，缺行：%s", line)
		}
	}
}
