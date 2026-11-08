package cli

import (
	"fmt"
	"os"
	"path/filepath"

	"xnull.dev/xnull/internal/exitcode"
	"xnull.dev/xnull/internal/manifest"
)

// runLock 实现 S8-03：`xnull lock [--update-lock] [工程目录]`。
// 默认只校验（锁缺失/不一致即失败）；--update-lock 是唯一重生成入口。
func runLock(env Env, args []string) int {
	update := false
	dir := "."
	for _, a := range args {
		if a == "--update-lock" {
			update = true
			continue
		}
		dir = a
	}
	root := findManifestRoot(dir)
	if root == "" {
		fmt.Fprintf(env.Stderr, "xnull: 找不到 xnull.project（从 %s 向上）\n", dir)
		return exitcode.Usage
	}
	project := filepath.Join(root, "xnull.project")
	res, diags, err := manifest.ResolveDependencies(project, manifest.Options{ToolchainVersion: Version})
	if err != nil {
		fmt.Fprintf(env.Stderr, "xnull: %v\n", err)
		return exitcode.BuildFail
	}
	if len(diags) > 0 {
		for _, d := range diags {
			fmt.Fprintln(env.Stderr, d.String())
		}
		return 1
	}
	repo := os.Getenv("XNULL_REPO")
	graph, gds := manifest.ResolveGraph(res, repo)
	if len(gds) > 0 {
		for _, d := range gds {
			fmt.Fprintln(env.Stderr, d.String())
		}
		return 1
	}
	lockPath := filepath.Join(root, "xnull.lock")

	if update {
		var prev *manifest.Lock
		if l, ds, lerr := manifest.LoadLock(lockPath); lerr == nil && len(ds) == 0 {
			prev = l
		}
		lock, genDs := manifest.GenerateLockForGraph(res, graph, repo, prev)
		if len(genDs) > 0 {
			for _, d := range genDs {
				fmt.Fprintln(env.Stderr, d.String())
			}
			return 1
		}
		if werr := manifest.WriteLock(lockPath, lock); werr != nil {
			fmt.Fprintf(env.Stderr, "xnull: 写锁失败：%v\n", werr)
			return exitcode.BuildFail
		}
		fmt.Fprintf(env.Stdout, "已生成 %s：%d 条\n", lockPath, len(lock.Entries))
		for _, w := range res.Warnings {
			fmt.Fprintf(env.Stderr, "xnull: 警告：%s\n", w)
		}
		return exitcode.Success
	}

	lock, lds, lerr := manifest.LoadLock(lockPath)
	if lerr != nil {
		if os.IsNotExist(lerr) {
			fmt.Fprintf(env.Stderr, "xnull: 缺锁文件 %s；用 --update-lock 生成（S8 §4.4）\n", lockPath)
			return 1
		}
		fmt.Fprintf(env.Stderr, "xnull: 读锁失败：%v\n", lerr)
		return exitcode.BuildFail
	}
	if len(lds) > 0 {
		for _, d := range lds {
			fmt.Fprintln(env.Stderr, d.String())
		}
		return 1
	}
	if ds := manifest.ValidateLockForGraph(lock, graph, repo); len(ds) > 0 {
		for _, d := range ds {
			fmt.Fprintln(env.Stderr, d.String())
		}
		return 1
	}
	fmt.Fprintf(env.Stdout, "锁有效：%s（%d 条）\n", lockPath, len(lock.Entries))
	return exitcode.Success
}
