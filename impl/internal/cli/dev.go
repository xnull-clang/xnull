package cli

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"xnull.dev/xnull/internal/devtool"
	"xnull.dev/xnull/internal/exitcode"
)

// runDev 分派内部维护工具：xnull dev check|ledger|res。
//
// 这三项只服务仓库维护，不属于语言用户的稳定 CLI 面，因此收在 dev 之下。
// 输出与退出码需与迁移前的 Python 工具保持一致（B-full 的 golden 合同）：
//   - check / ledger：0 成功、1 存在缺陷或执行失败、2 参数错误；
//   - res：错误一律 2，并以 "gen_resources: " 前缀输出（保持诊断文本一致）。
func runDev(env Env, args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(env.Stderr, "xnull: 用法：xnull dev <check|ledger|res|board|test> ...")
		return exitcode.Usage
	}

	switch args[0] {
	case "test":
		return runDevTest(env, args[1:])

	case "check":
		if len(args) > 2 {
			fmt.Fprintln(env.Stderr, "xnull: 用法：xnull dev check [仓库根]")
			return exitcode.Usage
		}
		root := "."
		if len(args) == 2 {
			root = args[1]
		}
		code, err := devtool.CheckSpecs(root, env.Stdout)
		if err != nil {
			fmt.Fprintf(env.Stderr, "xnull: %v\n", err)
			return exitcode.BuildFail
		}
		return code

	case "ledger":
		if len(args) > 2 {
			fmt.Fprintln(env.Stderr, "xnull: 用法：xnull dev ledger [仓库根]")
			return exitcode.Usage
		}
		root := "."
		if len(args) == 2 {
			root = args[1]
		}
		if err := devtool.GenerateLedger(root, env.Stdout); err != nil {
			fmt.Fprintf(env.Stderr, "xnull: %v\n", err)
			return exitcode.BuildFail
		}
		return exitcode.Success

	case "board":
		// SSOT 看板（ADR-001 §4）：脚本生成，手改即作废。
		var since time.Duration
		var writePath string
		noTest := false
		recordGreen := false
		root := "."
		args := args[1:]
		for i := 0; i < len(args); i++ {
			switch args[i] {
			case "--no-test":
				noTest = true
			case "--record-green":
				recordGreen = true
			case "--write":
				if i+1 >= len(args) {
					fmt.Fprintln(env.Stderr, "xnull: --write 缺少路径")
					return exitcode.Usage
				}
				writePath = args[i+1]
				i++
			case "--since":
				if i+1 >= len(args) {
					fmt.Fprintln(env.Stderr, "xnull: --since 缺少时长（如 168h）")
					return exitcode.Usage
				}
				d, err := time.ParseDuration(args[i+1])
				if err != nil {
					fmt.Fprintf(env.Stderr, "xnull: --since 非法：%v\n", err)
					return exitcode.Usage
				}
				since = d
				i++
			default:
				root = args[i]
			}
		}
		repoRoot, err := devtool.RepoRoot(root)
		if err != nil {
			fmt.Fprintf(env.Stderr, "xnull: %v\n", err)
			return exitcode.BuildFail
		}
		var out io.Writer = env.Stdout
		var f *os.File
		if writePath != "" {
			f, err = os.Create(writePath)
			if err != nil {
				fmt.Fprintf(env.Stderr, "xnull: %v\n", err)
				return exitcode.BuildFail
			}
			defer f.Close()
			out = f
		}
		opts := devtool.BoardOptions{Since: since, RunTests: !noTest, RecordGreen: recordGreen}
		if err := devtool.GenerateBoard(repoRoot, filepath.Join(repoRoot, "impl"), opts, out); err != nil {
			fmt.Fprintf(env.Stderr, "xnull: %v\n", err)
			return exitcode.BuildFail
		}
		return exitcode.Success

	case "res":
		if len(args) != 3 {
			fmt.Fprintln(env.Stderr, "gen_resources: 用法：gen_resources.py <资源目录> <输出.c>")
			return exitcode.Usage
		}
		if err := devtool.GenerateResources(args[1], args[2]); err != nil {
			fmt.Fprintf(env.Stderr, "gen_resources: %v\n", err)
			return exitcode.Usage
		}
		return exitcode.Success

	default:
		fmt.Fprintf(env.Stderr, "xnull: 未知 dev 子命令 %q（可用：check、ledger、res、board）\n", args[0])
		return exitcode.Usage
	}
}

