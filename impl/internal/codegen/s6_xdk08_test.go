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

// S6 XDK-08：text.xfb 绑定装载 + Regex C 原语端到端（可表达的跨界面）。
func TestS6XDK08TextXfbRegex(t *testing.T) {
	dir := t.TempDir()
	textSrc, err := os.ReadFile(filepath.Join("..", "..", "..", "bindings", "xdk", "text.xfb"))
	if err != nil {
		t.Fatalf("读取 text.xfb：%v", err)
	}
	writeFFIFile(t, filepath.Join(dir, "bindings", "xdk", "text.xfb"), string(textSrc))
	src := `static Int main() {
    print(regexMatch("a+b", "xaab"))
    print(regexMatch("a+b", "xyz"))
    print(regexMatch("[", "a"))
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
	if sd := sema.Analyze(mainPath, u); len(sd) != 0 {
		t.Fatalf("语义诊断：%v", sd)
	}
	csrc, err := EmitCWithFFI(u, reg)
	if err != nil {
		t.Fatalf("EmitCWithFFI: %v", err)
	}
	if !strings.Contains(csrc, "xn_ffi_regexMatch(") {
		t.Fatalf("text.xfb 未生成包装：\n%s", csrc)
	}
	rt := filepath.Join("..", "..", "runtime")
	cfile := filepath.Join(dir, "prog.c")
	writeFFIFile(t, cfile, csrc)
	bin := filepath.Join(dir, "prog")
	resC := writeEmptyResourceTable(t, dir)
	args := []string{"-std=c11", "-O2", "-pthread", "-I", rt, "-o", bin, cfile, resC}
	args = append(args, runtimeLib(t))
	var cerr bytes.Buffer
	cc := exec.Command("cc", args...)
	cc.Stderr = &cerr
	if err := cc.Run(); err != nil {
		t.Fatalf("cc 失败：%v\n%s", err, cerr.String())
	}
	var out bytes.Buffer
	run := exec.Command(bin)
	run.Stdout = &out
	if err := run.Run(); err != nil {
		t.Fatalf("运行失败：%v（stdout=%q）", err, out.String())
	}
	if want := "0\n1\n2\n"; out.String() != want {
		t.Fatalf("stdout=%q，期望 %q", out.String(), want)
	}
}
