package sema

import (
	"strings"

	"xnull.dev/xnull/internal/xfront"
)

// ---------- M2-A 收尾：XDK 包符号表与导入诊断（S1 §3.2/§3.5 + S6 §2/§4） ----------
//
// 诊断码段位（本文件启用）：
//   RES-103 导入别名冲突（§3.5）
//   RES-104 未消歧的简单名（§3.5）
//   RES-105 XDK 包未显式导入（§3.5）
//   RES-106 包或符号不存在（§3.5）
//   RES-107 非冲突场景使用 as 别名（§3.5）
//
// 标注（PKG-01 剩余项）：导入环与默认包符号跨包导入需要多包编译单元
// （工程清单模式），属多包切片；private/protected 泄漏由"符号不存在"兜底
// （注册表只登记公开 API，S6 §3 合同原则）。

// 诊断码。
const (
	ResAliasConflict = "RES-103" // 导入别名冲突（§3.5）
	ResAmbiguousName = "RES-104" // 未消歧的简单名（§3.5）
	ResXdkNotImport  = "RES-105" // XDK 包未显式导入（§3.5）
	ResNotFound      = "RES-106" // 包或符号不存在（§3.5）
	ResNeedlessAlias = "RES-107" // 非冲突场景使用 as 别名（§3.5）
)

// xdkPackages 是 XDK 包 → 导出符号集（S6 §2 包结构 + §4 逐包合同定案符号）。
// 只登记 S6 定案的公开 API；未定案名称不猜（实现层立项后追加，属次版本流程）。
var xdkPackages = map[string]map[string]bool{
	"errors": {
		"Error": true, "ErrorKind": true, "wrap": true, "mapErr": true, "report": true,
	},
	"tasks": {
		"Task": true, "TaskGroup": true, "Context": true,
	},
	"sync": {
		"Mutex": true, "Channel": true, "AtomicInt": true, "AtomicBool": true, "AtomicRef": true,
	},
	"runtime": {
		"diagnose": true, "exit": true, "nowMono": true, "nowWall": true, "env": true, "dumpTasks": true,
	},
	"collections": {
		// 内建容器（List/Map/Set/StringBuilder）属 S1 §9，不在本包；此处是特化容器（S6 §4.5 定案）
		"RingBuffer": true, "OrderedMap": true, "BTreeMap": true, "PriorityQueue": true,
	},
	"text": {
		"Regex": true, // S6 §4.6 定案符号；builder 式格式化类型名随实现层立项冻结
	},
	"sys": {
		"resourceExists": true, "readResource": true, "readResourceText": true,
		"listResources": true, "resourceSize": true,
	},
	"net": {}, // S6 §4.7 定案独立成包；符号随实现层立项冻结（包存在性可用）
}

// xdkSymbolKnown 判断名称是否为某个 XDK 包的导出符号（用于 RES-105）。
func xdkSymbolKnown(name string) bool {
	for _, syms := range xdkPackages {
		if syms[name] {
			return true
		}
	}
	return false
}

// xdkExporters 返回导出该符号的全部 XDK 包名（用于歧义判定）。
func xdkExporters(name string) []string {
	var pkgs []string
	for pkg, syms := range xdkPackages {
		if syms[name] {
			pkgs = append(pkgs, pkg)
		}
	}
	return pkgs
}

// importInfo 记录一个导入的展开结果。
type importInfo struct {
	p     xfront.Pos
	path  []string
	alias string
	syms  []string // 包导入时为该包全部导出符号；符号导入时为单符号
}

