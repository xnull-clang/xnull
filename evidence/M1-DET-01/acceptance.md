# M1-DET-01 验收记录

> 执行：CEO3-RD2　分支：`pod/c3-rd2`　日期：2026-11-07
> 依据：台账 DET-01「验收要点」三项（见 `checklist.md`，逐项抄录未增删）

## 逐项结果

| # | 验收要点 | 用例 | 结果 | 说明 |
|---|---|---|---|---|
| a | 相同诊断 | `internal/sema/det01_test.go` `TestDET01DiagStableAcrossRuns` + `TestDET01DiagIndependentOfMapOrder` | **PASS（main `2c00cf5`）** | 多错误源 200 轮稳定；歧义诊断顺序稳定（map 序发射点已随 PKG-01 重写消除），`after/postmerge-full-test.txt` |
| b | 相同运行结果 | `internal/interp/det01_test.go` `TestDET01RuntimeStable`、`internal/codegen/det01_test.go` `TestDET01EmitCDeterministic` | PASS | 解释路径 10 轮 stdout+rc 一致；EmitC 5 次逐字节一致；示例 9/9 双路径一致（`after/postmerge-examples.txt`） |
| c | 初始化顺序不依赖文件系统枚举顺序 | `internal/codegen/det01_test.go` `TestDET01InitOrderIndependentOfCreationOrder` | PASS | 同一逻辑树按 20 种文件创建顺序落盘，合并声明序与运行输出逐字节一致 |

## 结论（2026-11-07 集成后复跑）

- 合入 main `2c00cf5`（`git merge --no-ff`，无冲突），DET-01 三项用例全 PASS，全包 9/9 绿。
- 确定性判据：同命令同 `-o` 两次构建 hash 一致（`4e3ec1d7…`）；编译路径 10 次与解释路径 10 次运行同一 sha256（`a6ed6096…`），两路径逐字节一致。
- 红点根因（旧 `sema/xdk.go:173` 按 map 迭代序发射 `RES-104`）已随 PKG-01 导入诊断重写消除；原 `fix-proposal.diff` 作废，仅留过程证据。

## 未测项 / 风险

| 项 | 说明 |
|---|---|
| 编译路径 10 次运行 | 由 CLI 证据覆盖（`after/hash-and-runs.txt` 10/10 同一 sha256），未写成 Go 测试（每次 cc 约 3s，10 轮过慢） |
| 两次构建 hash | 同命令同 `-o` 两次构建一致；**不同 `-o` 名仅 16 字节差异（Mach-O `LC_UUID`）**，内容一致。若 CI 08 项要落 sha 锚点，须固定输出路径（并入 CEO3-RD2 CI 产物卡） |
| 多包/工程清单模式 | 未实现（`import` 环 + 同包分片属 PKG-01/ENTRY-01）；本锚点只验「当前可编译形态」的确定性 |
| INIT-1/INIT-2 | 探针发现两个 §4.3 初始化缺陷（初始化式调用后置函数报「未定义的函数」；同目录同包分片不加载），**归属 ENTRY-01**，证据 `before/probe-init-order.txt`，本卡不修 |

## 验收签署

- 执行侧自检：以上结果可由 `command.txt` 复跑。
- 独立验收（CEO3-QA2）：________　时间：________
- 结论（QA 填写）：________

> 本文件不代替验收签署；未签名前不得据此把台账 DET-01 改为 PASS。

## 二次复跑（2026-11-07，main `2c00cf5` = 含 `c737099`）

- `git merge main` → Already up to date（`c737099`/`2c00cf5` 已在祖先链）。
- `go test ./internal/{sema,interp,codegen}/ -run TestDET01 -count=1` → 5 个用例全 PASS（`after/rerun-2c00cf5.txt`）。
- `go test ./... -count=1` → 9/9 包 ok，rc=0（`after/rerun-full-test.txt`）。
- 示例双路径 → 9/9 一致（`after/rerun-examples.txt`）。
- 结论不变：DONE 3/3。

## 阶段对齐复跑（2026-11-07，main `7df123d`，B0 门）

- `git merge --no-ff main` 无冲突，合并提交 `3bead3b`。
- `go test ./... -count=1 -timeout 300s`：首次 rc=1（`after/sync-7df123d-full-test.txt`）——机器争用导致 codegen 包 359s 超时（cli 263s / ffi 191s，全部包同比放慢 3–7 倍）；同命令立即重跑 rc=0，9/9 包 ok（`after/sync-7df123d-full-test-2.txt`）。`internal/codegen` 单包独立复跑 119s ok（-timeout 600s），排除代码回归。
- DET-01 三项矩阵：5 个用例全 PASS（`after/sync-7df123d-det01.txt`）。
- 示例双路径 9/9 一致（`after/sync-7df123d-examples.txt`）；同命令两次构建 hash 一致 `f013ccf2…`；10 次编译路径运行同一 sha256 `a6ed6096…`（`after/sync-7df123d-hash-and-runs.txt`）。
- 结论不变：DONE 3/3，无回退。
