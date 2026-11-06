# S0-21e 自检结论（七项硬指标逐项）

> 依据：董事会判决 v1.4.0 第 7 条、董事会令 S0-27 v1.0.0 第 1、3 条。
> 本文件是 **E6 执行侧自检**，不构成 S0-24 门禁结论；判定权在 CEO，独立复核在 QA1。

| # | 指标 | 命令 | 判据 | 实测 | 判定 |
|---|---|---|---|---|---|
| 1 | Go 静态与全量测试 | `go vet ./... && go test ./... -count=1 -timeout 180s` | 退出码 0，无跳过、无超时 | `go vet`=0；`go test`=**1**：`internal/codegen` 187.869s 触 180s 超时（`TestExamplesCompileMatchesInterp/parser-seed.xn`，**已知 P0-1**），其余 8 包 ok | **红（P0-1，非本卡引入）** |
| 2 | C 运行时构建 | `sh impl/runtime/build_rt.sh` | 退出码 0 | 0；资源表/abi/std/weak-slot 测试通过 | 绿 |
| 3 | 工作区守门 | 主树 cwd `<wt>/evidence/S0-21d/bin/xnull dev check` | 退出码 0，无诊断 | 0；五项全 `[ok]`，EN 快照 9 份对照 | 绿 |
| 4 | 公开布局守门 | `xnull/` cwd 同一二进制 `dev check` | 退出码 0，与 #3 一致 | 0；输出与 #3 逐行同构（仅路径不同） | 绿 |
| 5 | 台账 | `dev ledger` 再生成后与 S0-21a golden `diff` | 101 条；PASS 数同基线；仅头部生成器名一行差异 | 120 行 / 101 条 / PASS 10；`diff` 唯一差异第 3 行 `gen_ledger.py` → `xnull dev ledger` | 绿（白名单内） |
| 6 | 资源生成器 | 同一 fixture 的 Go 产物 vs Python golden sha256 | 逐字节一致 | 两侧均 `2f88b9314adf77fc9a731202627d042242f7ebfe71e76c244afa9326b3c95949` | 绿 |
| 7 | 无 Python 残留 | `find impl -name '*.py'`；`git grep -n 'impl/tools/.*\.py' -- ':!*.md'` | 均为 0 | `find`=0；`git grep` 原始口径命中 17 条：16 条在 `evidence/` 历史记录文本内，1 条 `impl/internal/devtool/resources.go:99` 生成物注释（董事会令 §1.1 已登记例外）。产品代码口径（加 `':!evidence/**'`）为 1 | 绿（按令 §1.1 口径）；**字面命令不为 0，需 QA1 知悉** |

**整卡判定：不通过（#1 红）。** 原因唯一：P0-1 未关闭，`go test ./...` 在 180s 硬界内无法全绿。其余六项七条全部满足。

## 与 S0-21d 的差异

- `go test` 本轮按董事会令 §3 加 `-timeout 180s`；21d 当时用默认 10m，codegen 跑到 606s。两轮结论相同（P0-1），本轮是硬界下的正式证据。
- 21d 的 `go test` 输出保持原样，不覆盖、不删除。

## 七件套

`command.txt`、`stdout.txt`、`stderr.txt`、`exit_code.txt`、`sha.txt`、`artifact.sha256`、`acceptance.md`；附加 `summary.md`、`m1-*`…`m7-*` 原始输出。

## 声明

执行侧自检，不构成验收签署。指标 3/4 在本机通过不代表干净 clone 稳定——mtime 依赖按 S0-27 处理，见 `evidence/S0-27/`。
