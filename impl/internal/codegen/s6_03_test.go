package codegen

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/sema"
	"xnull.dev/xnull/internal/xfront"
)

// S6-03：procStatus 绑定暴露 + 文件/目录句柄 close 幂等（跨 FFI 用例）。
func TestS6_03ProcStatusAndHandleClose(t *testing.T) {
	dir := t.TempDir()
	sysSrc, err := os.ReadFile(filepath.Join("..", "..", "..", "bindings", "xdk", "sys.xfb"))
	if err != nil {
		t.Fatalf("读取 sys.xfb：%v", err)
	}
	writeFFIFile(t, filepath.Join(dir, "bindings", "xdk", "sys.xfb"), string(sysSrc))
	filePath := filepath.Join(dir, "data.txt")
	writeFFIFile(t, filePath, "hello")
	dirPath := dir

	src := `import xdk.sys
static Int main() {
    print(procStatus("exit 3"))
    File f = fileOpenRead("` + filePath + `")
    print(fileClose(f))
    print(fileClose(f))
    Dir d = dirOpen("` + dirPath + `")
    print(dirClose(d))
    print(dirClose(d))
    return 0
}`
	mainPath := filepath.Join(dir, "main.x")
	writeFFIFile(t, mainPath, src)
	reg, diags, err := LoadFFI(dir)
	if err != nil || len(diags) != 0 {
		t.Fatalf("LoadFFI: err=%v diags=%v", err, diags)
	}
	u, pdiags := xfront.ParseUnit(mainPath, src)
	if len(pdiags) != 0 {
		t.Fatalf("解析诊断：%v", pdiags)
	}
	if err := InjectFFI(u, reg); err != nil {
		t.Fatalf("InjectFFI: %v", err)
	}
	sema.RegisterExternalTypes(FFIHandleTypes(reg)...)
	if sd := sema.Analyze(mainPath, u); len(sd) != 0 {
		t.Fatalf("语义诊断：%v", sd)
	}
	csrc, err := EmitCWithFFI(u, reg)
	if err != nil {
		t.Fatalf("EmitCWithFFI: %v", err)
	}
	for _, want := range []string{"xn_ffi_procStatus(", "xn_ffi_fileClose(", "xn_ffi_dirClose("} {
		if !strings.Contains(csrc, want) {
			t.Fatalf("缺少 sys 绑定发射 %q：\n%s", want, csrc)
		}
	}
	rt := filepath.Join("..", "..", "runtime")
	cfile := filepath.Join(dir, "prog.c")
	writeFFIFile(t, cfile, csrc)
	bin := filepath.Join(dir, "prog")
	args := []string{"-std=c11", "-O2", "-pthread", "-I", rt, "-o", bin, cfile}
	args = append(args, runtimeLib(t))
	args = append(args, writeEmptyResourceTable(t, t.TempDir()))
	var cerr bytes.Buffer
	cc := exec.Command("cc", args...)
	cc.Stderr = &cerr
	if err := cc.Run(); err != nil {
		t.Fatalf("cc 失败：%v\n%s\n---- C ----\n%s", err, cerr.String(), csrc)
	}
	var out bytes.Buffer
	run := exec.Command(bin)
	run.Stdout = &out
	if err := run.Run(); err != nil {
		t.Fatalf("运行失败：%v（stdout=%q）", err, out.String())
	}
	// procStatus=3；file/dir close 重复调用均成功（close 以 Bool 暴露，幂等，S5 §4.4）。
	if want := "3\ntrue\ntrue\ntrue\ntrue\n"; out.String() != want {
		t.Fatalf("stdout=%q，期望 %q", out.String(), want)
	}
}

