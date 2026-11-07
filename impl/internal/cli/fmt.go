package cli

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"xnull.dev/xnull/internal/exitcode"
	"xnull.dev/xnull/internal/xpd"
)

// S8-10：xnull fmt 的清单/锁/元数据格式化面。
// 默认原地写；--check 只比较并以非零退出表示“需要格式化”。
func runFmt(env Env, rest []string) int {
	check := hasFlag(rest, "--check")
	var paths []string
	for _, a := range rest {
		if strings.HasPrefix(a, "-") {
			continue
		}
		paths = append(paths, a)
	}
	if len(paths) == 0 {
		for _, p := range []string{"xnull.project", "xnull.lock"} {
			if _, err := os.Stat(p); err == nil {
				paths = append(paths, p)
			}
		}
		for _, pat := range []string{"*.xmeta", filepath.Join("target", "*.xmeta")} {
			if ms, _ := filepath.Glob(pat); len(ms) > 0 {
				paths = append(paths, ms...)
			}
		}
	}
	if len(paths) == 0 {
		fmt.Fprintln(env.Stderr, "xnull: fmt 需要 xnull.project / xnull.lock / *.xmeta，或显式文件路径")
		return exitcode.Usage
	}
	failed := false
	for _, p := range paths {
		src, err := os.ReadFile(p)
		if err != nil {
			fmt.Fprintf(env.Stderr, "xnull: 无法读取 %s：%v\n", p, err)
			failed = true
			continue
		}
		out, ds := xpd.FormatSource(p, string(src))
		if len(ds) > 0 {
			for _, d := range ds {
				fmt.Fprintln(env.Stderr, d.String())
			}
			failed = true
			continue
		}
		if out == string(src) {
			continue
		}
		if check {
			fmt.Fprintf(env.Stderr, "xnull: 需要格式化 %s（xnull fmt --write）\n", p)
			failed = true
			continue
		}
		if err := os.WriteFile(p, []byte(out), 0o644); err != nil {
			fmt.Fprintf(env.Stderr, "xnull: 无法写入 %s：%v\n", p, err)
			failed = true
		}
	}
	if failed {
		return exitcode.BuildFail
	}
	return exitcode.Success
}
