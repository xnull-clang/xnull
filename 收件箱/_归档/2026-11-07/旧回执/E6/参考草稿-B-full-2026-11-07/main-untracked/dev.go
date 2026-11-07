package cli

import (
	"fmt"

	"xnull.dev/xnull/internal/devtool"
	"xnull.dev/xnull/internal/exitcode"
)

// runDev 分派内部维护工具：xnull dev check|ledger|res。
//
// 这些命令只服务仓库维护，不属于语言用户的稳定 CLI 面；
// 放在 dev 子命令下，避免与 S9 定义的构建命令混在一起。
func runDev(env Env, args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(env.Stderr, "xnull: 用法：xnull dev <check|ledger|res> ...")
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
			return exitcode.Usage
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

	case "res":
		if len(args) != 3 {
			fmt.Fprintln(env.Stderr, "xnull: 用法：xnull dev res <资源目录> <输出.c>")
			return exitcode.Usage
		}
		if err := devtool.GenerateResources(args[1], args[2]); err != nil {
			fmt.Fprintf(env.Stderr, "xnull: %v\n", err)
			return exitcode.BuildFail
		}
		return exitcode.Success

	default:
		fmt.Fprintf(env.Stderr, "xnull: 未知 dev 子命令 %q（可用：check、ledger、res）\n", args[0])
		return exitcode.Usage
	}
}