// runDevTest 是 S8-21 的开发期测试入口：
//
//	xnull dev test [--fast] [--merge] [--shard k/n] [--parallel N] [包...]
//
// 不带 --fast 时跑全量（合并门禁口径）；--fast 只跑指定包或相对 main 变更的包。
// --merge 期间持有 handoff/merge.lock（同一时刻只允许一套全量）。
func runDevTest(env Env, args []string) int {
	fast, merge := false, false
	shard := ""
	parallel := 1
	var pkgs []string
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--fast":
			fast = true
		case "--merge":
			merge = true
		case "--shard":
			if i+1 >= len(args) {
				fmt.Fprintln(env.Stderr, "xnull: --shard 缺少 k/n")
				return exitcode.Usage
			}
			shard = args[i+1]
			i++
		case "--parallel":
			if i+1 >= len(args) {
				fmt.Fprintln(env.Stderr, "xnull: --parallel 缺少并发数")
				return exitcode.Usage
			}
			fmt.Sscanf(args[i+1], "%d", &parallel)
			if parallel < 1 {
				parallel = 1
			}
			i++
		default:
			if strings.HasPrefix(args[i], "-") {
				fmt.Fprintf(env.Stderr, "xnull: 未知参数 %s\n", args[i])
				return exitcode.Usage
			}
			pkgs = append(pkgs, args[i])
		}
	}
	root, rerr := devtool.RepoRoot(".")
	if rerr != nil {
		fmt.Fprintf(env.Stderr, "xnull: 不是仓库：%v\n", rerr)
		return exitcode.Usage
	}
	if merge {
		release, lerr := acquireMergeLock(root)
		if lerr != nil {
			fmt.Fprintf(env.Stderr, "xnull: %v\n", lerr)
			return exitcode.BuildFail
		}
		defer release()
	}
	targets := pkgs
	if len(targets) == 0 && fast {
		targets = changedPackages(root)
	}
	if len(targets) == 0 {
		targets = []string{"./..."}
	} else {
		targets = expandPackages(targets)
	}
	if shard != "" {
		return runSharded(env, root, targets, shard, parallel)
	}
	if parallel > 1 {
		return runAutoParallel(env, root, targets, parallel)
	}
	return goTest(env, root, targets, "")
}

func expandPackages(pkgs []string) []string {
	out := make([]string, 0, len(pkgs))
	for _, p := range pkgs {
		if strings.HasPrefix(p, "./") || strings.HasPrefix(p, "xnull.dev/") {
			out = append(out, p)
			continue
		}
		out = append(out, "./internal/"+p)
	}
	return out
}

// changedPackages 返回相对 main 变更的 Go 包（git diff）。
func changedPackages(root string) []string {
	for _, base := range []string{"origin/main...HEAD", "main...HEAD", "HEAD~1...HEAD"} {
		cmd := exec.Command("git", "diff", "--name-only", base)
		cmd.Dir = root
		out, err := cmd.Output()
		if err != nil {
			continue
		}
		seen := map[string]bool{}
		var pkgs []string
		for _, line := range strings.Split(string(out), "\n") {
			line = strings.TrimSpace(line)
			if !strings.HasPrefix(line, "impl/") || !strings.HasSuffix(line, ".go") || strings.HasSuffix(line, "_test.go") {
				continue
			}
			pkg := "./" + filepath.ToSlash(filepath.Dir(strings.TrimPrefix(line, "impl/")))
			if pkg == "./." {
				continue
			}
			if !seen[pkg] {
				seen[pkg] = true
				pkgs = append(pkgs, pkg)
			}
		}
		if len(pkgs) > 0 {
			return pkgs
		}
	}
	return nil
}

func goTest(env Env, root string, targets []string, runRe string) int {
	args := []string{"test", "-count=1", "-timeout", "600s"}
	if runRe != "" {
		args = append(args, "-run", runRe)
	}
	args = append(args, targets...)
	cmd := exec.Command("go", args...)
	cmd.Dir = filepath.Join(root, "impl")
	cmd.Stdout = env.Stdout
	cmd.Stderr = env.Stderr
	fmt.Fprintf(env.Stderr, "xnull: go %s\n", strings.Join(args, " "))
	if err := cmd.Run(); err != nil {
		return exitcode.BuildFail
	}
	return exitcode.Success
}

