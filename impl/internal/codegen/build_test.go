package codegen

import (
	"bytes"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// runtimeDirForTest 返回仓库内的 impl/runtime 绝对路径（测试 cwd = impl/internal/codegen）。
func runtimeDirForTest(t *testing.T) string {
	t.Helper()
	dir, err := filepath.Abs(filepath.Join("..", "..", "runtime"))
	if err != nil {
		t.Fatal(err)
	}
	return dir
}

// M6-B0-02（P-10）：C 编译清单必须纳入 xrt_abi.c 与 rt_std_*.c，且顺序固定。
func TestBuildCCArgsIncludesRuntimeABIAndStd(t *testing.T) {
	const rt = "/RT"
	got := buildCCArgs("prog", "prog.c", rt, nil)
	want := []string{
		"-std=c11", "-O2", "-pthread", "-I", rt, "-o", "prog", "prog.c",
		filepath.Join(rt, "rt.c"),
		filepath.Join(rt, "rt_gc.c"),
		filepath.Join(rt, "rt_policy.c"),
		filepath.Join(rt, "rt_weak.c"),
		filepath.Join(rt, "xrt_abi.c"),
		filepath.Join(rt, "rt_std_runtime.c"),
		filepath.Join(rt, "rt_std_text.c"),
		filepath.Join(rt, "rt_std_sys.c"),
		filepath.Join(rt, "rt_std_bytes.c"),
		filepath.Join(rt, "rt_task.c"),
		filepath.Join(rt, "rt_sync.c"),
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("cc 参数不符（P-10 要求 xrt_abi.c + rt_std_*.c）\n got: %v\nwant: %v", got, want)
	}
}

// P-10 条件 3：LinkArgs 追加在全部目标文件之后（链接顺序敏感）。
func TestBuildCCArgsAppendsLinkArgsLast(t *testing.T) {
	const rt = "/RT"
	link := []string{"-lm", "-lz"}
	got := buildCCArgs("prog", "prog.c", rt, link)

	if len(got) < 2 || got[len(got)-2] != "-lm" || got[len(got)-1] != "-lz" {
		t.Fatalf("LinkArgs 未按序追加到末尾：%v", got)
	}
	lastObj := -1
	for i, a := range got {
		if strings.HasSuffix(a, ".c") {
			lastObj = i
		}
	}
	for _, la := range link {
		idx := -1
		for i, a := range got {
			if a == la {
				idx = i
			}
		}
		if idx <= lastObj {
			t.Fatalf("%s 必须位于全部目标文件之后（last .c = %d, idx = %d）：%v", la, lastObj, idx, got)
		}
	}
}

// 端到端样例：真实运行时目录 + LinkArgs，编译并运行 examples/hello.x。
func TestBuildSampleHelloWithLinkArgs(t *testing.T) {
	rt := runtimeDirForTest(t)
	out := filepath.Join(t.TempDir(), "hello")
	var errBuf bytes.Buffer

	code := BuildWithOptions(filepath.Join("..", "..", "..", "examples", "hello.x"),
		out, rt, Options{LinkArgs: []string{"-lm"}}, &errBuf)
	if code != 0 {
		t.Fatalf("BuildWithOptions 失败（code=%d）：%s", code, errBuf.String())
	}

	cmd := exec.Command(out)
	cmd.Env = nil
	var stdout bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &errBuf
	if err := cmd.Run(); err != nil {
		t.Fatalf("运行样例失败：%v（stderr: %s）", err, errBuf.String())
	}
	const want = "hello, XNull\n1 + 2 = 3\n"
	if stdout.String() != want {
		t.Fatalf("样例输出不符：%q（want %q）", stdout.String(), want)
	}
}
