# B1-02/B1-03 自举线执行记录（E4）

## 结论（2026-11-07 14:25 重跑）

- **B1-03 差分：0 差异**（基线 155 文件；union 156 文件亦 0）。
- **幂等：0 违约**（Go / XNull 各二次格式化不变）。
- **诊断：6/6 用例，码型对齐 Go oracle（FMT-101 / FMT-102 / FMT-104），退出码均 2**。
- **全量测试：绿**（`go test ./...`）。

## 环境

- 输入：main `f63fcba` 的 155 个 `.x`（`files-155.txt`）；union = 本树 `git ls-files '*.x'`（156，`files-union.txt`）。
- Go oracle：`impl/internal/xnfmt` + `impl/cmd/xnfmt`（B1-01，来自 `wt/e6-toolchain@8ed0153`），sha256 `aab1cabc…`。
- XNull 版：`impl/xnfmt/xnfmt.x`（B1-02，来自 `wt/c3-rd1@c3d5ca6` + 本卡修复），用 `xnull build` 产出，sha256 `e8c6183f…`。
- 运行时：`impl/runtime/rt_std_text.c::xdkc_utf8_valid`（E5 交付 `wt/e5-runtime@c9e8a5d`，已 cherry-pick `2948e82`）。

## 修复（4 处历史差异 → 0）

| # | 文件 | 根因 | 修法 |
|---|---|---|---|
| 1 | tuple-ok.x | XNull 未识别 `$"…"` 插值串与 `===` | 词法整体成 token；`matchOp` 增 `===` |
| 2 | tuple-switch.x | `case (` 被判为调用 | `controlKeyword` 增 `case` |
| 3 | branch-tuple-recv.x | 数字扫描吞掉 `1.` 后的标识符；`!`/一元 `(` 空格 | 数字只在点后为数字时收小数；一元规则前移 |
| 4 | text.x | XNull 未把「头部注释之后的独立注释」计入 import 区段，缺 R9.1 段间空行 | 新增 `secComments` 区段 + 段间 1 空行 |

## 诊断（B1-03 第 4 项补齐 + FMT-101）

| # | 输入 | 期望 | 实测 |
|---|---|---|---|
| 1 | 缺文件 | FMT-104 / rc 2 | FMT-104 / rc 2 |
| 2 | 目录 | FMT-104 / rc 2 | FMT-104 / rc 2 |
| 3 | 无参数 | FMT-104 / rc 2 | FMT-104 / rc 2 |
| 4 | 非法 UTF-8 | FMT-102 / rc 2 | FMT-102 / rc 2（`utf8Valid`） |
| 5 | 未闭合字符串 | FMT-101 / rc 2 | FMT-101 / rc 2 |
| 6 | 未闭合块注释 | FMT-101 / rc 2 | FMT-101 / rc 2 |

## 证据

`command.txt`、`run.sh`（一键复现）、`rerun/`（权威输出：`exit_code.txt`、`env.txt`、`artifact.sha256`、`diagnostics.log`、`go-test-all.log`、`*-diff.txt`、`*-idem-*.txt`）。

## 已知缺口

1. XNull 版批处理仍按「一文件一进程」驱动（`impl/xnfmt/xnfmt`）；同进程多文件曾遇信号 11，未在本卡排查。
2. 诊断位置列号统一输出 `0:0`（Go oracle 输出精确 line:col）；码型与退出码已对齐，位置精度为已知差异。
3. Go oracle 与 XNull 版均为“文本级”格式化；AST 结构化排版属 v2。
