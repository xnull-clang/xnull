// QA 侧 AST 快照工具（M6/EXP-004）：不入生产树，用 go -overlay 注入 impl/cmd/astdump。
package main

import (
	"fmt"
	"os"

	"xnull.dev/xnull/internal/xfront"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "用法：astdump <file.x>")
		os.Exit(2)
	}
	src, err := os.ReadFile(os.Args[1])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	u, diags := xfront.ParseUnit(os.Args[1], string(src))
	if len(diags) > 0 {
		for _, d := range diags {
			fmt.Fprintln(os.Stderr, d.String())
		}
		os.Exit(1)
	}
	fmt.Print(xfront.PrintUnit(u))
}
