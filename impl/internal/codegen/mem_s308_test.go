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

// S3-08：§23 的 GC 策略选择（auto/arc/gc）——arc/gc 强制全部类的分配种类。
func TestS3_08MemPolicyOverride(t *testing.T) {
	src := `
class Node { Node next; }
class Plain { Int x = 1; }
static Int main() { Node n = new Node(); Plain p = new Plain(); n.next = n; return p.x }`
	u, diags := xfront.ParseUnit("t.x", src)
	if len(diags) != 0 {
		t.Fatalf("解析诊断：%v", diags)
	}
	res, sd := sema.AnalyzeWith("t.x", u)
	if len(sd) != 0 {
		t.Fatalf("语义诊断：%v", sd)
	}
	strats := res.Strategies(u)

	arcC, err := EmitCWithBuildOptions(u, nil, strats, Options{MemPolicy: "arc"})
	if err != nil {
		t.Fatalf("arc 选项代码生成失败：%v", err)
	}
	if !strings.Contains(arcC, "rt_arc_new(&RT_TYPE_XN_Node)") {
		t.Fatalf("--mem=arc 下环类应为 ARC")
	}
	if strings.Contains(arcC, "xn_gc_new(&RT_TYPE_XN_Node)") {
		t.Fatalf("--mem=arc 下不得出现 GC 分配")
	}

	gcC, err := EmitCWithBuildOptions(u, nil, strats, Options{MemPolicy: "gc"})
	if err != nil {
		t.Fatalf("gc 选项代码生成失败：%v", err)
	}
	if !strings.Contains(gcC, "xn_gc_new(&RT_TYPE_XN_Plain)") {
		t.Fatalf("--mem=gc 下非环类也应为 GC")
	}
}

// S3-08：Stats 选项在生成代码中打开统计并输出报告。
func TestS3_08StatsEmission(t *testing.T) {
	src := `
class C { Int x = 1; }
static Int main() { C c = new C(); return c.x }`
	u, diags := xfront.ParseUnit("t.x", src)
	if len(diags) != 0 {
		t.Fatalf("解析诊断：%v", diags)
	}
	res, sd := sema.AnalyzeWith("t.x", u)
	if len(sd) != 0 {
		t.Fatalf("语义诊断：%v", sd)
	}
	csrc, err := EmitCWithBuildOptions(u, nil, res.Strategies(u), Options{Stats: true})
	if err != nil {
		t.Fatalf("代码生成失败：%v", err)
	}
	for _, sym := range []string{"xrt_stats_reset", "xrt_stats_set_enabled", "xrt_stats_report"} {
		if !strings.Contains(csrc, sym) {
			t.Fatalf("--stats 生成代码缺少 %q", sym)
		}
	}
}

// S3-08：--stats 运行期输出分配/GC 指标（stderr），且程序行为不变。
func TestS3_08StatsRun(t *testing.T) {
	src := `
class C { Int x = 1; }
static Int main() { C c = new C(); print(c.x); return 0 }`
	u, diags := xfront.ParseUnit("t.x", src)
	if len(diags) != 0 {
		t.Fatalf("解析诊断：%v", diags)
	}
	res, sd := sema.AnalyzeWith("t.x", u)
	if len(sd) != 0 {
		t.Fatalf("语义诊断：%v", sd)
	}
	csrc, err := EmitCWithBuildOptions(u, nil, res.Strategies(u), Options{Stats: true})
	if err != nil {
		t.Fatalf("代码生成失败：%v", err)
	}
	dir := t.TempDir()
	cfile := filepath.Join(dir, "prog.c")
	if err := os.WriteFile(cfile, []byte(csrc), 0o644); err != nil {
		t.Fatal(err)
	}
	bin := filepath.Join(dir, "prog")
	cc := exec.Command("cc", "-std=c11", "-I", "../../../impl/runtime", "-O2", "-o", bin,
		cfile, "../../../impl/runtime/rt.c", "../../../impl/runtime/rt_gc.c",
		"../../../impl/runtime/rt_policy.c", "../../../impl/runtime/rt_weak.c",
		"../../../impl/runtime/xrt_abi.c")
	var ccerr bytes.Buffer
	cc.Stderr = &ccerr
	if err := cc.Run(); err != nil {
		t.Fatalf("cc 失败：%v\n%s", err, ccerr.String())
	}
	var out, errb bytes.Buffer
	run := exec.Command(bin)
	run.Stdout = &out
	run.Stderr = &errb
	if err := run.Run(); err != nil {
		t.Fatalf("运行失败：%v\n%s", err, errb.String())
	}
	if out.String() != "1\n" {
		t.Fatalf("stdout=%q，期望 1", out.String())
	}
	if !strings.Contains(errb.String(), "xrt stats:") {
		t.Fatalf("stderr 缺少统计报告：%q", errb.String())
	}
}