// analyzeImports 处理导入：存在性、别名规则、简单名歧义、XDK 未导入检查基础。
func (a *analyzer) analyzeImports(u *xfront.CompilationUnit) {
	var imports []importInfo
	aliasOwners := map[string]string{} // 别名 → 来源描述（别名冲突检测）
	for _, imp := range u.Imports {
		p := imp.Path
		if len(p) == 0 {
			continue
		}
		info := importInfo{p: imp.P, path: p, alias: imp.Alias}
		if p[0] == "xdk" {
			if len(p) < 2 {
				continue
			}
			pkg := p[1]
			syms, known := xdkPackages[pkg]
			if !known {
				a.errf(imp.P, ResNotFound, "未知的 XDK 包 `"+strings.Join(p, ".")+"`（S6 §2 包结构）",
					"可用包：errors/tasks/sync/runtime/collections/text/sys/net")
				continue
			}
			if len(p) == 3 { // 符号导入
				sym := p[2]
				if !syms[sym] {
					a.errf(imp.P, ResNotFound, "XDK 包 `xdk."+pkg+"` 没有导出符号 `"+sym+"`（§3.5）",
						"检查符号名或改用包导入")
					continue
				}
				info.syms = []string{sym}
			} else { // 包导入：全部导出符号可见（§3.2）
				for s := range syms {
					info.syms = append(info.syms, s)
				}
			}
		} else {
			// 用户包：多包符号表属多包切片；此处只登记（存在性检查待工程清单）
			a.hasImp = true
			imports = append(imports, info)
			continue
		}
		a.hasImp = true
		imports = append(imports, info)
	}
	// 别名与简单名规则（§3.5）。
	visible := map[string][]string{} // 简单名 → 来源列表
	srcPos := map[string]xfront.Pos{}
	for _, imp := range imports {
		if len(imp.path) < 2 {
			continue
		}
		src := strings.Join(imp.path, ".")
		if imp.alias != "" {
			if prev, dup := aliasOwners[imp.alias]; dup {
				a.errf(imp.p, ResAliasConflict, "导入别名 `"+imp.alias+"` 冲突（已由 `"+prev+"` 使用）（§3.5）", "换一个别名")
				continue
			}
			aliasOwners[imp.alias] = src
			// 非冲突场景使用 as：被导符号来源唯一且无同名符号时，别名即非消歧
			if len(imp.syms) == 1 {
				sym := imp.syms[0]
				other := 0
				for _, o := range imports {
					for _, s := range o.syms {
						if s == sym {
							other++
						}
					}
				}
				if other <= 1 {
					a.errf(imp.p, ResNeedlessAlias,
						"`"+sym+"` 无同名歧义，as 别名只用于消歧（§3.5）", "去掉 as 子句")
				}
			}
			a.imported[imp.alias] = true
			continue
		}
		for _, s := range imp.syms {
			visible[s] = append(visible[s], src)
			if _, ok := srcPos[s]; !ok {
				srcPos[s] = imp.p
			}
		}
	}
	// 未消歧的简单名：同名符号来自多个包且未用别名（§3.5）。
	for name, srcs := range visible {
		if len(srcs) > 1 {
			a.ambiguous[name] = true
			a.errf(srcPos[name], ResAmbiguousName,
				"简单名 `"+name+"` 在多个来源间歧义（"+strings.Join(srcs, "、")+"），必须用 as 消歧（§3.5）",
				"为其中一个导入加 as 别名")
		} else {
			a.imported[name] = true
		}
	}
}

// checkTypeXdkUse 检查类型位置上的 XDK 符号是否已导入（§3.5）。
func (a *analyzer) checkTypeXdkUse(t xfront.TypeRef) {
	if t == nil {
		return
	}
	switch ty := t.(type) {
	case *xfront.NamedType:
		if len(ty.Qual) == 1 && xdkSymbolKnown(ty.Qual[0]) && !a.imported[ty.Qual[0]] {
			var pkgs []string
			for _, pkg := range xdkExporters(ty.Qual[0]) {
				pkgs = append(pkgs, "xdk."+pkg)
			}
			a.errf(ty.P, ResXdkNotImport, "XDK 符号 `"+ty.Qual[0]+"` 未显式导入（定义于 "+strings.Join(pkgs, "、")+"）（§3.5）",
				"在使用文件顶部添加 import")
		}
		for _, arg := range ty.Args {
			a.checkTypeXdkUse(arg)
		}
	case *xfront.SuffixedType:
		a.checkTypeXdkUse(ty.Base)
	case *xfront.FuncTypeRef:
		a.checkTypeXdkUse(ty.Ret)
		for _, p := range ty.Params {
			a.checkTypeXdkUse(p)
		}
	case *xfront.TupleTypeRef:
		for _, el := range ty.Elems {
			a.checkTypeXdkUse(el)
		}
	}
}

// checkXdkUse 对未定义名称做 XDK 未导入检查（§3.5）。
func (a *analyzer) checkXdkUse(p xfront.Pos, name string) {
	if xdkSymbolKnown(name) && !a.imported[name] {
		var pkgs []string
		for _, pkg := range xdkExporters(name) {
			pkgs = append(pkgs, "xdk."+pkg)
		}
		a.errf(p, ResXdkNotImport, "XDK 符号 `"+name+"` 未显式导入（定义于 "+strings.Join(pkgs, "、")+"）（§3.5）",
			"在使用文件顶部添加 import")
	}
}
