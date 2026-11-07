# SSOT 看板（脚本生成，手改即作废）

- 生成时间：2026-11-07 19:44:31 +0800
- 仓库：`XNull-Lang`　分支：`main`　HEAD：`18a69f1`
- 窗口：近 7 天（起点提交 `852c141`）
- 数据源：git log / go test / impl/docs/conformance/status.tsv / evidence/ / handoff/
- 断链协议：ADR-003（接力棒 + last-green；`--record-green` 在测试绿时记录 HEAD）

## 四数

| # | 指标 | 值 |
|---|---|---|
| 1 | 窗口内 commit 数 | 383 |
| 2 | 锚点翻转（PASS） | 30（起点 30，Δ+0） |
| 3 | 全量测试 | 绿（11 包 ok） |
| 4 | 门进度 | B0 6 卡（有证据 5） / B1 3 卡（有证据 3） / B2 0 卡 / B3 0 卡 / B4 0 卡；收件箱/门/M1门.md；收件箱/门/M6-B0门.md；收件箱/门/M6-B1门.md |

## 台账锚点（status.tsv 已登记 45 行）

| 状态 | 数量 |
|---|---|
| PASS | 30 |
| 部分 | 11 |
| 未实现 | 4 |
| N/A | 0 |

> 未登记锚点在台账中显示「未实现」（口径见 impl/docs/conformance/ledger-restructure.md）。

## 生产线进度（窗口内 commit / 最近一条）

| 线 | Owner | commit | 最近提交 |
|---|---|---|---|
| 前端线 | E2 | 48 | c90880d fix(sema): BND-06 数据枚举项字段不可变/不可 new |
| 自举线 | E4 | 50 | 7181fda fix(codegen): INT-01 try 目标支持成员方法 + 返回路径 |
| 运行时线 | E5 | 11 | 9e6de30 fix(runtime): 弱槽位目标死亡后解绑，destroy 不再触达已释放 |
| QA 线 | QA1 | 101 | e2f943c docs(S2): 门报告/ADR-004/回执/QA evidence 入库（ |
| 发布线 | COO | 0 | — |

## 最近提交（最多 15 条）

| sha | 日期 | 作者 | 主题 |
|---|---|---|---|
| 18a69f1 | 11-07 19:44 | 李飞恒 | sign(S2): BND-06 + PCTOR-01 PASS; BND-07/08/INT-01 gaps reco |
| e2f943c | 11-07 19:27 | 李飞恒 | docs(S2): 门报告/ADR-004/回执/QA evidence 入库（防工作区丢失） |
| 4b574dd | 11-07 19:19 | 李飞恒 | recover(S2): restore code+books after main race; status PASS |
| 41891c3 | 11-07 19:13 | 李飞恒 | merge: E2 BND-06 enum item immutability into recovery |
| c90880d | 11-07 19:12 | 李飞恒 | fix(sema): BND-06 数据枚举项字段不可变/不可 new |
| a5a635f | 11-07 19:11 | 李飞恒 | merge: E4 INT-01 try member call + defer chain into main |
| 37d1dec | 11-07 19:11 | 李飞恒 | docs(S2): E4 INT-01 try 成员调用回执 |
| 7181fda | 11-07 19:11 | 李飞恒 | fix(codegen): INT-01 try 目标支持成员方法 + 返回路径祖先 defer 链 |
| feabde1 | 11-07 19:08 | 李飞恒 | merge: QA S2 sign-off BND-04 PASS, BND-06/INT-01 FAIL into m |
| fa4fbf9 | 11-07 19:08 | 李飞恒 | merge: E2 BND-07/08 singleton/factory sema 名称空间 into main |
| 1b1d12e | 11-07 19:06 | 李飞恒 | feat(sema): BND-07/08 singleton/factory 名称空间与禁止面 |
| 77694e8 | 11-07 19:05 | 李飞恒 | test(qa): BND-04 record generic struct codegen boundary on m |
| 6cb5ffe | 11-07 19:05 | 李飞恒 | test(qa): S2 sign-off BND-04 PASS, BND-06/INT-01 FAIL on mai |
| e360394 | 11-07 19:03 | 李飞恒 | docs(S2): E4 STRUCT-01 可空值字段回执 |
| cf3e084 | 11-07 19:03 | 李飞恒 | merge: E4 STRUCT-01 nullable value fields into main |

