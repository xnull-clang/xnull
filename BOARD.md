# SSOT 看板（脚本生成，手改即作废）

- 生成时间：2026-11-07 14:33:22 +0800
- 仓库：`XNull-Lang`　分支：`main`　HEAD：`a65fd4d`
- 窗口：近 7 天（起点提交 `852c141`）
- 数据源：git log / go test / impl/docs/conformance/status.tsv / evidence/ / handoff/
- 断链协议：ADR-003（接力棒 + last-green；`--record-green` 在测试绿时记录 HEAD）

## 四数

| # | 指标 | 值 |
|---|---|---|
| 1 | 窗口内 commit 数 | 177 |
| 2 | 锚点翻转（PASS） | 10（起点 10，Δ+0） |
| 3 | 全量测试 | 绿（11 包 ok） |
| 4 | 门进度 | B0 6 卡（有证据 5） / B1 3 卡（有证据 3） / B2 0 卡 / B3 0 卡 / B4 0 卡；收件箱/门/M6-B0门.md；收件箱/门/M6-B1门.md |

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
| 自举线 | E4 | 20 | 0d8c985 feat(xnfmt): adopt B1-01 oracle + B1-02  |
| 运行时线 | E5 | 5 | 2948e82 feat(runtime): xdkc_utf8_valid + utf8Val |
| QA 线 | QA1 | 62 | f53f6fb fix(interp): reference/string identity f |
| 发布线 | COO | 0 | — |

## 最近提交（最多 15 条）

