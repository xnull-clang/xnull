package sema

import (
	"sort"
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
		"Task": true, "TaskGroup": true, "Context": true, "CancelToken": true, "TaskError": true, "CancelledError": true,
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
		// 算法函数：S6 §4.5 只给类别，签名未冻结；保留名用于 TY-229 显式诊断。
		"sort": true, "groupBy": true, "dedup": true, "find": true,
	},
	"text": {
		"Regex": true, "Format": true, "parseInt": true, "parseFloat": true,
		"utf8ToUtf16": true, "utf16ToUtf8": true,
	},
	"sys": {
		// 句柄类型（S6 §4.7；close 经顶层 fileClose/dirClose）
		"File": true, "Dir": true, "Process": true,
		// 文件/目录/存在性（当前绑定面）
		"fileOpenRead": true, "fileOpenWrite": true, "fileRead": true, "fileWrite": true,
		"fileClose": true, "dirOpen": true, "dirRead": true, "dirClose": true,
		"pathExists": true, "utf8Valid": true, "readFileText": true, "writeFileText": true,
		"procStatus": true,
		// 资源读取（S6 §4.8）
		"resourceExists": true, "readResource": true, "readResourceText": true,
		"listResources": true, "resourceSize": true,
	},
	"net": {
		// S6-09（ADR-009）：socket plain/Async + HTTP 响应句柄。
		"Socket": true, "Listener": true, "HttpResponse": true,
		"connect": true, "connectAsync": true, "bind": true, "bindAsync": true,
		"accept": true, "acceptAsync": true,
		"socketConnect": true, "socketSend": true, "socketRecv": true, "socketClose": true,
		"socketConnectAsync": true, "socketSendAsync": true, "socketRecvAsync": true,
		"httpRequest": true, "httpStatus": true, "httpBodyText": true,
		"httpResponseClose": true, "httpRequestAsync": true,
	},
	"net.http": {
		"HttpResponse": true,
		"get":          true, "getAsync": true, "post": true, "postAsync": true,
		"httpRequest": true, "httpStatus": true, "httpBodyText": true, "httpResponseClose": true,
		"httpRequestAsync": true,
	},
}

// xdkSubPackages 是已定案的多级 XDK 包子包（相对 xdk. 的路径）。
// `import xdk.net.http` 是包导入，不是 xdk.net 的符号 http（S1 §3.2）。
var xdkSubPackages = map[string]bool{
	"net.http": true,
}

// xdkSubPackageSymbols 是多级包子包的导出符号（S6 §4.7）。
var xdkSubPackageSymbols = map[string]map[string]bool{
	"net.http": {
		"Request": true, "Response": true, "HttpResponse": true,
		"get": true, "post": true, "getAsync": true, "postAsync": true,
		"httpRequest": true, "httpStatus": true, "httpBodyText": true,
		"httpResponseClose": true, "httpRequestAsync": true,
	},
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
	sort.Strings(pkgs) // DET-01：包名列表顺序不得取自 map 迭代序
	return pkgs
}

// importInfo 记录一个导入的展开结果。
type importInfo struct {
	p            xfront.Pos
	path         []string
	alias        string
	syms         []string // 包导入时为该包全部导出符号；符号导入时为单符号
	src          string   // 来源标识（包路径）；别名/歧义判定用
	pkgImport    bool     // 包导入（全部符号）
	symbolImport bool     // 符号导入（单符号）
}

