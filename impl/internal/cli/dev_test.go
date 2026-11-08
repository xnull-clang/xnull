package cli

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/exitcode"
)

func TestDevUsage(t *testing.T) {
	cases := []struct {
		name    string
		args    []string
		want    int
		wantErr string
	}{
		{name: "无子命令", args: []string{"dev"}, want: exitcode.Usage, wantErr: "xnull dev <check|ledger|res|board>"},
		{name: "未知子命令", args: []string{"dev", "nope"}, want: exitcode.Usage, wantErr: "未知 dev 子命令"},
		{name: "res 缺参数", args: []string{"dev", "res", "only-one"}, want: exitcode.Usage, wantErr: "gen_resources: 用法"},
		{name: "res 目录不存在", args: []string{"dev", "res", "/nonexistent-res-dir", "/tmp/x.c"}, want: exitcode.Usage, wantErr: "gen_resources: 资源目录不存在"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			code, _, errOut := run(c.args...)
			if code != c.want {
				t.Fatalf("exit = %d, want %d（stderr: %s）", code, c.want, errOut)
			}
			if !strings.Contains(errOut, c.wantErr) {
				t.Fatalf("stderr 缺少 %q：%s", c.wantErr, errOut)
			}
		})
	}
}

func TestDevResGenerates(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "a.txt"), []byte("hello"), 0o644); err != nil {
		t.Fatal(err)
	}
	out := filepath.Join(t.TempDir(), "res.c")
	code, _, errOut := run("dev", "res", dir, out)
	if code != exitcode.Success {
		t.Fatalf("exit = %d, want 0（stderr: %s）", code, errOut)
	}
	data, err := os.ReadFile(out)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), `"a.txt"`) {
		t.Fatalf("生成内容缺少资源：\n%s", data)
	}
}

// S8-21：开发期 --fast 与分片；合并锁互斥。
func devTest(args ...string) (int, string, string) {
	var out, errb bytes.Buffer
	code := runDevTest(Env{Stdout: &out, Stderr: &errb}, args)
	return code, out.String(), errb.String()
}

func TestDevTestFastAndShard(t *testing.T) {
	if code, out, errOut := devTest("--fast", "devtool"); code != exitcode.Success {
		t.Fatalf("--fast devtool 应通过：%s%s", out, errOut)
	}
	if code, out, errOut := devTest("--fast", "--shard", "1/2", "manifest"); code != exitcode.Success {
		t.Fatalf("--shard 1/2 manifest 应通过：%s%s", out, errOut)
	}
	if code, _, _ := devTest("--fast", "--shard", "3/2", "manifest"); code != exitcode.Usage {
		t.Fatalf("非法分片应退出 2，实际 %d", code)
	}
	if code, out, errOut := devTest("--fast", "--parallel", "2", "devtool"); code != exitcode.Success {
		t.Fatalf("--parallel 2 devtool 应通过：%s%s", out, errOut)
	}
	// 合并门禁口径：0/n 跑全部 shard 并聚合，任一红即整体红。
	if code, out, errOut := devTest("--fast", "--shard", "0/2", "manifest"); code != exitcode.Success {
		t.Fatalf("--shard 0/2（全部聚合）manifest 应通过：%s%s", out, errOut)
	}
}

func TestMergeLockExclusive(t *testing.T) {
	root := t.TempDir()
	release, err := acquireMergeLock(root)
	if err != nil {
		t.Fatalf("首次加锁应成功：%v", err)
	}
	if _, err := acquireMergeLock(root); err == nil {
		t.Fatalf("重复加锁应失败")
	}
	release()
	if _, err := acquireMergeLock(root); err != nil {
		t.Fatalf("释放后应可再次加锁：%v", err)
	}
}

// S8-21（测试硬规则 5）：分片必须按测试名稳定哈希，增删其他用例不改变归属。
func TestShardHashStable(t *testing.T) {
	for _, name := range []string{"TestA", "TestS2StructValueCopy", "TestExamplesCompileMatchesInterp"} {
		first := shardOf(name, 4)
		if first != shardOf(name, 4) {
			t.Fatalf("%s 分片不稳定", name)
		}
		if first < 0 || first > 3 {
			t.Fatalf("%s 分片越界：%d", name, first)
		}
	}
	names := []string{"T1", "T2", "T3", "T4", "T5", "T6", "T7"}
	shards, serial := splitTests(names, 3, map[string]bool{"T3": true})
	seen := map[string]int{}
	for _, group := range shards {
		for _, n := range group {
			seen[n]++
		}
	}
	for _, n := range serial {
		seen[n]++
	}
	for _, n := range names {
		if seen[n] != 1 {
			t.Fatalf("%s 出现 %d 次（分片必须不重不漏）", n, seen[n])
		}
	}
	if len(serial) != 1 || serial[0] != "T3" {
		t.Fatalf("串行标记应只包含 T3，实际 %v", serial)
	}
}

// S8-21（测试硬规则 4）：串行用例显式登记在 handoff/serial-tests.txt。
func TestSerialTestsMarkFile(t *testing.T) {
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "handoff"), 0o755); err != nil {
		t.Fatal(err)
	}
	content := "# 并发/端口/全局状态用例\nTestX\n\nTestY\n"
	if err := os.WriteFile(filepath.Join(root, "handoff", "serial-tests.txt"), []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	mark := serialTests(root)
	if !mark["TestX"] || !mark["TestY"] || len(mark) != 2 {
		t.Fatalf("串行标记解析错误：%v", mark)
	}
}

// S8-21（测试硬规则 3）：合并门禁必须跑完全部分片。
func TestGatePlanAllShards(t *testing.T) {
	if shard, par := gatePlan(true, "", 1); shard != "0/4" || par != 4 {
		t.Fatalf("--merge 默认应为 0/4、并发 4，实际 %q/%d", shard, par)
	}
	if shard, par := gatePlan(true, "2/3", 2); shard != "2/3" || par != 4 {
		t.Fatalf("显式分片应保留，并发抬到 4，实际 %q/%d", shard, par)
	}
	if shard, par := gatePlan(false, "", 1); shard != "0/4" || par != 1 {
		t.Fatalf("未指定分片应默认 0/4（全部片跑完并聚合），实际 %q/%d", shard, par)
	}
	if shard, par := gatePlan(false, "3/4", 2); shard != "3/4" || par != 2 {
		t.Fatalf("显式分片与并发应原样保留，实际 %q/%d", shard, par)
	}
}