## 断链与最后绿点（ADR-003）

| 线 | last-green | 落后 HEAD | 状态 | 最近 commit |
|---|---|---|---|---|
| 前端线 | c90880d | 36 | 有效（该线最近提交） | ba4458a（16h15m） |
| 自举线 | 18a69f1 | 0 | 有效（该线最近提交） | fe19e7c（18h41m） |
| 运行时线 | 9e6de30 | 113 | 有效（该线最近提交） | db74cc7（21h18m） |
| QA 线 | e2f943c | 1 | 有效（支撑线：活动路径最近提交） | 2597b36（18h21m） |
| 发布线 | 3890532 | 175 | 有效（支撑线：活动路径最近提交） | — |

## 接力棒（handoff/）

已有接力棒 20 根；应覆盖卡片 74 张。

| 卡片 | 接力棒 | 字段 |
|---|---|---|
| B0-02 | 缺失 | — |
| B0-07b | 缺失 | — |
| B0-07c | 有 | 完整 |
| B1-02 | 有 | 完整 |
| B1-03 | 有 | 完整 |
| BYTES-RUNTIME | 有 | 缺 已知缺口 |
| E5-ABI-v1 | 有 | 完整 |
| ERR-01-B2 | 有 | 完整 |
| EXP-023 | 有 | 完整 |
| FIX-E2-INT64 | 缺失 | — |
| FIX-ERR-B2 | 缺失 | — |
| G11 | 有 | 完整 |
| GEN-01 | 有 | 完整 |
| GEN-01-sema | 有 | 完整 |
| GEN-G11 | 缺失 | — |
| GEN-G11-reverify | 缺失 | — |
| IDE-SOURCE | 有 | 完整 |
| M1-BLD-01 | 缺失 | — |
| M1-BLD-01-reverify-d620ea5 | 缺失 | — |
| M1-DET-01 | 缺失 | — |
| M1-DET-01-fix | 缺失 | — |
| M1-DET-01-reverify-d620ea5 | 缺失 | — |
| M1-ENTRY-01 | 缺失 | — |
| M1-ENTRY-01-qa | 缺失 | — |
| M1-ENTRY-01-reverify-2026-11-07 | 缺失 | — |
| M1-ENTRY-01-reverify-91c89c0 | 缺失 | — |
| M1-ENTRY-01-reverify-d620ea5 | 缺失 | — |
| M1-ERR-01 | 缺失 | — |
| M1-ERR-01-fix | 缺失 | — |
| M1-ERR-01-fix2 | 缺失 | — |
| M1-ERR-01-qa | 缺失 | — |
| M1-ERR-01-reverify-d620ea5 | 缺失 | — |
| M1-GEN-01 | 缺失 | — |
| M1-GEN-01-sema | 缺失 | — |
| M1-PKG-01 | 缺失 | — |
| M1-PKG-01-qa | 缺失 | — |
| M1-TUPLE-01 | 缺失 | — |
| M1-TUPLE-01-qa | 缺失 | — |
| M1-TUPLE-01-reverify-91c89c0 | 缺失 | — |
| M1-TUPLE-01-reverify-d620ea5 | 缺失 | — |
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
| NEG-01 | 缺失 | — |
| NEG-1.3a | 缺失 | — |
| NEG-3 | 缺失 | — |
| NEG-INTERP | 缺失 | — |
| P1-INIT-FWD | 缺失 | — |
| PKG-01 | 有 | 缺 已知缺口 |
| PKG-F1 | 缺失 | — |
| PKG-F2 | 缺失 | — |
| PKG-F3 | 缺失 | — |
| QA1-B1-03 | 有 | 完整 |
| QA1-EXP-004 | 有 | 完整 |
| QA1-EXP-004b | 有 | 缺 已知缺口 |
| QA1-GEN-01 | 有 | 缺 已知缺口 |
| QA1-anchors-2026-11-07 | 缺失 | — |
| QA1-verify-2026-11-07 | 缺失 | — |
| S2-E5-deinit | 有 | 缺 已知缺口 |
| S2-E5-weak | 有 | 完整 |
| TUPLE-01 | 缺失 | — |
| TUPLE-OPT | 缺失 | — |
| XFRONT-FIX-NEG-GEN | 缺失 | — |
| XNFMT-CI | 有 | 完整 |
| e5-2026-11-07 | 缺失 | — |

