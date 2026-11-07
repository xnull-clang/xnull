# M1-PKG-01 验收清单与结论（S1 包与导入）

> **锚点：PKG-01**　**主责：CEO1-RD1**　**工作树：`wt/c1-rd1` / `pod/c1-rd1`**　**基线：`81ec33d`**
> **台账原文（逐字）**：`PKG-01 | S1 | 包与导入；包导入、符号导入、同名消歧别名、非冲突别名被拒绝、简单名歧义、XDK 未导入、导入环均正确诊断 | M1 | internal/xfront/unit_test.go + internal/sema/xdk_test.go | 部分`
> **规范依据：S1 §3.1（package）、§3.2（import）、§3.3（名称解析）、§3.4（多包编译）、§3.5（导入诊断）**

---

## 0. 结论

**PKG-01：7/7 验收要点通过（本清单逐项打勾），0 项未覆盖。**

- 红证据：`red/red-sema.out`（实现前，7 组用例 7 个 FAIL；XDK 项当时已绿，如实保留）。
- 绿证据：`stdout.txt` / `stderr.txt` / `exit_code.txt` + `logs/`。
- 未测项与边界见 §3（跨包代码生成不在本锚点验收要点内，明确列边界，不冒充通过）。

---

## 1. 台账验收要点 → 检查表（逐项，不得漏项）

| # | 台账要点（原文拆条） | 检查子项 | 期望 | 实现位置 | 用例 | 判定 |
|---|---|---|---|---|---|---|
| ① | **包导入** | `import P` 引入 P 的全部公开顶层符号 | 无诊断，符号可用 | `sema/pkg.go` `NewPackage` / `xdk.go` `analyzeImports` | `TestPkgImport` | ☑ 通过 |
| ① | 包导入 | 包导入不绑定包命名空间别名（`text.banner` 非法） | `RES-101` | 同上 | `TestPkgImport` | ☑ 通过 |
| ① | 包导入 | 顶层 `private` / `protected` 不可导入 | `RES-101` | `NewPackage` 只登记公开符号 | `TestPkgImport` | ☑ 通过 |
| ① | 包导入 | 当前包顶层声明遮蔽同名导入，不算歧义 | 无诊断 | `topLevelNames` 遮蔽判定 | `TestPkgImport` | ☑ 通过 |
| ② | **符号导入** | `import P.S` 只引入 S | 无诊断，S 可用 | `xdk.go` 符号导入分支 | `TestSymbolImport` | ☑ 通过 |
| ② | 符号导入 | 同包其他符号不因符号导入可见 | `RES-101` | 同上 | `TestSymbolImport` | ☑ 通过 |
| ② | 符号导入 | 符号不存在 | `RES-106` | `resolveUserImport` | `TestSymbolImport` | ☑ 通过 |
| ② | 符号导入 | 私有符号不能被符号导入 | `RES-106` | `NewPackage` 公开过滤 | `TestSymbolImport` | ☑ 通过 |
| ③ | **同名消歧别名** | 两处同名符号各自 `as` 消歧 → 合法 | 无诊断 | 别名冲突/需求判定 | `TestAliasDisambiguation` | ☑ 通过 |
| ③ | 同名消歧别名 | 别名替换原简单名，原简单名不可裸用 | `RES-101` | `a.imported[alias]` | `TestAliasDisambiguation` | ☑ 通过 |
| ③ | 同名消歧别名 | 一处消歧、一处裸导入 → 合法 | 无诊断 | 同上 | `TestAliasDisambiguation` | ☑ 通过 |
| ④ | **非冲突别名被拒绝** | 单一符号导入 `as`（无同名） | `RES-107` | `importedSym` 来源计数 | `TestNeedlessAliasRejected` | ☑ 通过 |
| ④ | 非冲突别名被拒绝 | 包导入 `import P as Q`（§3.2 禁止包别名） | `RES-107` | `pkgImport` 分支 | `TestNeedlessAliasRejected` | ☑ 通过 |
| ④ | 非冲突别名被拒绝 | XDK 包别名 `import xdk.text as T` | `RES-107` | 同上 | `TestNeedlessAliasRejected` | ☑ 通过 |
| ④ | 非冲突别名被拒绝 | 同一别名指向两个符号 | `RES-103` | `aliasOwners` | `TestNeedlessAliasRejected` | ☑ 通过 |
| ④ | 非冲突别名被拒绝 | 别名与当前文件顶层声明冲突 | `RES-103` | `topLevelNames` | `TestNeedlessAliasRejected` | ☑ 通过 |
| ④ | 非冲突别名被拒绝 | 别名与预定义类型名冲突 | `RES-103` | `builtinTypeNames` | `TestNeedlessAliasRejected` | ☑ 通过 |
| ⑤ | **简单名歧义** | 两个导入提供同一简单名且未消歧 | `RES-104` | `exposed` 来源集合 | `TestAmbiguousSimpleName` | ☑ 通过 |
| ⑤ | 简单名歧义 | 重复导入同一包/同一符号允许，不产生歧义 | 无诊断 | 按来源去重 | `TestAmbiguousSimpleName` | ☑ 通过 |
| ⑤ | 简单名歧义 | 重复导入同一 XDK 包允许 | 无诊断 | 按来源去重 | `TestAmbiguousSimpleName` | ☑ 通过 |
| ⑥ | **XDK 未导入** | 未导入即使用 XDK 静态入口 | `RES-105` | `checkXdkUse`（既有） | `TestXdkNotImportedStrict` | ☑ 通过 |
| ⑥ | XDK 未导入 | 显式导入后可用 | 无诊断 | 同上 | `TestXdkNotImportedStrict` | ☑ 通过 |
| ⑥ | XDK 未导入 | 其他导入不能掩盖 XDK 未导入 | `RES-105` | 严格模式（去 `hasImp` 一刀切） | `TestXdkNotImportedStrict` | ☑ 通过 |
| ⑦ | **导入环** | 入口 → A → B → A | `RES-108` | `sema/pkg.go` `checkImportCycle`（语义）＋ `codegen/multifile.go`（解析，既有） | `TestImportCycle` | ☑ 通过 |
| ⑦ | 导入环 | 无环链 A → C 合法 | 无诊断 | 同上 | `TestImportCycle` | ☑ 通过 |

