# B1-03 验收（自举线 E4 重跑，权威口径）

> 本文件取代 `evidence/M6-B1-03/report.md` 的 FAIL 结论（该报告基于 B1-02 旧二进制与占位 Go oracle）。
> 基线：main `f63fcba` 的 155 个 `.x`；union：本树 `git ls-files '*.x'`（156）。
> 被测提交：`0d8c985`（pod/e4-codegen）；重跑脚本 `evidence/M6-B1-03/e4/run.sh`；输出 `evidence/M6-B1-03/e4/rerun/`。

## 结论

| 指标 | 目标 | 实测 |
|---|---|---|
| 逐字节差异（基线 155） | 0 | **0**（`rerun/base155-diff.txt` 空） |
| 逐字节差异（union 156） | 0 | **0**（`rerun/union-diff.txt` 空） |
| 幂等（Go / XNull，两语料） | 0 违约 | **0 / 0**（`rerun/*-idem-*.txt` 空） |
| 工具失败 | 0 | 0 |
| 异常输入诊断 | 4/4 | **3/4**（缺文件、目录、无参数 → FMT-104 rc=2；非法 UTF-8 rc=0） |
| 回归 `go test ./...` | 绿 | **绿**（`rerun/go-test-all.log`） |

## 覆盖的 4 处历史差异

| # | 文件 | 修法 |
|---|---|---|
| 1 | `evidence/M1-TUPLE-01/cli/tuple-ok.x` | XNull：`$"…"` 整体 token + `===` 单 token |
| 2 | `evidence/M1-TUPLE-01/cli/tuple-switch.x` | XNull：`case` 计入控制关键字（`(` 前 1 空格） |
| 3 | `evidence/M6-B0-05/before/branch-tuple-recv.x` | Go+XN：数字不吞点后标识符；一元 `!` 与 `(` 0 空格 |
| 4 | `impl/lib/xdk/text.x` | XNull：独立注释计入 import 区段，R9.1 段间 1 空行 |

## 产物

- Go oracle：`impl/internal/xnfmt` + `impl/cmd/xnfmt`（B1-01，来自 `wt/e6-toolchain@8ed0153`），sha256 `7acfc46b…`
- XNull 版：`impl/xnfmt/xnfmt.x`（B1-02），经 `xnull build` 产出，sha256 `699c3006…`
- 记录：`rerun/env.txt`（HEAD/base）、`rerun/artifact.sha256`、`rerun/exit_code.txt`

## 未通过项与依赖

- **非法 UTF-8（1/4）**：XNull 无字节级校验能力；需运行时线（E5）提供 `xdkc_utf8_valid(String) -> Bool`（或等价入口），绑定后可补。**不阻塞 0 差异主判据**，但 B1 门诊断项仍缺 1。

## 送 QA1

独立复验命令：`./evidence/M6-B1-03/e4/run.sh f63fcba`；判据：两处 `diff-*` 空、两处 `*-idem-*` 空、`go-test-all` 绿。
