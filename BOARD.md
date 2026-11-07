# SSOT 看板（脚本生成，手改即作废）

- 生成时间：2026-11-08 04:45:56 +0800
- 仓库：`XNull-Lang`　分支：`main`　HEAD：`6b73235`
- 窗口：近 7 天（起点提交 `852c141`）
- 数据源：git log / go test / impl/docs/conformance/status.tsv / evidence/ / handoff/
- 断链协议：ADR-003（接力棒 + last-green；`--record-green` 在测试绿时记录 HEAD）

## 四数

| # | 指标 | 值 |
|---|---|---|
| 1 | 窗口内 commit 数 | 601 |
| 2 | 锚点翻转（PASS） | 75（起点 75，Δ+0） |
| 3 | 全量测试 | 红（2 包失败：xnull.dev/xnull/internal/codegen, xnull.dev/xnull/internal/devtool） |
| 4 | 门进度 | B0 6 卡（有证据 5） / B1 3 卡（有证据 3） / B2 0 卡 / B3 0 卡 / B4 0 卡；收件箱/门/GATE-01门.md；收件箱/门/M1门.md；收件箱/门/M2门.md；收件箱/门/M6-B0门.md；收件箱/门/M6-B1门.md；收件箱/门/S3门.md；收件箱/门/S4门.md；收件箱/门/S5门.md |

## 台账锚点（status.tsv 已登记 84 行）

| 状态 | 数量 |
|---|---|
| PASS | 75 |
| 部分 | 9 |
| 未实现 | 0 |
| N/A | 0 |

> 未登记锚点在台账中显示「未实现」（口径见 impl/docs/conformance/ledger-restructure.md）。

## 生产线进度（窗口内 commit / 最近一条）

| 线 | Owner | commit | 最近提交 |
|---|---|---|---|
| 前端线 | E2 | 71 | 397a8b3 feat(sema): S6-05 xdk.text Format/parse/ |
| 自举线 | E4 | 91 | 4d8928c feat(xdk): 8 package skeletons + import  |
| 运行时线 | E5 | 17 | 0e5950b merge: E5 S6-02 runtime 面 合入 main |
| QA 线 | QA1 | 116 | 4201b28 docs(S5): E4 S5-04 跨任务内存回执 |
| 发布线 | COO | 0 | — |

## 最近提交（最多 15 条）

| sha | 日期 | 作者 | 主题 |
|---|---|---|---|
| 6b73235 | 11-08 04:45 | 李飞恒 | docs(ledger): align GEN-01/NEG-01/PKG-01 PASS with M1 accept |
| 6462eaa | 11-08 04:41 | 李飞恒 | gate(S5): S5 门报告 12/12 通过; AGENTS/索引同步 |
| fd1d7be | 11-08 04:41 | 李飞恒 | qa(S5): SCHED-01 PASS — S5 12/12; status PASS=75 |
| 11bf22f | 11-08 04:39 | 李飞恒 | merge: E3 S6-08 包骨架 + loader 合入 main |
| 96aa3da | 11-08 04:39 | 李飞恒 | merge: E2 S6-05 text sema 签名 合入 main |
| 7661f61 | 11-08 04:38 | 李飞恒 | merge: E5 SCHED-01 载体池 + 伴生执行器 合入 main |
| 397a8b3 | 11-08 04:38 | 李飞恒 | feat(sema): S6-05 xdk.text Format/parse/编码/Regex 签名 |
| 4d6b5c3 | 11-08 04:38 | 李飞恒 | receipt(S6-08): xdk package skeletons + loader |
| 4d8928c | 11-08 04:38 | 李飞恒 | feat(xdk): 8 package skeletons + import loader + matrix chec |
| 0e5950b | 11-08 04:33 | 李飞恒 | merge: E5 S6-02 runtime 面 合入 main |
| b1eef1e | 11-08 04:33 | 李飞恒 | merge: E3 S6-07 collections 合入 main |
| a208d67 | 11-08 04:33 | 李飞恒 | merge: E2 S6-01 XDK 八包签名 合入 main |
| 047fbd6 | 11-08 04:33 | 李飞恒 | merge: E4 S6-02 xdk.runtime 发射面 合入 main |
| 1acd2b1 | 11-08 04:33 | 李飞恒 | merge: E3 S6-06 xdk.errors 源码单元 合入 main |
| 47fd089 | 11-08 04:33 | 李飞恒 | feat(runtime): 载体池 + 伴生执行器（SCHED-01） |

## 断链与最后绿点（ADR-003）

| 线 | last-green | 落后 HEAD | 状态 | 最近 commit |
|---|---|---|---|---|
| 前端线 | 39d0273 | 244 | 有效（该线最近提交） | ba4458a（25h17m） |
| 自举线 | 4f63150 | 150 | 有效（该线最近提交） | fe19e7c（27h43m） |
| 运行时线 | 9e90d4e | 303 | 有效（该线最近提交） | db74cc7（30h19m） |
| QA 线 | e4b8f21 | 151 | 有效（支撑线：活动路径最近提交） | 2597b36（27h23m） |
| 发布线 | 3890532 | 393 | 有效（支撑线：活动路径最近提交） | — |