// runSharded 按一级测试名取模分片；--parallel 同时跑多个分片。
func runSharded(env Env, root string, targets []string, shard string, parallel int) int {
	var k, n int
	if _, err := fmt.Sscanf(shard, "%d/%d", &k, &n); err != nil || n < 1 || k < 1 || k > n {
		fmt.Fprintf(env.Stderr, "xnull: --shard 需形如 1/4（且 1<=k<=n），实际 %q\n", shard)
		return exitcode.Usage
	}
	listCmd := exec.Command("go", append([]string{"test", "-list", "^Test"}, targets...)...)
	listCmd.Dir = filepath.Join(root, "impl")
	out, err := listCmd.Output()
	if err != nil {
		fmt.Fprintf(env.Stderr, "xnull: 列举测试失败：%v\n", err)
		return exitcode.BuildFail
	}
	var names []string
	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "Test") {
			names = append(names, line)
		}
	}
	if len(names) == 0 {
		fmt.Fprintln(env.Stderr, "xnull: 没有可分片的测试")
		return exitcode.BuildFail
	}
	var mine []string
	for i, name := range names {
		if i%n == k-1 {
			mine = append(mine, name)
		}
	}
	if len(mine) == 0 {
		return exitcode.Success
	}
	runRe := "^(" + strings.Join(mine, "|") + ")$"
	return goTest(env, root, targets, runRe)
}

// runAutoParallel 把目标包的一级测试按 N 片并发跑（每片独立 go test 进程）。
func runAutoParallel(env Env, root string, targets []string, n int) int {
	listCmd := exec.Command("go", append([]string{"test", "-list", "^Test"}, targets...)...)
	listCmd.Dir = filepath.Join(root, "impl")
	out, err := listCmd.Output()
	if err != nil {
		fmt.Fprintf(env.Stderr, "xnull: 列举测试失败：%v\n", err)
		return exitcode.BuildFail
	}
	var names []string
	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "Test") {
			names = append(names, line)
		}
	}
	if len(names) == 0 {
		fmt.Fprintln(env.Stderr, "xnull: 没有可并行的测试")
		return exitcode.BuildFail
	}
	if n > len(names) {
		n = len(names)
	}
	type job struct {
		idx int
		run string
		out *safeBuffer
	}
	jobs := make([]*job, n)
	for i := 0; i < n; i++ {
		var mine []string
		for j, name := range names {
			if j%n == i {
				mine = append(mine, name)
			}
		}
		jobs[i] = &job{idx: i, run: "^(" + strings.Join(mine, "|") + ")$", out: &safeBuffer{}}
	}
	var wg sync.WaitGroup
	failed := false
	for _, jb := range jobs {
		wg.Add(1)
		go func(jb *job) {
			defer wg.Done()
			args := []string{"test", "-count=1", "-timeout", "600s", "-run", jb.run}
			args = append(args, targets...)
			cmd := exec.Command("go", args...)
			cmd.Dir = filepath.Join(root, "impl")
			cmd.Stdout = jb.out
			cmd.Stderr = jb.out
			if err := cmd.Run(); err != nil {
				failed = true
			}
		}(jb)
	}
	wg.Wait()
	for _, jb := range jobs {
		fmt.Fprintf(env.Stdout, "---- 并行分片 %d ----\n%s", jb.idx+1, jb.out.String())
	}
	if failed {
		return exitcode.BuildFail
	}
	return exitcode.Success
}

// safeBuffer 是并发安全的输出缓冲。
type safeBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *safeBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

func (b *safeBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.String()
}

// acquireMergeLock 创建 handoff/merge.lock；已存在则失败（合并串行）。
func acquireMergeLock(root string) (func(), error) {
	path := filepath.Join(root, "handoff", "merge.lock")
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, err
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o644)
	if err != nil {
		if os.IsExist(err) {
			holder, _ := os.ReadFile(path)
			return nil, fmt.Errorf("合并锁已被占用（%s）：%s；等前一套全量结束后再试", path, strings.TrimSpace(string(holder)))
		}
		return nil, err
	}
	fmt.Fprintf(f, "pid=%d time=%s\n", os.Getpid(), time.Now().Format(time.RFC3339))
	f.Close()
	return func() { os.Remove(path) }, nil
}