// S6-03：*Async / Process 内建入口的声明注入与调用降级（Context 不经 .xfb）。
// 仅断言生成 C 形态；端到端链接待 E5 S6-03 runtime 合入 main。
func TestS6_03AsyncAndProcessSurface(t *testing.T) {
	dir := t.TempDir()
	sysSrc, err := os.ReadFile(filepath.Join("..", "..", "..", "bindings", "xdk", "sys.xfb"))
	if err != nil {
		t.Fatalf("读取 sys.xfb：%v", err)
	}
	writeFFIFile(t, filepath.Join(dir, "bindings", "xdk", "sys.xfb"), string(sysSrc))
	src := `import xdk.sys
import xdk.tasks
static Int main() {
    Context c = Context.background()
    File? f = fileOpenReadAsync(c, "in.txt")
    if (f == null) {
        return 1
    }
    Bytes b = Bytes.fromString("A")
    Int32 code = 7
    Int64 n = fileReadAsync(c, f, b, code)
    Int32 w = fileWriteAsync(c, f, b)
    Bool ok = fileCloseAsync(c, f)
    Dir? d = dirOpenAsync(c, ".")
    Bool dc = dirCloseAsync(c, d)
    Process? p = procSpawn("true")
    Int32 st = 0
    Int32 rw = procWait(p, st)
    Int32 rk = procKill(p, 9)
    Bool pc = procClose(p)
    Int32 rr = procRunAsync(c, "true")
    Int32 rs = procStatusAsync(c, "true")
    return 0
}`
	mainPath := filepath.Join(dir, "main.x")
	writeFFIFile(t, mainPath, src)
	reg, diags, err := LoadFFI(dir)
	if err != nil || len(diags) != 0 {
		t.Fatalf("LoadFFI: err=%v diags=%v", err, diags)
	}
	u, pdiags := xfront.ParseUnit(mainPath, src)
	if len(pdiags) != 0 {
		t.Fatalf("解析诊断：%v", pdiags)
	}
	if err := InjectFFI(u, reg); err != nil {
		t.Fatalf("InjectFFI: %v", err)
	}
	if err := InjectSys603(u); err != nil {
		t.Fatalf("InjectSys603: %v", err)
	}
	// 注：sema 侧的 File?→File 收窄属 E2 SEMA-NARROW；本用例只锁发射形态。
	csrc, err := EmitCWithFFI(u, reg)
	if err != nil {
		t.Fatalf("EmitCWithFFI: %v", err)
	}
	for _, want := range []string{
		"xdkc_file_open_read_async(",
		"xdkc_file_read_async(",
		"xdkc_file_write_async(",
		"xdkc_file_close_async(",
		"xdkc_dir_open_async(",
		"xdkc_dir_close_async(",
		"xdkc_proc_spawn(",
		"xdkc_proc_wait(",
		"xdkc_proc_kill(",
		"xdkc_proc_close(",
		"xdkc_proc_run_async(",
		"xdkc_proc_status_async(",
		"xrt_handle_mark_closed(",
	} {
		if !strings.Contains(csrc, want) {
			t.Fatalf("缺少 S6-03 发射 %q：\n%s", want, csrc)
		}
	}
}

// s6BuildRun 用真实 sys 绑定构建并运行（Build 负责 FFI/S6-03 注入）。
func s6BuildRun(t *testing.T, src string) (string, int) {
	t.Helper()
	dir := t.TempDir()
	sysSrc, err := os.ReadFile(filepath.Join("..", "..", "..", "bindings", "xdk", "sys.xfb"))
	if err != nil {
		t.Fatalf("读取 sys.xfb：%v", err)
	}
	writeFFIFile(t, filepath.Join(dir, "bindings", "xdk", "sys.xfb"), string(sysSrc))
	mainPath := filepath.Join(dir, "main.x")
	writeFFIFile(t, mainPath, src)
	bin := filepath.Join(dir, "prog")
	var stderr bytes.Buffer
	if code := Build(mainPath, bin, filepath.Join("..", "..", "runtime"), &stderr); code != 0 {
		t.Fatalf("构建失败 code=%d\n%s", code, stderr.String())
	}
	var out bytes.Buffer
	cmd := exec.Command(bin)
	cmd.Stdout = &out
	err = cmd.Run()
	code := 0
	if err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			code = ee.ExitCode()
		} else {
			t.Fatalf("运行失败：%v", err)
		}
	}
	return out.String(), code
}

// S6-03：Async 取消是可恢复错误（fileReadAsync 返回 -1、code=2，不 exit）。
func TestS6_03AsyncCancelRecoverable(t *testing.T) {
	dir := t.TempDir()
	data := filepath.Join(dir, "in.txt")
	writeFFIFile(t, data, "abc")
	src := `import xdk.sys
import xdk.tasks
import xdk.runtime
@tasks
static Int main() {
    Context c = Context.background()
    Context dead = c.withDeadline(nowMono() - 1)
    File f = fileOpenRead("` + data + `")
    Bytes b = Bytes.fromString("")
    Int32 code = 0
    Int64 n = fileReadAsync(dead, f, b, code)
    print(str(n))
    print(code)
    fileClose(f)
    return 0
}`
	out, code := s6BuildRun(t, src)
	if code != 0 || out != "-1\n2\n" {
		t.Fatalf("out=%q code=%d，期望 \"-1\\n2\\n\" / 0", out, code)
	}
}

// S6-03：procRunAsync 成功返回子进程退出码；取消返回 -1（不与 0—255 退出码混淆）。
func TestS6_03ProcRunStatus(t *testing.T) {
	src := `import xdk.sys
import xdk.tasks
import xdk.runtime
@tasks
static Int main() {
    Context c = Context.background()
    print(procRunAsync(c, "exit 7"))
    Context dead = c.withDeadline(nowMono() - 1)
    print(procRunAsync(dead, "sleep 1"))
    return 0
}`
	out, code := s6BuildRun(t, src)
	if code != 0 || out != "7\n-1\n" {
		t.Fatalf("out=%q code=%d，期望 \"7\\n-1\\n\" / 0", out, code)
	}
}
