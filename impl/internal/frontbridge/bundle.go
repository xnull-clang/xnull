// B3-08b：输出多文件 import 闭包的 AST bundle（只读，不参与代码生成）。
package frontbridge

import (
	"os"
	"path/filepath"
	"runtime"

	"xnull.dev/xnull/internal/diag"
	"xnull.dev/xnull/internal/xfront"
)

// BundleFile 是一个依赖文件的 AST 文本。
type BundleFile struct {
	Path string `json:"path"` // 绝对路径（消费方可自行转相对）
	AST  string `json:"ast"`  // xnast v1 文本（xfront.PrintUnitPos）
}

// ASTBundle 按 LoadUnits 的依赖后序返回入口及其全部 import 闭包的 AST。
// 规则与 codegen.LoadUnits 一致：xdk.<pkg> 装载 impl/lib/xdk/<pkg>.x（存在时）；
// 其他点分导入映射为同目录相对路径 .x；依赖先于使用方，入口最后。
func ASTBundle(entry string) ([]BundleFile, []diag.Diagnostic) {
	var out []BundleFile
	var diags []diag.Diagnostic
	entryDir := filepath.Dir(filepath.Clean(entry))
	state := map[string]int{} // 0 未访问 / 1 访问中 / 2 完成
	var visit func(path string) bool
	visit = func(path string) bool {
		abs := filepath.Clean(path)
		if st, ok := state[abs]; ok {
			if st == 1 {
				diags = append(diags, diag.Diagnostic{
					File: path, Line: 1, Col: 1, Code: "B3-001",
					Message: "AST bundle：import 图存在环",
				})
				return false
			}
			return true
		}
		state[abs] = 1
		src, err := os.ReadFile(abs)
		if err != nil {
			diags = append(diags, diag.Diagnostic{
				File: path, Line: 1, Col: 1, Code: "B3-002",
				Message: "AST bundle：找不到源文件 " + abs,
			})
			state[abs] = 2
			return false
		}
		u, pd := ParseUnit(abs, string(src))
		diags = append(diags, pd...)
		if len(pd) > 0 || u == nil {
			state[abs] = 2
			return false
		}
		okAll := true
		for _, imp := range u.Imports {
			if len(imp.Path) == 0 {
				continue
			}
			if imp.Path[0] == "xdk" {
				if len(imp.Path) >= 2 {
					dep := filepath.Join(xdkLibDirFB(), imp.Path[1]+".x")
					if _, err := os.Stat(dep); err == nil {
						if !visit(dep) {
							okAll = false
						}
					}
				}
				continue
			}
			dep := filepath.Join(entryDir, filepath.Join(imp.Path...)+".x")
			if !visit(dep) {
				okAll = false
			}
		}
		state[abs] = 2
		out = append(out, BundleFile{Path: abs, AST: xfront.PrintUnitPos(u)})
		return okAll
	}
	visit(entry)
	return out, diags
}

func xdkLibDirFB() string {
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		return filepath.Join("lib", "xdk")
	}
	return filepath.Clean(filepath.Join(filepath.Dir(file), "..", "..", "lib", "xdk"))
}
