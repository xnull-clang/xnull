// xnast：B2 oracle 工具（Go 侧）。输出 token/AST/诊断的规范文本 v1。
//
// 用法：
//
//	xnast --tokens file.x
//	xnast --ast    file.x
//	xnast --diags  file.x
//
// 输出只依赖源码内容；不写时间戳/路径/环境变量。数据输出即使存在诊断也
// 写 stdout 并退出 0，供差分器比较；文件不可读退出 2。
package main

import (
	"fmt"
	"os"
	"strconv"

	"xnull.dev/xnull/internal/xfront"
)

func main() {
	mode := ""
	path := ""
	dumpDepth := xfront.DefaultDumpDepth
	args := os.Args[1:]
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--tokens", "--ast", "--diags":
			mode = args[i]
		case "--dump-depth":
			if i+1 >= len(args) {
				fmt.Fprintln(os.Stderr, "xnast: --dump-depth 需要整数参数")
				os.Exit(2)
			}
			i++
			n, err := strconv.Atoi(args[i])
			if err != nil || n <= 0 {
				fmt.Fprintf(os.Stderr, "xnast: --dump-depth 非法：%s\n", args[i])
				os.Exit(2)
			}
			dumpDepth = n
		case "-h", "--help":
			fmt.Fprintln(os.Stderr, "用法：xnast [--dump-depth N] --tokens|--ast|--diags <file.x>")
			return
		default:
			path = args[i]
		}
	}
	if mode == "" || path == "" {
		fmt.Fprintln(os.Stderr, "用法：xnast [--dump-depth N] --tokens|--ast|--diags <file.x>")
		os.Exit(2)
	}
	src, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "xnast: %v\n", err)
		os.Exit(2)
	}
	switch mode {
	case "--tokens":
		toks, _ := xfront.Lex(path, string(src))
		fmt.Print(xfront.PrintTokens(toks))
	case "--ast":
		u, _ := xfront.ParseUnit(path, string(src))
		fmt.Println(xfront.PrintUnitPosDepth(u, dumpDepth))
	case "--diags":
		_, ds := xfront.ParseUnit(path, string(src))
		fmt.Print(xfront.PrintDiags(ds))
	}
}
