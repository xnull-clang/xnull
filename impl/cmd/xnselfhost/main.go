// Command xnselfhost 是 frontbridge 使用的外部自举解释器。
//
// 用法：xnselfhost <program.x> [args...]
// 读取并解析自举程序（xparser.x / xlex.x），然后用解释器执行，程序输出写到 stdout，
// 解释器错误写到 stderr。由 frontbridge 自动构建并缓存，仅用于显式 xnull/auto 前端；
// 默认前端仍是 go。
package main

import (
	"fmt"
	"os"

	"xnull.dev/xnull/internal/interp"
	"xnull.dev/xnull/internal/xfront"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "xnselfhost: 用法：xnselfhost <program.x> [args...]")
		os.Exit(2)
	}
	path := os.Args[1]
	src, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "xnselfhost: 读取 %s：%v\n", path, err)
		os.Exit(2)
	}
	u, ds := xfront.ParseUnit(path, string(src))
	if len(ds) > 0 {
		for _, d := range ds {
			fmt.Fprintln(os.Stderr, d.String())
		}
		os.Exit(1)
	}
	code, err := interp.Run(u, os.Stdout, os.Args[2:])
	if err != nil {
		fmt.Fprintf(os.Stderr, "xnselfhost: %v\n", err)
	}
	os.Exit(code)
}
