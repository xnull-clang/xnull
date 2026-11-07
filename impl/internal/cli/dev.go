package cli

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
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
		return exitcode.Usage
	}

	switch args[0] {
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
		root := "."
		args := args[1:]
		for i := 0; i < len(args); i++ {
			switch args[i] {
			case "--no-test":
				noTest = true
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
		opts := devtool.BoardOptions{Since: since, RunTests: !noTest}
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
