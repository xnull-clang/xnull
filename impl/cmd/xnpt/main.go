// xnpt：解析对照工具（M5.1-c）。
// 对给定的表达式串，用 xfront 解析器解析后按 PrintExpr 输出 S 表达式，
// 与 examples/parser-seed.x（XNull 版 Pratt 解析器）同输入对照。
// 用法：xnpt "1 + 2 * 3" "(1 + 2) * 3" ...
package main

import (
	"fmt"
	"os"

	"xnull.dev/xnull/internal/xfront"
)

func main() {
	src := "static Int main() {\n"
	for _, e := range os.Args[1:] {
		src += "    dump(" + e + ");\n"
	}
	src += "    return 0;\n}\nstatic void dump(Int _) {}\n"
	u, diags := xfront.ParseUnit("xnpt.x", src)
	if len(diags) > 0 {
		for _, d := range diags {
			fmt.Fprintln(os.Stderr, d.String())
		}
		os.Exit(1)
	}
	for _, d := range u.Decls {
		fn, ok := d.(*xfront.TopFunc)
		if !ok || fn.Name != "main" {
			continue
		}
		for _, st := range fn.Body.Stmts {
			ret, ok := st.(*xfront.ExprStmt)
			if !ok {
				continue
			}
			call, ok := ret.X.(*xfront.Call)
			if !ok || len(call.Args) != 1 {
				continue
			}
			fmt.Println(xfront.PrintExpr(call.Args[0]))
		}
	}
}
