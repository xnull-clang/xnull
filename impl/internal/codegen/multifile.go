package codegen

import (
	"os"
	"path/filepath"
	"strings"

	"xnull.dev/xnull/internal/diag"
	"xnull.dev/xnull/internal/xfront"
)

// 多文件编译单元（S1 §3.2/§3.4；M5.2 前置）。
//
// 加载规则（起步形态，细化路径解析归后续工程清单批次）：
//   - `import p1.p2.…pn` 映射为 entry 所在目录下的相对文件 p1/p2/…/pn.xn；
//   - `xdk.*` 导入由 sema 处理，加载器不解析为文件；
//   - 包导入图必须无环（§3.4），检测到环即编译错误；
//   - 同一文件只加载一次（重复导入允许，§3.2）；
//   - 合并顺序＝依赖优先的后序（确定性：同一 import 列表按源码书写顺序，
//     不依赖文件系统枚举顺序）。

// 多文件加载诊断码（续 RES-1xx 导入族；规范 §3.5 列明情形，码值由实现分配）。
const (
	codeImportCycle     = "RES-108" // 包导入环（§3.4）
	codeMultiPackage    = "RES-109" // 跨包导入未支持（多包编译属工程清单批次）
	codeImportFileMiss  = "RES-106" // 包或符号不存在（§3.5）——复用导入族既有码
	codeSubFileNotNamed = "RES-110" // 子文件缺少 package 声明（默认包不可跨包导入，§3.3）
)

// LoadUnits 从 entry 出发解析 import 依赖并返回合并后的编译单元。
// 返回单元的 Decls 顺序＝依赖先、入口最后；诊断按发现顺序返回。
func LoadUnits(entryPath string) (*xfront.CompilationUnit, []diag.Diagnostic) {
	dir := filepath.Dir(entryPath)
	base := filepath.Base(entryPath)

	var diags []diag.Diagnostic
	state := map[string]int{} // 0 未访问 / 1 访问中 / 2 已完成
	units := map[string]*xfront.CompilationUnit{}
	var order []string // 后序：依赖在前

	var visit func(path, from string) bool
	visit = func(path, from string) bool {
		abs := path
		if st, ok := state[abs]; ok {
			if st == 1 {
				// 环：从当前栈中回到访问中的节点
				diags = append(diags, diag.Diagnostic{
					File: from, Line: 1, Col: 1, Code: codeImportCycle,
					Message: "包导入图存在环（§3.4）：" + relName(dir, abs) + " 已被当前导入链引用",
					Hint:    "拆出公共依赖文件，消除互相 import",
				})
				return false
			}
			return true
		}
		state[abs] = 1
		src, err := os.ReadFile(path)
		if err != nil {
			diags = append(diags, diag.Diagnostic{
				File: from, Line: 1, Col: 1, Code: codeImportFileMiss,
				Message: "找不到包文件 " + relName(dir, abs) + "（import 点分路径映射为同目录相对路径 .xn）",
				Hint:    "确认文件名与 import 路径一致，或改用已存在的包",
			})
			state[abs] = 2
			return false
		}
		u, pd := xfront.ParseUnit(path, string(src))
		diags = append(diags, pd...)
		if len(pd) > 0 {
			state[abs] = 2
			return false
		}
		units[abs] = u
		okAll := true
		for _, imp := range u.Imports {
			if len(imp.Path) == 0 || imp.Path[0] == "xdk" {
				continue
			}
			dep := filepath.Join(dir, filepath.Join(imp.Path...)+".xn")
			if !visit(dep, path) {
				okAll = false
			}
		}
		state[abs] = 2
		order = append(order, abs)
		return okAll
	}
	visit(entryPath, entryPath)

	if len(diags) > 0 {
		return nil, diags
	}

	entry := units[filepath.Clean(entryPath)]
	if entry == nil {
		return nil, []diag.Diagnostic{{
			File: entryPath, Line: 1, Col: 1, Code: codeImportFileMiss,
			Message: "无法读取入口文件 " + base,
		}}
	}

	merged := &xfront.CompilationUnit{P: entry.P, Package: entry.Package}
	// import 合并去重（同一 path+alias 只保留一份；§3.2 重复导入允许）
	seenImp := map[string]bool{}
	for _, abs := range order {
		u := units[abs]
		for _, imp := range u.Imports {
			key := strings.Join(imp.Path, ".") + "|" + imp.Alias
			if seenImp[key] {
				continue
			}
			seenImp[key] = true
			merged.Imports = append(merged.Imports, imp)
		}
	}
	// 包一致性：多包编译（§3.4 类型带包前缀）属工程清单批次；本次要求同包。
	for _, abs := range order {
		u := units[abs]
		if abs == filepath.Clean(entryPath) {
			continue
		}
		if entry.Package == nil && u.Package == nil {
			// 默认包跨文件组合是当前起步形态：视为同一编译单元的多个分片
			continue
		}
		if entry.Package == nil || u.Package == nil ||
			strings.Join(entry.Package.Name, ".") != strings.Join(u.Package.Name, ".") {
			diags = append(diags, diag.Diagnostic{
				File: abs, Line: 1, Col: 1, Code: codeMultiPackage,
				Message: "跨包导入暂不支持：子文件包名必须与入口一致（§3.4 多包编译属工程清单批次）",
				Hint:    "统一 package 声明，或等待多包编译切片",
			})
		}
	}
	if len(diags) > 0 {
		return nil, diags
	}

	for _, abs := range order {
		merged.Decls = append(merged.Decls, units[abs].Decls...)
	}
	return merged, nil
}

// relName 生成相对 entry 目录的展示名（诊断友好）。
func relName(dir, abs string) string {
	if rel, err := filepath.Rel(dir, abs); err == nil {
		return rel
	}
	return abs
}