// analyzeImports 处理导入：存在性、别名规则、简单名歧义、XDK 未导入检查基础。
//
// 分两段（§3.2/§3.5）：
//  1. 逐个导入展开为 importInfo：XDK 走注册表；用户包走依赖包符号表（deps）。
//  2. 别名与简单名规则：别名只用于消歧、别名唯一、简单名歧义必须报错。
func (a *analyzer) analyzeImports(u *xfront.CompilationUnit) {
	for _, imp := range u.Imports {
		if len(imp.Path) > 0 {
			a.importPaths = append(a.importPaths, imp.Path)
		}
	}
	topNames := topLevelNames(u)
	var binds []importInfo

	for _, imp := range u.Imports {
		p := imp.Path
		if len(p) == 0 {
			continue
		}
		info := importInfo{p: imp.P, path: p, alias: imp.Alias}
		if p[0] == "xdk" {
			if len(p) < 2 {
				a.errf(imp.P, ResNotFound, "XDK 导入缺包名（§3.2）", "写成 import xdk.<包> 或 import xdk.<包>.<符号>")
				continue
			}
			pkg := p[1]
			syms, known := xdkPackages[pkg]
			if !known {
				a.errf(imp.P, ResNotFound, "未知的 XDK 包 `"+strings.Join(p, ".")+"`（S6 §2 包结构）",
					"可用包：errors/tasks/sync/runtime/collections/text/sys/net")
				continue
			}
			info.src = "xdk." + pkg
			// 多级包子包（如 xdk.net.http）：包导入或子包符号导入。
			if len(p) >= 3 {
				if subSyms, ok := xdkSubPackageSymbols[pkg+"."+p[2]]; ok {
					info.src = "xdk." + pkg + "." + p[2]
					switch {
					case len(p) == 3:
						info.syms = sortedKeys(subSyms)
						info.pkgImport = true
					case len(p) == 4 && subSyms[p[3]]:
						info.syms = []string{p[3]}
						info.symbolImport = true
					default:
						a.errf(imp.P, ResNotFound, "XDK 子包 `xdk."+pkg+"."+p[2]+"` 没有导出符号 `"+
							strings.Join(p[3:], ".")+"`（§3.5）", "检查符号名或改用包导入")
						continue
					}
					binds = append(binds, info)
					continue
				}
			}
			switch {
			case len(p) == 3 && syms[p[2]]: // 符号导入
				info.syms = []string{p[2]}
				info.symbolImport = true
			case len(p) >= 3 && xdkSubPackages[pkg+"."+strings.Join(p[2:], ".")]:
				// 多级包子包（如 xdk.net.http）：包导入，不绑定符号。
				info.syms = nil
				info.pkgImport = true
			case len(p) == 3:
				a.errf(imp.P, ResNotFound, "XDK 包 `xdk."+pkg+"` 没有导出符号 `"+p[2]+"`（§3.5）",
					"检查符号名或改用包导入")
				continue
			default: // 包导入
				info.syms = sortedKeys(syms)
				info.pkgImport = true
			}
			binds = append(binds, info)
			continue
		}

		// 用户包：需要依赖包符号表（AnalyzeWithDeps）。
		if a.deps == nil {
			// 旧行为：无法解析用户包，延后未定义检查，避免误报。
			a.hasImp = true
			continue
		}
		dep, sym, ok := a.resolveUserImport(p)
		if !ok {
			a.errf(imp.P, ResNotFound, "包 `"+strings.Join(p, ".")+"` 未在本次编译中找到（§3.5）",
				"检查 import 路径，或把依赖包加入本次编译")
			continue
		}
		if len(dep.Name) == 0 && u.Package != nil {
			a.errf(imp.P, ResDefaultPkg, "默认包 `"+strings.Join(dep.Path, ".")+"` 不能被其他包导入（§3.1）",
				"在被导入文件顶部写 package 声明")
			continue
		}
		if samePackage(u, dep) {
			// 同包分片：符号已随编译单元合并，不建立导入绑定。
			if imp.Alias != "" {
				a.errf(imp.P, ResNeedlessAlias, "包导入不能使用 as 别名（§3.2）", "去掉 as 子句")
				continue
			}
			for s := range dep.Symbols {
				a.imported[s] = true
			}
			continue
		}
		info.src = strings.Join(dep.Path, ".")
		if sym != "" { // 符号导入
			if !dep.Symbols[sym] {
				a.errf(imp.P, ResNotFound, "包 `"+info.src+"` 没有公开符号 `"+sym+"`（§3.5）",
					"检查符号名（private/protected 不可导入），或改用包导入")
				continue
			}
			info.syms = []string{sym}
			info.symbolImport = true
		} else { // 包导入
			info.syms = sortedKeys(dep.Symbols)
			info.pkgImport = true
		}
		binds = append(binds, info)
	}

	// 环检测先于绑定（§3.4）：有环即报错，仍继续产出别名/歧义诊断以便一次看全。
	a.checkImportCycle(u)

	// 别名的"是否需要"判定：统计同一简单名被哪些来源占用（含别名导入，§3.2）。
	importedSym := map[string]map[string]bool{}
	// 实际暴露到文件作用域的简单名：来源集合（未别名导入）。
	exposed := map[string]map[string]bool{}
	addSrc := func(m map[string]map[string]bool, name, src string) {
		if m[name] == nil {
			m[name] = map[string]bool{}
		}
		m[name][src] = true
	}
	for _, b := range binds {
		for _, s := range b.syms {
			addSrc(importedSym, s, b.src)
			if b.alias == "" {
				addSrc(exposed, s, b.src)
			}
		}
	}

	aliasOwners := map[string]string{} // 已绑定名（简单名+别名）→ 来源
	bound := map[string]string{}
	for _, b := range binds {
		if b.alias != "" {
			if b.pkgImport {
				a.errf(b.p, ResNeedlessAlias, "包导入不能使用 as 别名（§3.2）：`"+b.src+"` 不绑定包命名空间",
					"改用符号导入 `import P.S as A` 仅引入所需符号")
				continue
			}
			aliasID := b.src + "." + b.syms[0]
			if prev, dup := aliasOwners[b.alias]; dup {
				if prev != aliasID {
					a.errf(b.p, ResAliasConflict, "导入别名 `"+b.alias+"` 冲突（已由 `"+prev+"` 使用）（§3.5）", "换一个别名")
				}
				continue
			}
			if topNames[b.alias] {
				a.errf(b.p, ResAliasConflict, "导入别名 `"+b.alias+"` 与当前文件顶层声明冲突（§3.3）", "换一个别名")
				continue
			}
			if builtinTypeNames[b.alias] {
				a.errf(b.p, ResAliasConflict, "导入别名 `"+b.alias+"` 与预定义类型名冲突（§3.3）", "换一个别名")
				continue
			}
			aliasOwners[b.alias] = aliasID
			// 非冲突场景使用 as → RES-107（§3.2）。
			if len(importedSym[b.syms[0]]) <= 1 {
				a.errf(b.p, ResNeedlessAlias, "`"+b.syms[0]+"` 无同名歧义，as 别名只用于消歧（§3.2）", "去掉 as 子句")
				continue
			}
			a.imported[b.alias] = true
			continue
		}
		for _, s := range b.syms {
			if srcs := exposed[s]; len(srcs) > 1 {
				// 当前包顶层声明遮蔽同名导入（§3.3），不算歧义。
				if topNames[s] {
					continue
				}
				if prev, dup := aliasOwners[s]; dup && prev != b.src+"."+s {
					if !a.ambiguous[s] {
						a.errf(b.p, ResAmbiguousName, "简单名 `"+s+"` 已由别名 `"+prev+"` 占用（§3.2/§3.3）", "改用 as 别名或完全限定名")
						a.ambiguous[s] = true
					}
					continue
				}
				if !a.ambiguous[s] {
					var srcList []string
					for src := range srcs {
						srcList = append(srcList, src)
					}
					sort.Strings(srcList)
					a.errf(b.p, ResAmbiguousName,
						"简单名 `"+s+"` 在多个来源间歧义（"+strings.Join(srcList, "、")+"），必须用 as 消歧（§3.2/§3.5）",
						"为其中一个导入加 as 别名")
					a.ambiguous[s] = true
				}
				continue
			}
			if prev, dup := aliasOwners[s]; dup && prev != b.src+"."+s {
				if !a.ambiguous[s] {
					prevSrc := prev
					if i := strings.LastIndex(prev, "."); i >= 0 {
						prevSrc = prev[:i]
					}
					if prevSrc == b.src {
						// 同包不同符号：别名唯一性错误（§3.3）。
						a.errf(b.p, ResAliasConflict, "导入别名 `"+s+"` 已绑定 `"+prev+"`，与裸导入简单名冲突（§3.3/§3.5）", "换一个别名或改名")
					} else {
						// 不同包同名：简单名歧义（§3.2/§3.5）。
						a.errf(b.p, ResAmbiguousName, "简单名 `"+s+"` 与别名 `"+prev+"` 冲突（§3.3）", "换一个别名")
					}
					a.ambiguous[s] = true
				}
				continue
			}
			if _, ok := bound[s]; !ok {
				bound[s] = b.src
				aliasOwners[s] = b.src + "." + s
			}
		}
	}
	for s := range bound {
		a.imported[s] = true
	}
}

// checkTypeXdkUse 检查类型位置上的 XDK 符号是否已导入（§3.5）。
func (a *analyzer) checkTypeXdkUse(t xfront.TypeRef) {
	if t == nil {
		return
	}
	switch ty := t.(type) {
	case *xfront.NamedType:
		if len(ty.Qual) == 1 && !externalTypes[ty.Qual[0]] && xdkSymbolKnown(ty.Qual[0]) && !a.imported[ty.Qual[0]] {
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
