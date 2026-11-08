package cli

import (
	"bytes"
	"fmt"
	"hash/fnv"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
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
		fmt.Fprintln(env.Stderr, "xnull: 用法：xnull dev <check|ledger|res|board> ...")
		fmt.Fprintln(env.Stderr, "xnull: 用法：xnull dev test [--fast] [--merge] [--shard k/n] [--parallel N] [包...]")
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
	// 所有测试统一走切片并发（AGENTS 测试硬规则 1/2）：
	// 未显式 --shard 时默认 0/4（跑完全部 4 片并聚合），--merge 再保证并发不低于 4。
	shard, parallel = gatePlan(merge, shard, parallel)
	targets := pkgs
	if len(targets) == 0 && fast {
		targets = changedPackages(root)
	}
	if len(targets) == 0 {
		targets = []string{"./..."}
	} else {
		targets = expandPackages(targets)
	}
	return runSharded(env, root, targets, shard, parallel)
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

// gatePlan 落实「所有测试切片并发 + 合并门禁跑完全部 shard」：
// 未指定分片时默认 0/4（全部 4 片并聚合）；--merge 时并发不足 4 抬到 4。
func gatePlan(merge bool, shard string, parallel int) (string, int) {
	if shard == "" {
		shard = "0/4"
	}
	if merge && parallel < 4 {
		parallel = 4
	}
	return shard, parallel
}

// shardOf 用 FNV-1a 哈希把一级测试名稳定映射到 [0,n)。
// 切片只依赖测试名本身：增删其他用例不影响已有用例的归属（AGENTS 测试硬规则 5）。
func shardOf(name string, n int) int {
	h := fnv.New32a()
	_, _ = h.Write([]byte(name))
	return int(h.Sum32() % uint32(n))
}

// listTests 列举目标包的一级测试名（去重、保序）。
func listTests(root string, targets []string) ([]string, error) {
	cmd := exec.Command("go", append([]string{"test", "-list", "^Test"}, targets...)...)
	cmd.Dir = filepath.Join(root, "impl")
	out, err := cmd.Output()
	if err != nil {
		return nil, err
	}
	seen := map[string]bool{}
	var names []string
	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "Test") && !seen[line] {
			seen[line] = true
			names = append(names, line)
		}
	}
	return names, nil
}

// serialTests 读取 handoff/serial-tests.txt：每行一个一级测试名，# 开头为注释。
// 登记在此的用例必须串行执行（并发/GC 压力、固定端口、全局状态），不得默默并发。
func serialTests(root string) map[string]bool {
	mark := make(map[string]bool)
	data, err := os.ReadFile(filepath.Join(root, "handoff", "serial-tests.txt"))
	if err != nil {
		return mark
	}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		mark[line] = true
	}
	return mark
}

// splitTests 按稳定哈希分片；串行标记的用例单独返回，保证只跑一次且不并发。
func splitTests(names []string, n int, serial map[string]bool) ([][]string, []string) {
	shards := make([][]string, n)
	var serialList []string
	for _, name := range names {
		if serial[name] {
			serialList = append(serialList, name)
			continue
		}
		i := shardOf(name, n)
		shards[i] = append(shards[i], name)
	}
	return shards, serialList
}

func runReFor(names []string) string {
	if len(names) == 0 {
		return ""
	}
	quoted := make([]string, len(names))
	for i, name := range names {
		quoted[i] = regexp.QuoteMeta(name)
	}
	return "^(" + strings.Join(quoted, "|") + ")$"
}

// runSharded 按稳定哈希分片；k=0 表示跑全部 1..n 片并聚合（合并门禁口径），
// --parallel 决定同时跑几个分片。串行标记的用例在最后单独串行跑一次。
func runSharded(env Env, root string, targets []string, shard string, parallel int) int {
	var k, n int
	if _, err := fmt.Sscanf(shard, "%d/%d", &k, &n); err != nil || n < 1 || k < 0 || k > n {
		fmt.Fprintf(env.Stderr, "xnull: --shard 需形如 1/4（0/4 表示跑全部；且 0<=k<=n），实际 %q\n", shard)
		return exitcode.Usage
	}
	names, err := listTests(root, targets)
	if err != nil {
		fmt.Fprintf(env.Stderr, "xnull: 列举测试失败：%v\n", err)
		return exitcode.BuildFail
	}
	if len(names) == 0 {
		fmt.Fprintln(env.Stderr, "xnull: 没有可分片的测试")
		return exitcode.BuildFail
	}
	shards, serialList := splitTests(names, n, serialTests(root))
	var jobs []testJob
	for i := 0; i < n; i++ {
		if k != 0 && i != k-1 {
			continue
		}
		jobs = append(jobs, testJob{label: fmt.Sprintf("分片 %d/%d（%d 例）", i+1, n, len(shards[i])), run: runReFor(shards[i])})
	}
	if k == 0 || k == 1 {
		if len(serialList) > 0 {
			jobs = append(jobs, testJob{label: fmt.Sprintf("串行标记（%d 例）", len(serialList)), run: runReFor(serialList), serial: true})
		}
	}
	return runJobs(env, root, targets, jobs, parallel)
}

// runAutoParallel 把目标包的一级测试按 N 片并发跑（每片独立 go test 进程）。
func runAutoParallel(env Env, root string, targets []string, n int) int {
	return runSharded(env, root, targets, "0/"+strconv.Itoa(n), n)
}

// testJob 是一次 go test 调用（一个分片或一组串行用例）。
type testJob struct {
	label  string
	run    string
	serial bool
	out    *safeBuffer
}

// runJobs 以 parallel 并发执行 jobs；串行标记的 job 在其余 job 结束后再跑。
// 任一分片红即整体红（AGENTS 测试硬规则 3）。
func runJobs(env Env, root string, targets []string, jobs []testJob, parallel int) int {
	if parallel < 1 {
		parallel = 1
	}
	if len(jobs) == 0 {
		fmt.Fprintln(env.Stderr, "xnull: 该分片没有用例")
		return exitcode.Success
	}
	failed := false
	// idxs 是 jobs 的下标，避免拷贝 testJob 导致 out 指针丢失。
	runAll := func(idxs []int, workers int) {
		sem := make(chan struct{}, workers)
		var wg sync.WaitGroup
		var mu sync.Mutex
		for _, idx := range idxs {
			jb := &jobs[idx]
			sem <- struct{}{}
			wg.Add(1)
			go func(jb *testJob) {
				defer wg.Done()
				defer func() { <-sem }()
				args := []string{"test", "-count=1", "-timeout", "900s"}
				if jb.run != "" {
					args = append(args, "-run", jb.run)
				}
				args = append(args, targets...)
				cmd := exec.Command("go", args...)
				cmd.Dir = filepath.Join(root, "impl")
				cmd.Stdout = jb.out
				cmd.Stderr = jb.out
				if err := cmd.Run(); err != nil {
					mu.Lock()
					failed = true
					mu.Unlock()
				}
			}(jb)
		}
		wg.Wait()
	}
	for i := range jobs {
		jobs[i].out = &safeBuffer{}
	}
	var concurrent, sequential []int
	for i := range jobs {
		if jobs[i].serial {
			sequential = append(sequential, i)
		} else {
			concurrent = append(concurrent, i)
		}
	}
	runAll(concurrent, parallel)
	runAll(sequential, 1)
	for i := range jobs {
		jb := &jobs[i]
		status := "绿"
		if strings.Contains(jb.out.String(), "\nFAIL") {
			status = "红"
		}
		fmt.Fprintf(env.Stdout, "---- %s：%s ----\n%s", jb.label, status, jb.out.String())
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
