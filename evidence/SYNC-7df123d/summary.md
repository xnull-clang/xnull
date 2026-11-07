# SYNC：main@7df123d 合入 pod/c1-rd1

> 合并提交 `63c972f`（非快进，父 `a6fb48d` + `7df123d`）。**无冲突**（`git merge --no-ff` 自动合并）。
> 工作树 `wt/c1-rd1`；采集时间 2026-11-07 12:33–12:36 CST。

## 测试结果

| 项 | 结果 | 证据 |
|---|---|---|
| `go test ./... -count=1 -timeout 300s` | **10/10 包 ok，exit 0**（cli 71.8s / codegen 145.2s / ffi 50.2s / 其余 <13s） | `full-suite.out` |
| PKG-01 锚点矩阵（8 用例） | **8/8 PASS** | `anchor-pkg01.out` |
| NEG `TestDiagMatrixS1` | **51/60**；剩余 9 项全在 sema（类型别名；保留名×6；`Array`；`true` 声明名），xfront 无红项 | `neg-matrix.out` |
| `examples/multi` 双路径 | build/run/interp 退出码 0；stdout 逐字节一致（`[xnull] / 25 / [norm=25]`） | `dualpath*.out`、`dualpath.diff`（空） |

## 环境异常（诚实记录）

首次全量执行在 `internal/codegen` 5m 超时（`TestExamplesCompileMatchesInterp/hello.x` 卡在 `cc`/`exec`）。
排查：系统 load average 29–43，存在 **7 个 13–16 小时前泄漏的 `/tmp/xnull-m5` 进程**（各 ~97% CPU，孤儿，命令为对 `examples/parser-seed.xn` 的旧二进制解释执行）。
处置：`pkill -9 -f /tmp/xnull-m5` 后 load 降至 5.86，**同一命令重跑 10/10 包 ok**。
失败原始输出保留在 `full-suite-attempt1-env-load.out`，未删除、未改写。

## 合并说明

- `impl/internal/xfront/**`、`impl/internal/sema/{pkg.go,xdk.go,sema.go}`：main 无改动 → 无冲突。
- 跨包 `import` 的 codegen 变更（`impl/internal/codegen/multifile.go`，B0）与本分支 PKG-01 的 sema 依赖表**互不冲突**；`go test ./...` 覆盖两者。
- PKG-01 边界不变：CLI 仍未接 `AnalyzeWithDeps`；B0 的 codegen 跨包能力与本锚点的“导入诊断”验收互不影响。
