**状态：DONE（7/7）**　**锚点：M1-PKG-01**　**代码+证据提交：`9bb6bef`**　**本回执更新提交：见 `git log -1 -- 收件箱/CEO1/回执-M1-PKG-01.md`**

---

1. 改了什么：实现 PKG-01（S1 §3 包与导入）。新增 `impl/internal/sema/pkg.go`（包符号表 `Package`/`NewPackage`、`AnalyzeWithDeps`、导入环检测、顶层名扫描）与 `impl/internal/sema/pkg_test.go`（8 个 Test，先红后绿）；重写 `impl/internal/sema/xdk.go` 的 `analyzeImports`（XDK 与用户包统一解析、别名/歧义/重复导入规则）；`impl/internal/sema/sema.go` 仅加 `analyzer.deps` 字段并把 `AnalyzeWith` 委托给 `analyzeWith`。未改现有测试期望、未删测试、未改 xfront/CLI/codegen。
2. 怎么验：`cd impl && go vet ./internal/sema ./internal/xfront`（exit 0）；`go test ./internal/sema -count=1 -v`（ok）；`go test ./internal/xfront -count=1 -v`（ok）；锚点 8 用例全 PASS；`go test ./internal/codegen -count=1 -timeout 300s`（ok，回归）；`go test ./... -count=1 -timeout 300s`（10 包全 ok）；双路径 `examples/multi`：编译产物 stdout 与 `--interp` stdout 逐字节一致、退出码均 0（`diff/` 空 diff）。原始输出见 `evidence/M1-PKG-01/{red,logs,stdout.txt,stderr.txt,exit_code.txt}`。
3. sha：工作树 `wt/c1-rd1`/分支 `pod/c1-rd1`，提交前基线 `81ec33d`（S0-28；impl 代码与 `dfcf033` 相同）；代码+证据提交 `9bb6bef48e7428c94414391fe27ed929ac2fdfc4`，本回执为紧随其后的独立提交（HEAD 见 `git log -1`）。红证据时间 `2026-11-07 03:22:35 CST`，早于实现落盘；实现补丁见 `evidence/M1-PKG-01/diff/impl.patch`。
4. 产物路径：代码 `impl/internal/sema/{pkg.go,pkg_test.go,xdk.go,sema.go}`；证据 `evidence/M1-PKG-01/`（七件套 `acceptance.md`/`command.txt`/`stdout.txt`/`stderr.txt`/`exit_code.txt`/`sha.txt`/`artifact.sha256` + `red/` + `diff/` + `logs/` + `before/`）；提交仅在本分支，未 push、未合并、未碰 main。
5. 未测项/风险：①跨包代码生成仍由 `codegen.LoadUnits` 报 `RES-109`（多包编译属工程清单/BND-01），本锚点只闭合台账所列 7 项导入诊断，未宣称“跨包可执行”；②`xnull build/run` 仍走 `sema.Analyze`（无依赖包表），`AnalyzeWithDeps` 尚未接 CLI（跨域，cli 属三司），`examples/multi` 双路径不受影响；③完全限定名（§3.3 第 4 级）不在台账 PKG-01 枚举内，未改；④`RES-111`（默认包被跨包导入）为本卡新增码，需 E6 记入台账码表。
是否越界：否（仅动 PKG-01 实现所需的 `internal/sema` 三个文件 + 新增两文件；xfront 仅跑既有用例、未改）
域界定：PKG-01 由 v1.7.0 §2.1 指派给 CEO1-RD1，台账证据映射含 `internal/sema/xdk_test.go`；本次只改导入解析链（`xdk.go`/`sema.go` + 新增 `pkg.go`），未触碰 RD2 的 `ty.go`/`assign.go`/`typedecl.go` 与 `interp/**`（ERR-01/TUPLE-01 域）。

---

## 台账验收要点逐项打勾（7/7）

| # | 验收要点 | 结果 | 用例 |
|---|---|---|---|
| ① | 包导入（含不绑定包别名、私有/受保护不可导入、顶层遮蔽） | ☑ 通过 | `TestPkgImport` |
| ② | 符号导入（只引入单符号、不存在/私有报错） | ☑ 通过 | `TestSymbolImport` |
| ③ | 同名消歧别名（双别名合法、别名替换原名、单边消歧合法） | ☑ 通过 | `TestAliasDisambiguation` |
| ④ | 非冲突别名被拒绝（符号/XDK/包别名 → RES-107；别名冲突/顶层/预定义 → RES-103） | ☑ 通过 | `TestNeedlessAliasRejected` |
| ⑤ | 简单名歧义（RES-104；重复导入不误报） | ☑ 通过 | `TestAmbiguousSimpleName` |
| ⑥ | XDK 未导入（RES-105；显式导入可用；不被其他导入掩盖） | ☑ 通过 | `TestXdkNotImportedStrict` + 既有 `TestXdkNotImported` |
| ⑦ | 导入环（RES-108；无环链合法） | ☑ 通过 | `TestImportCycle` + 既有 `codegen.TestLoadUnitsCycle` |

补充随附：`RES-106` 包/符号不存在、`RES-111` 默认包跨包导入（`TestImportTargetRules`）。

---

## 集成更新（main@2c00cf5，2026-11-07）

- 合并提交 `39552bc`（非快进）；唯一冲突 `impl/internal/sema/xdk.go`，已保留 PKG-01 新实现与 main 的 DET-01 排序。
- 集成后复跑：PKG-01 锚点 **8/8 PASS**；`go test ./...` **10/10 包 ok**；`examples/multi` 双路径 stdout 逐字节一致、退出码 0。
- 证据：`evidence/XFRONT-FIX-NEG-GEN/post-merge.md`、`after/full-suite-post-merge.out`。

---

## 同步更新（main@7df123d，2026-11-07 12:36）

- `git merge --no-ff main` → 合并提交 `63c972f`，**无冲突**（自动合并）。
- 全量：`go test ./... -count=1 -timeout 300s` → **10/10 包 ok，exit 0**（首跑因 7 个 13h 前泄漏的 `/tmp/xnull-m5` 进程占满 CPU 而 codegen 5m 超时；kill 后同命令重跑绿，失败原始输出留证）。
- PKG-01 锚点：**8/8 PASS**；`examples/multi` 双路径 stdout 一致、退出码 0。
- NEG `TestDiagMatrixS1`：**51/60**；剩余 9 项全在 sema（类型别名、保留名×6、`Array`、`true` 声明名），xfront 无红项。
- 证据：`evidence/SYNC-7df123d/`。
