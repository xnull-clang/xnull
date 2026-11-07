# SSOT 看板（脚本生成，手改即作废）

- 生成时间：2026-11-07 14:08:38 +0800
- 仓库：`XNull-Lang`　分支：`main`　HEAD：`ee5bace`
- 窗口：近 7 天（起点提交 `852c141`）
- 数据源：git log / go test / impl/docs/conformance/status.tsv / evidence/ / handoff/
- 断链协议：ADR-003（接力棒 + last-green；`--record-green` 在测试绿时记录 HEAD）

## 四数

| # | 指标 | 值 |
|---|---|---|
| 1 | 窗口内 commit 数 | 138 |
| 2 | 锚点翻转（PASS） | 10（起点 10，Δ+0） |
| 3 | 全量测试 | 绿（9 包 ok） |
| 4 | 门进度 | B0 8 卡 / B1 1 卡 / B2 0 卡 / B3 0 卡 / B4 0 卡；收件箱/门/M6-B0门.md |

## 台账锚点（status.tsv 已登记 35 行）

| 状态 | 数量 |
|---|---|
| PASS | 10 |
| 部分 | 19 |
| 未实现 | 6 |
| N/A | 0 |

> 未登记锚点在台账中显示「未实现」（口径见 impl/docs/conformance/ledger-restructure.md）。

## 生产线进度（窗口内 commit / 最近一条）

| 线 | Owner | commit | 最近提交 |
|---|---|---|---|
| 前端线 | E2 | 23 | 49cbb27 merge(pod/e2-sema): SYNCED 9848d06 |
| 自举线 | E4 | 17 | 99185dd fix(ffi): native String return uses cons |
| 运行时线 | E5 | 4 | 5161769 feat(ffi): add readFileText/writeFileTex |
| QA 线 | QA1 | 53 | a5fb086 test(interp): NEG runtime negatives for  |
| 发布线 | COO | 0 | — |

## 最近提交（最多 15 条）

| sha | 日期 | 作者 | 主题 |
|---|---|---|---|
| ee5bace | 11-07 14:08 | 李飞恒 | chore(board): generate SSOT board from git/test/ledger/evide |
| 1b9f096 | 11-07 14:06 | 李飞恒 | docs(handoff): NEG-01 51/60, interp items closed |
| 8beda11 | 11-07 14:03 | 李飞恒 | docs: ADR-003 chain-recovery protocol and handoff template |
| 548a06d | 11-07 13:59 | 李飞恒 | docs: ADR-002 trial reduced to 6h; define 3 production + 2 s |
| 3034293 | 11-07 13:57 | 李飞恒 | merge(pod/e3-interp): ERR-01 B1 closure-try verified + NEG i |
| a5fb086 | 11-07 13:57 | 李飞恒 | test(interp): NEG runtime negatives for Result misuse |
| 2b7c65c | 11-07 13:55 | 李飞恒 | docs: adopt ADR-001 five-line governance; archive old proces |
| d000b43 | 11-07 13:50 | 李飞恒 | docs: archive outdated inbox and root docs |
| f63fcba | 11-07 13:17 | 李飞恒 | merge(pod/e3-interp): SYNCED 37cbe18 |
| 37cbe18 | 11-07 13:15 | 李飞恒 | sync: merge main 49cbb27 into pod/e3-interp (BLD-01 x P1-INI |
| 49cbb27 | 11-07 13:11 | 李飞恒 | merge(pod/e2-sema): SYNCED 9848d06 |
| 8a50e84 | 11-07 13:09 | 李飞恒 | merge(pod/c2-rd2): SYNCED eaf3c41 |
| eaf3c41 | 11-07 13:07 | 李飞恒 | docs(evidence): BLD-01 合 main 90fcdc3 复跑证据（sema 参数检查双保留；28/2 |
| 9079857 | 11-07 13:07 | 李飞恒 | merge: main 90fcdc3（c1-rd1/c1-rd2）into pod/c2-rd2 |
| 90fcdc3 | 11-07 13:03 | 李飞恒 | merge(pod/c1-rd2): SYNCED 8650405 |

## 断链与最后绿点（ADR-003）

| 线 | last-green | 状态 | 最近 commit |
|---|---|---|---|
| 前端线 | ee5bace | 有效 | ba4458a（10h39m） |
| 自举线 | ee5bace | 有效 | fe19e7c（13h06m） |
| 运行时线 | ee5bace | 有效 | db74cc7（15h42m） |
| QA 线 | ee5bace | 有效 | 2597b36（12h46m） |
| 发布线 | ee5bace | 有效 | — |

## 接力棒（handoff/）

已有接力棒 1 根；应覆盖卡片 1 张。

| 卡片 | 接力棒 | 字段 |
|---|---|---|
| NEG | 有 | 完整 |

## 告警（ADR-003 断链判据）

- QA 线：12h46m 无 commit（ADR-003 2h 阈值）
- 前端线：10h39m 无 commit（ADR-003 2h 阈值）
- 自举线：13h06m 无 commit（ADR-003 2h 阈值）
- 运行时线：15h42m 无 commit（ADR-003 2h 阈值）

## evidence（按最近修改，最多 10 项；共 53 项）

| 目录 | 文件数 | 最近修改 |
|---|---|---|
| D1D3E11-MAIN | 5 | 11-07 13:57 |
| M6-B1-03 | 28 | 11-07 13:25 |
| INTEG-final-e2 | 17 | 11-07 13:21 |
| INTEG-final-c3rd1 | 90 | 11-07 13:21 |
| INTEG-final-c3rd2 | 7 | 11-07 13:20 |
| INTEG-final-c2rd1 | 10 | 11-07 13:20 |
| P1-INIT-FWD | 11 | 11-07 13:17 |
| M1-ERR-01-fix | 7 | 11-07 13:17 |
| INTEG-c2-rd1 | 30 | 11-07 13:13 |
| FIX-E2-INT64 | 13 | 11-07 13:11 |

---
本文件由 `xnull dev board` 生成；手工编辑无效。
