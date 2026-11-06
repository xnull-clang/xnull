# 集成更新（main@2c00cf5 合入）

> 分支 `pod/c1-rd1`；合并提交 `39552bc`（非快进，父：`646b289` + `2c00cf5`）。

## 合并结果

| 项 | 结果 |
|---|---|
| 冲突文件 | 仅 `impl/internal/sema/xdk.go`（main 的 DET-01 排序 vs PKG-01 的 `analyzeImports` 重写） |
| 解决 | 保留 PKG-01 新实现；保留 main 的 `xdkExporters` `sort.Strings(pkgs)`；新实现本身用 `sortedKeys` + 排序后的歧义来源列表，DET-01 不回归 |
| 其他文件 | 自动合并；`impl/internal/xfront/**` 无冲突 |
| 全量测试 | `go test ./... -count=1 -timeout 300s` → 10/10 包 ok，exit 0（`after/full-suite-post-merge.out`） |
| examples/multi 双路径 | build/run/interp 退出码 0；stdout 逐字节一致（`[xnull] / 25 / [norm=25]`） |

## PKG-01 复跑（我的锚点）

`TestPkgImport|TestSymbolImport|TestAliasDisambiguation|TestNeedlessAliasRejected|TestAmbiguousSimpleName|TestXdkNotImportedStrict|TestImportCycle|TestImportTargetRules` → **8/8 PASS**。

## NEG 复跑（集成后）

`TestDiagMatrixS1` → **51/60**（合入前 48/60；main 的 defer 修复多清 3 项）。
剩余 9 项全部为 sema 域：`neg-0.6-41`（类型别名）、`neg-1.3-01…06`（保留名）、`neg-1.3-08`（`Array`）、`neg-1.3-09`（`true` 声明名）。
xfront 侧无新增红项；`neg-3.2-02`（包别名）保持 PASS。

## GEN

main 合入的是 interp 泛型重载；codegen 单态化（`generics.go`）仍在 `pod/c1-rd3`，本分支 `TestGEN01` 计数不变（xfront 解析两项已清零，见 `before/after-parse-probe.out`）。

原始输出：`after/neg-integrated-TestDiagMatrixS1.out`、`after/full-suite-post-merge.out`。