**补充（§3.5 同类诊断，随本锚点一并闭合）**

| 项 | 期望 | 用例 | 判定 |
|---|---|---|---|
| 包不存在 | `RES-106` | `TestImportTargetRules` | ☑ 通过 |
| 默认包被跨包导入（§3.1/§3.5） | `RES-111` | `TestImportTargetRules` | ☑ 通过 |
| 默认包入口导入默认包分片（`examples/multi` 形态） | 无诊断 | `TestImportTargetRules` | ☑ 通过 |

---

## 2. 诊断码与检测时机（QA 要求）

| 码 | 含义 | 检测时机 | 最小复现 | 用例 |
|---|---|---|---|---|
| `RES-103` | 导入别名冲突 | 语义（导入解析） | `import lib.a.Thing as P` + `import lib.b.Thing as P` | `TestNeedlessAliasRejected` |
| `RES-104` | 未消歧的简单名 | 语义（导入解析） | `import lib.a.Thing` + `import lib.b.Thing` | `TestAmbiguousSimpleName` |
| `RES-105` | XDK 未显式导入 | 语义（名称使用点） | `diagnose("x")` 且无 `import xdk.runtime` | `TestXdkNotImportedStrict` |
| `RES-106` | 包/符号不存在 | 语义（导入解析） | `import lib.none` / `import lib.text.Nope` | `TestSymbolImport` / `TestImportTargetRules` |
| `RES-107` | 非冲突别名（含包别名） | 语义（导入解析） | `import lib.text.banner as B` | `TestNeedlessAliasRejected` |
| `RES-108` | 包导入环 | 语义（依赖图 DFS）＋ 解析（文件加载，既有） | A→B→A | `TestImportCycle` |
| `RES-111` | 默认包被跨包导入 | 语义（导入解析） | `package app` + `import lib.plain`（plain 无 package） | `TestImportTargetRules` |

---

## 3. 未测项与边界（诚实声明）

1. **跨包代码生成未纳入本锚点**：`codegen.LoadUnits` 对“子文件包名与入口不一致”仍报 `RES-109`（多包编译属工程清单/BND-01 切片）。本锚点闭合的是 §3.5 所列**导入诊断**与符号可见性；不宣称“跨包可执行”。
2. **完全限定名（§3.3 第 4 级）未纳入**台账 PKG-01 的 7 项枚举；未改动。
3. **`@annotation` / `singleton` / `extension` 声明**属 S2 解析缺口（首轮 G-U2/U3），与 PKG-01 无关。
4. **CLI 未接依赖包表**：`xnull build/run` 走 `sema.Analyze`（无依赖包表，保持旧“延后”行为）；依赖包解析能力以 `sema.AnalyzeWithDeps` API + 用例验收，接入 CLI 属跨域（cli）。`examples/multi` 双路径不受影响（默认包分片）。
5. **红证据时间**：`red/timestamp.txt` 早于实现落盘；`diff/` 提供实现补丁与红/绿对照。

---

## 4. 文件清单（一文件一写入者）

| 文件 | 动作 | 说明 |
|---|---|---|
| `impl/internal/sema/pkg.go` | 新增 | 包符号表、`AnalyzeWithDeps`、环检测、顶层名扫描 |
| `impl/internal/sema/pkg_test.go` | 新增 | 本锚点 8 个 Test（红→绿） |
| `impl/internal/sema/xdk.go` | 修改 | `analyzeImports` 重写：XDK + 用户包统一解析、别名/歧义规则 |
| `impl/internal/sema/sema.go` | 修改 | `analyzer.deps` 字段；`AnalyzeWith` 委托 `analyzeWith` |
| `impl/internal/xfront/**` | 未改 | 导入语法解析已满足（`unit_test.go` 既有用例） |
| `impl/internal/codegen/**` | 未改 | 环检测既有 `RES-108`，仅回归验证 |

**未改现有测试期望、未删测试**：`git diff` 只含上述 4 个 `.go` 文件，测试改动全部在新增 `pkg_test.go`。

---

## 5. 证据索引

| 文件 | 内容 |
|---|---|
| `command.txt` | 全部可复制命令（含工作树、时间戳） |
| `red/` | 实现前失败测试原始输出 + 时间戳 |
| `logs/` | 包全量测试、双路径构建/运行原始输出 |
| `stdout.txt` / `stderr.txt` / `exit_code.txt` | 聚合证据 |
| `sha.txt` | HEAD、分支、改动文件 sha256、工具链版本 |
| `artifact.sha256` | 测试二进制 sha256（构建产物不提交） |
| `diff/` | 实现补丁、红/绿对照、git status |
| `before/` | T0 基线（实现前）包测试原始输出 |