| sha | 日期 | 作者 | 主题 |
|---|---|---|---|
| a65fd4d | 11-07 14:33 | 李飞恒 | handoff(PKG-01): TUPLE interp F1/F2 green on e91e33c; NEG 9  |
| e91e33c | 11-07 14:32 | 李飞恒 | merge(pod/e3-interp): NEG interp closure + TUPLE-01 F1/F2 id |
| d349f6a | 11-07 14:30 | 李飞恒 | merge: pod/e4-codegen B1-02/B1-03 xnfmt into main (cac6686) |
| c4d4c89 | 11-07 14:30 | 李飞恒 | handoff(B1): root batons + last-green + QA1 request (E4) |
| 640044f | 11-07 14:30 | 李飞恒 | fix(cli): include E6 machine.go missing from main merge (res |
| 4d614cc | 11-07 14:29 | 李飞恒 | Merge branch 'main' into pod/e4-codegen |
| 7945c4f | 11-07 14:28 | 李飞恒 | receipt(B1-02/B1-03): E4 closure receipts; supersede old FAI |
| a0e4038 | 11-07 14:27 | 李飞恒 | docs(handoff): NEG 51/60, interp items incl TUPLE F1/F2 clos |
| 6b6e987 | 11-07 14:27 | 李飞恒 | merge: pod/e6-toolchain into main (board + IDE sources) |
| f53f6fb | 11-07 14:27 | 李飞恒 | fix(interp): reference/string identity for tuple equality (T |
| d28da32 | 11-07 14:27 | 李飞恒 | feat(cli): IDE new/check command wiring (IDE-SOURCE) |
| 242005f | 11-07 14:27 | 李飞恒 | merge: main into pod/e6-toolchain (IDE + board integration) |
| 6dc2bfa | 11-07 14:25 | 李飞恒 | handoff(B1-02): record E5 notification |
| 96f34b0 | 11-07 14:25 | 李飞恒 | docs(handoff): IDE-SOURCE baton |
| d948276 | 11-07 14:25 | 李飞恒 | handoff(E4): last-green 9832bfb |

## 断链与最后绿点（ADR-003）

| 线 | last-green | 落后 HEAD | 状态 | 最近 commit |
|---|---|---|---|---|
| 前端线 | 49cbb27 | 52 | 有效（该线最近提交） | ba4458a（11h04m） |
| 自举线 | b23fa42 | 0 | 失效（非 HEAD 祖先）（该线最近提交） | fe19e7c（13h30m） |
| 运行时线 | 2948e82 | 35 | 有效（该线最近提交） | db74cc7（16h07m） |
| QA 线 | b23fa42 | 0 | 失效（非 HEAD 祖先）（支撑线：活动路径最近提交） | 2597b36（13h10m） |
| 发布线 | d000b43 | 46 | 有效（支撑线：活动路径最近提交） | — |

## 接力棒（handoff/）

已有接力棒 13 根；应覆盖卡片 47 张。

| 卡片 | 接力棒 | 字段 |
|---|---|---|
| B0-02 | 缺失 | — |
| B0-07b | 缺失 | — |
| B0-07c | 有 | 缺 已知缺口 |
| B1-02 | 有 | 完整 |
| B1-03 | 有 | 完整 |
| E5-ABI-v1 | 有 | 完整 |
| ERR-01-B2 | 有 | 完整 |
| EXP-023 | 有 | 完整 |
| FIX-E2-INT64 | 缺失 | — |
| FIX-ERR-B2 | 缺失 | — |
| G11 | 有 | 完整 |
| GEN-01 | 有 | 完整 |
| GEN-G11 | 缺失 | — |
| IDE-SOURCE | 有 | 完整 |
| M1-BLD-01 | 缺失 | — |
| M1-DET-01 | 缺失 | — |
| M1-DET-01-fix | 缺失 | — |
| M1-ENTRY-01 | 缺失 | — |
| M1-ENTRY-01-qa | 缺失 | — |
| M1-ERR-01 | 缺失 | — |
| M1-ERR-01-fix | 缺失 | — |
| M1-ERR-01-fix2 | 缺失 | — |
| M1-ERR-01-qa | 缺失 | — |
| M1-GEN-01 | 缺失 | — |
| M1-GEN-01-sema | 缺失 | — |
| M1-PKG-01 | 缺失 | — |
| M1-PKG-01-qa | 缺失 | — |
| M1-TUPLE-01 | 缺失 | — |
| M1-TUPLE-01-qa | 缺失 | — |
| M1-TYPE-01-fix | 缺失 | — |
| M6-B0-01 | 缺失 | — |
| M6-B0-03 | 缺失 | — |
| M6-B0-04 | 缺失 | — |
| M6-B0-05 | 缺失 | — |
| M6-B0-05-sema | 缺失 | — |
| M6-B0-07a | 缺失 | — |
| M6-B0-07c | 缺失 | — |
| M6-B1-01 | 缺失 | — |
| M6-B1-02 | 缺失 | — |
| M6-B1-03 | 缺失 | — |
| NEG | 有 | 完整 |
| NEG-INTERP | 缺失 | — |
| P1-INIT-FWD | 缺失 | — |
| PKG-01 | 有 | 缺 已知缺口 |
| QA1-B1-03 | 有 | 完整 |
| QA1-EXP-004 | 有 | 完整 |
| XFRONT-FIX-NEG-GEN | 缺失 | — |

## 告警（ADR-003 断链判据）

- QA 线：13h10m 无 commit（ADR-003 2h 阈值）
- QA 线：last-green b23fa42 失效（不是 HEAD 祖先）
- 前端线：11h04m 无 commit（ADR-003 2h 阈值）
- 接力棒缺失：B0-02
- 接力棒缺失：B0-07b
- 接力棒缺失：FIX-E2-INT64
- 接力棒缺失：FIX-ERR-B2
- 接力棒缺失：GEN-G11
- 接力棒缺失：M1-BLD-01
- 接力棒缺失：M1-DET-01
- 接力棒缺失：M1-DET-01-fix
- 接力棒缺失：M1-ENTRY-01
- 接力棒缺失：M1-ENTRY-01-qa
- 接力棒缺失：M1-ERR-01
- 接力棒缺失：M1-ERR-01-fix
- 接力棒缺失：M1-ERR-01-fix2
- 接力棒缺失：M1-ERR-01-qa
- 接力棒缺失：M1-GEN-01
- 接力棒缺失：M1-GEN-01-sema
- 接力棒缺失：M1-PKG-01
- 接力棒缺失：M1-PKG-01-qa
- 接力棒缺失：M1-TUPLE-01
- 接力棒缺失：M1-TUPLE-01-qa
- 接力棒缺失：M1-TYPE-01-fix
- 接力棒缺失：M6-B0-01
- 接力棒缺失：M6-B0-03
- 接力棒缺失：M6-B0-04
- 接力棒缺失：M6-B0-05
- 接力棒缺失：M6-B0-05-sema
- 接力棒缺失：M6-B0-07a
- 接力棒缺失：M6-B0-07c
- 接力棒缺失：M6-B1-01
- 接力棒缺失：M6-B1-02
- 接力棒缺失：M6-B1-03
- 接力棒缺失：NEG-INTERP
- 接力棒缺失：P1-INIT-FWD
- 接力棒缺失：XFRONT-FIX-NEG-GEN
- 接力棒缺字段：B0-07c（已知缺口）
- 接力棒缺字段：PKG-01（已知缺口）
- 自举线：13h30m 无 commit（ADR-003 2h 阈值）
- 自举线：last-green b23fa42 失效（不是 HEAD 祖先）
- 运行时线：16h07m 无 commit（ADR-003 2h 阈值）

## evidence（按最近修改，最多 10 项；共 61 项）

| 目录 | 文件数 | 最近修改 |
|---|---|---|
| M1-ERR-01-qa | 22 | 11-07 14:36 |
| GEN-G11 | 6 | 11-07 14:34 |
| NEG-INTERP | 11 | 11-07 14:32 |
| M6-B1-03 | 68 | 11-07 14:30 |
| M6-B1-02 | 1 | 11-07 14:30 |
| M6-B0-07c | 20 | 11-07 14:30 |
| B1-02 | 5 | 11-07 14:30 |
| M6-B1-01 | 17 | 11-07 14:27 |
| EXP-023 | 3 | 11-07 14:27 |
| FIX-ERR-B2 | 14 | 11-07 14:27 |

---
本文件由 `xnull dev board` 生成；手工编辑无效。
