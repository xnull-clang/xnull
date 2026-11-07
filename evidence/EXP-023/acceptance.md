# xnull dev board 首版（P0，ADR-002 T+2：SSOT 看板可用）

## 决定要点

- 唯一看板由 `xnull dev board` 从四个数据源现场生成：git log（窗口内提交/生产线归属）、`go test ./...`、`impl/docs/conformance/status.tsv`（锚点）、`evidence/`（卡片与门进度）。
- **默认输出 stdout、不落盘**：避免再产生可手改的快照文件；`--write` 仅作显式导出。
- 输出首行固定声明「SSOT 看板（脚本生成，手改即作废）」。

## 四数口径

| # | 指标 | 计算方式 |
|---|---|---|
| 1 | 窗口内 commit 数 | `git log --since=<窗口>` 计数（默认 7 天） |
| 2 | 锚点翻转 | 当前 `status.tsv` PASS 数 − 窗口起点提交的 PASS 数 |
| 3 | 全量测试 | 现场 `go test ./... -count=1 -timeout 300s`，绿=全部 ok |
| 4 | 门进度 | `evidence/` 中 B0–B4 卡数 + `收件箱/**/*门*.md`（存在时） |

## 生产线归属（ADR-002：3 生产 + 2 支撑）

按提交改动路径归类：`xfront|sema` → 前端线 E2；`codegen|xnfmt|cmd` → 自举线 E4；`runtime|bindings` → 运行时线 E5；`evidence|收件箱` → QA 线；`xnull/` → 发布线。

## 自检

| 项 | 结果 |
|---|---|
| 单元测试（临时 git 仓库 fixture） | 通过：四数、锚点 Δ、evidence、非 git 报错、路径归类 |
| 本工作树现场生成 | exit 0；四数=71 commits / 10 PASS(Δ+0) / 绿(11 包) / B0 7 卡·B1 1 卡 |
| 无快照 | 未提交任何看板静态文件 |

## 已知边界（首版）

1. 生产线归属为路径规则，跨线提交只计首个匹配线（单值）。
2. 锚点基线取窗口内最早提交的 `status.tsv`；窗口内无提交时 Δ=0。
3. `go test` 现场执行约 20–60s；`--no-test` 可跳过但四数第 3 项显示「未运行」。