## 接力棒（handoff/）

已有接力棒 34 根；应覆盖卡片 104 张。

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
| QA-BOUND03 | 缺失 | — |
| QA-S3A | 缺失 | — |
| QA-S3A2 | 缺失 | — |
| QA-S4A | 缺失 | — |
| QA-S5A | 缺失 | — |
| QA1-B1-03 | 有 | 完整 |
| QA1-EXP-004 | 有 | 完整 |
| QA1-EXP-004b | 有 | 缺 已知缺口 |
| QA1-GEN-01 | 有 | 缺 已知缺口 |
| QA1-anchors-2026-11-07 | 缺失 | — |
| QA1-verify-2026-11-07 | 缺失 | — |
| S2-E5-BND10 | 有 | 完整 |
| S2-E5-MEM01 | 有 | 完整 |
| S2-E5-deinit | 有 | 缺 已知缺口 |
| S2-E5-weak | 有 | 完整 |
| S3-01 | 有 | 完整 |
| S3-04-E5 | 有 | 完整 |
| S3-07 | 有 | 完整 |
| S3-08 | 有 | 完整 |
| S4-E5 | 有 | 完整 |
| S5-00-接口冻结 | 有 | 完整 |
| S5-01 | 有 | 完整 |
| S5-02 | 有 | 完整 |
| S5-03 | 缺失 | — |
| S5-03-E5 | 有 | 完整 |
| S5-04 | 缺失 | — |
| S5-05 | 缺失 | — |
| S5-QA | 缺失 | — |
| S5-SCHED01 | 有 | 完整 |
| S6-01 | 缺失 | — |
| S6-02 | 缺失 | — |
| S6-03 | 缺失 | — |
| S6-03-E5 | 有 | 完整 |
| S6-04-E5 | 有 | 完整 |
| S6-05 | 缺失 | — |
| S6-06 | 缺失 | — |
| S6-07 | 缺失 | — |
| S6-08 | 缺失 | — |
| TUPLE-01 | 缺失 | — |
| TUPLE-OPT | 缺失 | — |
| XFRONT-FIX-NEG-GEN | 缺失 | — |
| XNFMT-CI | 有 | 完整 |
| e5-2026-11-07 | 缺失 | — |

## 告警（ADR-003 断链判据）

- QA 线：27h23m 无 commit（ADR-003 2h 阈值）
- 前端线：25h17m 无 commit（ADR-003 2h 阈值）
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
- 接力棒缺失：QA-BOUND03
- 接力棒缺失：QA-S3A
- 接力棒缺失：QA-S3A2
- 接力棒缺失：QA-S4A
- 接力棒缺失：QA-S5A
- 接力棒缺失：QA1-anchors-2026-11-07
- 接力棒缺失：QA1-verify-2026-11-07
- 接力棒缺失：S5-03
- 接力棒缺失：S5-04
- 接力棒缺失：S5-05
- 接力棒缺失：S5-QA
- 接力棒缺失：S6-01
- 接力棒缺失：S6-02
- 接力棒缺失：S6-03
- 接力棒缺失：S6-05
- 接力棒缺失：S6-06
- 接力棒缺失：S6-07
- 接力棒缺失：S6-08
- 接力棒缺失：TUPLE-01
- 接力棒缺失：TUPLE-OPT
- 接力棒缺失：XFRONT-FIX-NEG-GEN
- 接力棒缺失：e5-2026-11-07
- 接力棒缺字段：BYTES-RUNTIME（已知缺口）
- 接力棒缺字段：PKG-01（已知缺口）
- 接力棒缺字段：QA1-EXP-004b（已知缺口）
- 接力棒缺字段：QA1-GEN-01（已知缺口）
- 接力棒缺字段：S2-E5-deinit（已知缺口）
- 自举线：27h43m 无 commit（ADR-003 2h 阈值）
- 运行时线：30h19m 无 commit（ADR-003 2h 阈值）

## evidence（按最近修改，最多 10 项；共 163 项）

| 目录 | 文件数 | 最近修改 |
|---|---|---|
| S6-04-E5 | 5 | 11-08 04:48 |
| S6-03-E5 | 4 | 11-08 04:48 |
| S6-05 | 10 | 11-08 04:48 |
| S6-03 | 2 | 11-08 04:48 |
| S5-QA | 28 | 11-08 04:39 |
| S6-08 | 4 | 11-08 04:39 |
| S5-SCHED01 | 6 | 11-08 04:39 |
| S6-07 | 4 | 11-08 04:33 |
| S6-01 | 6 | 11-08 04:33 |
| S6-02 | 2 | 11-08 04:33 |

---
本文件由 `xnull dev board` 生成；手工编辑无效。