## 告警（ADR-003 断链判据）

- QA 线：18h21m 无 commit（ADR-003 2h 阈值）
- 前端线：16h15m 无 commit（ADR-003 2h 阈值）
- 接力棒缺失：B0-02
- 接力棒缺失：B0-07b
- 接力棒缺失：FIX-E2-INT64
- 接力棒缺失：FIX-ERR-B2
- 接力棒缺失：GEN-G11
- 接力棒缺失：GEN-G11-reverify
- 接力棒缺失：M1-BLD-01
- 接力棒缺失：M1-BLD-01-reverify-d620ea5
- 接力棒缺失：M1-DET-01
- 接力棒缺失：M1-DET-01-fix
- 接力棒缺失：M1-DET-01-reverify-d620ea5
- 接力棒缺失：M1-ENTRY-01
- 接力棒缺失：M1-ENTRY-01-qa
- 接力棒缺失：M1-ENTRY-01-reverify-2026-11-07
- 接力棒缺失：M1-ENTRY-01-reverify-91c89c0
- 接力棒缺失：M1-ENTRY-01-reverify-d620ea5
- 接力棒缺失：M1-ERR-01
- 接力棒缺失：M1-ERR-01-fix
- 接力棒缺失：M1-ERR-01-fix2
- 接力棒缺失：M1-ERR-01-qa
- 接力棒缺失：M1-ERR-01-reverify-d620ea5
- 接力棒缺失：M1-GEN-01
- 接力棒缺失：M1-GEN-01-sema
- 接力棒缺失：M1-PKG-01
- 接力棒缺失：M1-PKG-01-qa
- 接力棒缺失：M1-TUPLE-01
- 接力棒缺失：M1-TUPLE-01-qa
- 接力棒缺失：M1-TUPLE-01-reverify-91c89c0
- 接力棒缺失：M1-TUPLE-01-reverify-d620ea5
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
- 接力棒缺失：NEG-01
- 接力棒缺失：NEG-1.3a
- 接力棒缺失：NEG-3
- 接力棒缺失：NEG-INTERP
- 接力棒缺失：P1-INIT-FWD
- 接力棒缺失：PKG-F1
- 接力棒缺失：PKG-F2
- 接力棒缺失：PKG-F3
- 接力棒缺失：QA1-anchors-2026-11-07
- 接力棒缺失：QA1-verify-2026-11-07
- 接力棒缺失：TUPLE-01
- 接力棒缺失：TUPLE-OPT
- 接力棒缺失：XFRONT-FIX-NEG-GEN
- 接力棒缺失：e5-2026-11-07
- 接力棒缺字段：BYTES-RUNTIME（已知缺口）
- 接力棒缺字段：PKG-01（已知缺口）
- 接力棒缺字段：QA1-EXP-004b（已知缺口）
- 接力棒缺字段：QA1-GEN-01（已知缺口）
- 接力棒缺字段：S2-E5-deinit（已知缺口）
- 自举线：18h41m 无 commit（ADR-003 2h 阈值）
- 运行时线：21h18m 无 commit（ADR-003 2h 阈值）

## evidence（按最近修改，最多 10 项；共 106 项）

| 目录 | 文件数 | 最近修改 |
|---|---|---|
| S2-QA | 3885 | 11-07 19:41 |
| S2-BND0708 | 6 | 11-07 19:27 |
| S2-BND06b | 6 | 11-07 19:27 |
| QA1-verify-2026-11-07 | 22 | 11-07 19:27 |
| QA1-anchors-2026-11-07 | 49 | 11-07 19:27 |
| M1-TUPLE-01-reverify-d620ea5 | 51 | 11-07 19:27 |
| M1-TUPLE-01-reverify-91c89c0 | 114 | 11-07 19:27 |
| M1-ERR-01-reverify-d620ea5 | 15 | 11-07 19:27 |
| M1-ENTRY-01-reverify-d620ea5 | 120 | 11-07 19:27 |
| M1-ENTRY-01-reverify-91c89c0 | 121 | 11-07 19:27 |

---
本文件由 `xnull dev board` 生成；手工编辑无效。
