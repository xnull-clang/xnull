# B1-03 验收（自举线 E4 重跑，权威口径）

> 本文件取代旧 `report.md` 的 FAIL 结论（基于 B1-02 旧二进制与占位 Go oracle）。
> 基线：main `f63fcba` 的 155 个 `.x`；union：本树 `git ls-files '*.x'`（156）。
> 被测代码提交：`2948e82`（含 E5 `xdkc_utf8_valid` cherry-pick）；证据提交见 `handoff/B1-03.md`。
> 重跑脚本：`evidence/M6-B1-03/e4/run.sh`；输出：`evidence/M6-B1-03/e4/rerun/`。

## 结论

| 指标 | 目标 | 实测 |
|---|---|---|
| 逐字节差异（基线 155） | 0 | **0**（`rerun/base155-diff.txt` 空） |
| 逐字节差异（union 156） | 0 | **0**（`rerun/union-diff.txt` 空） |
| 幂等（Go / XNull，两语料） | 0 违约 | **0 / 0**（`rerun/*-idem-*.txt` 空） |
| 工具失败 | 0 | 0 |
| 异常输入诊断 | 4/4（含 FMT-101/102/104） | **6/6**（见下表） |
| 回归 `go test ./...` | 绿 | **绿**（`rerun/go-test-all.log`） |

## 诊断用例（与 Go oracle 码型对齐）

| 输入 | Go oracle | XNull 版 | rc |
|---|---|---|---|
| 缺文件 | FMT-104 | FMT-104 | 2 |
| 目录 | FMT-104 | FMT-104 | 2 |
| 无参数 | FMT-104 | FMT-104 | 2 |
| 非法 UTF-8 | FMT-102 | FMT-102 | 2 |
| 未闭合字符串 | FMT-101 | FMT-101 | 2 |
| 未闭合块注释 | FMT-101 | FMT-101 | 2 |

已知精度差异：XNull 版诊断位置统一 `0:0`，Go 为精确 `line:col`；码型与退出码一致。

## 覆盖的 4 处历史差异

| # | 文件 | 修法 |
|---|---|---|
| 1 | `evidence/M1-TUPLE-01/cli/tuple-ok.x` | XNull：`$"…"` 整体 token + `===` 单 token |
| 2 | `evidence/M1-TUPLE-01/cli/tuple-switch.x` | XNull：`case` 计入控制关键字（`(` 前 1 空格） |
| 3 | `evidence/M6-B0-05/before/branch-tuple-recv.x` | 数字不吞点后标识符；一元 `!` 与 `(` 0 空格 |
| 4 | `impl/lib/xdk/text.x` | XNull：独立注释计入 import 区段，R9.1 段间 1 空行 |

## 产物

- Go oracle：`impl/internal/xnfmt` + `impl/cmd/xnfmt`（B1-01，`wt/e6-toolchain@8ed0153`），sha256 `aab1cabc…`
- XNull 版：`impl/xnfmt/xnfmt.x`（B1-02），经 `xnull build` 产出，sha256 `e8c6183f…`
- 记录：`rerun/env.txt`（HEAD/base）、`rerun/artifact.sha256`、`rerun/exit_code.txt`

## 送 QA1

独立复验命令：`./evidence/M6-B1-03/e4/run.sh f63fcba`；判据：两处 `diff-*` 空、两处 `*-idem-*` 空、`go-test-all` 绿、`diagnostics.log` 6/6 且 rc=2。
