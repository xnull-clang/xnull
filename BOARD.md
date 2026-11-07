# SSOT 看板（脚本生成，手改即作废）

- 生成时间：2026-11-08 00:45:09 +0800
- 仓库：`XNull-Lang`　分支：`main`　HEAD：`e9cd063`
- 窗口：近 7 天（起点提交 `852c141`）
- 数据源：git log / go test / impl/docs/conformance/status.tsv / evidence/ / handoff/
- 断链协议：ADR-003（接力棒 + last-green；`--record-green` 在测试绿时记录 HEAD）

## 四数

| # | 指标 | 值 |
|---|---|---|
| 1 | 窗口内 commit 数 | 453 |
| 2 | 锚点翻转（PASS） | 45（起点 45，Δ+0） |
| 3 | 全量测试 | 绿（11 包 ok） |
| 4 | 门进度 | B0 6 卡（有证据 5） / B1 3 卡（有证据 3） / B2 0 卡 / B3 0 卡 / B4 0 卡；收件箱/门/GATE-01门.md；收件箱/门/M1门.md；收件箱/门/M2门.md；收件箱/门/M6-B0门.md；收件箱/门/M6-B1门.md |

## 台账锚点（status.tsv 已登记 55 行）

| 状态 | 数量 |
|---|---|
| PASS | 45 |
| 部分 | 8 |
| 未实现 | 2 |
| N/A | 0 |

> 未登记锚点在台账中显示「未实现」（口径见 impl/docs/conformance/ledger-restructure.md）。

## 生产线进度（窗口内 commit / 最近一条）

| 线 | Owner | commit | 最近提交 |
|---|---|---|---|
| 前端线 | E2 | 58 | 39d0273 feat(sema): GATE-01 诊断码表与 new 非 class ch |
| 自举线 | E4 | 62 | a34a392 fix(codegen): BND-10b 全局根与 GC 单例/数据枚举（不重 |
| 运行时线 | E5 | 11 | 9e6de30 fix(runtime): 弱槽位目标死亡后解绑，destroy 不再触达已释放 |
| QA 线 | QA1 | 107 | e4b8f21 sign(S2): MEM-01 + MEM-02 + BND-10 PASS; |
| 发布线 | COO | 0 | — |

## 最近提交（最多 15 条）

| sha | 日期 | 作者 | 主题 |
|---|---|---|---|
| e9cd063 | 11-08 00:43 | 李飞恒 | docs: M2 后下一阶段（S3-S8 定版 -> B2 前置） |
| a5a58a7 | 11-08 00:43 | 李飞恒 | gate(M2): M2 门报告 29/29 通过; AGENTS/索引同步 |
| 4f63150 | 11-08 00:43 | 李飞恒 | gate(S2): GATE-01 PASS — M2 29/29 达成; status PASS=45 |
| e4b8f21 | 11-08 00:28 | 李飞恒 | sign(S2): MEM-01 + MEM-02 + BND-10 PASS; GATE-01 门报告 PASS; s |
| c4361f6 | 11-08 00:12 | 李飞恒 | sign(S2): INH-01 + FIELD-01 根验收 PASS（基线补签） |
| 05e680c | 11-07 23:44 | 李飞恒 | ssot: INT-01 入 status.tsv；PASS=41 |
| 02f7d84 | 11-07 23:44 | 李飞恒 | sign(S2): SINGLE-01 PASS; status PASS=40 |
| af857c2 | 11-07 23:29 | 李飞恒 | sign(S2): ANN-01 + BND-13 + EXT-01 PASS; status PASS=39 |
| f7628b9 | 11-07 23:29 | 李飞恒 | merge: E4 BND-10b 全局根 + GC 单例/数据枚举 合入 main |
| cf76614 | 11-07 23:28 | 李飞恒 | docs(S2): E4 BND-10b 回执（E5 后剩余缺口） |
| a34a392 | 11-07 23:28 | 李飞恒 | fix(codegen): BND-10b 全局根与 GC 单例/数据枚举（不重复 E5 实现） |
| 6e37d88 | 11-07 23:26 | 李飞恒 | merge: E2 GATE-01 诊断码表 + new 非 class 拒绝 合入 main |
| 002cdcd | 11-07 23:25 | 李飞恒 | sign(S2): BND-15 PASS; status PASS=36 |
| 39d0273 | 11-07 23:25 | 李飞恒 | feat(sema): GATE-01 诊断码表与 new 非 class check 拒绝 |
| 10941d7 | 11-07 23:23 | 李飞恒 | merge: E2 EXT-01 singleton/data-enum + ANN-01 注解检查 合入 main |

## 断链与最后绿点（ADR-003）

| 线 | last-green | 落后 HEAD | 状态 | 最近 commit |
|---|---|---|---|---|
| 前端线 | 39d0273 | 96 | 有效（该线最近提交） | ba4458a（21h16m） |
| 自举线 | 4f63150 | 2 | 有效（该线最近提交） | fe19e7c（23h42m） |
| 运行时线 | 9e90d4e | 155 | 有效（该线最近提交） | db74cc7（26h19m） |
| QA 线 | e4b8f21 | 3 | 有效（支撑线：活动路径最近提交） | 2597b36（23h22m） |
| 发布线 | 3890532 | 245 | 有效（支撑线：活动路径最近提交） | — |

## 接力棒（handoff/）

已有接力棒 22 根；应覆盖卡片 76 张。

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
| S2-E5-BND10 | 有 | 完整 |
| S2-E5-MEM01 | 有 | 完整 |
| S2-E5-deinit | 有 | 缺 已知缺口 |
| S2-E5-weak | 有 | 完整 |
| TUPLE-01 | 缺失 | — |
| TUPLE-OPT | 缺失 | — |
| XFRONT-FIX-NEG-GEN | 缺失 | — |
| XNFMT-CI | 有 | 完整 |
| e5-2026-11-07 | 缺失 | — |

## 告警（ADR-003 断链判据）

- QA 线：23h22m 无 commit（ADR-003 2h 阈值）
- 前端线：21h16m 无 commit（ADR-003 2h 阈值）
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
- 自举线：23h42m 无 commit（ADR-003 2h 阈值）
- 运行时线：26h19m 无 commit（ADR-003 2h 阈值）

## evidence（按最近修改，最多 10 项；共 118 项）

| 目录 | 文件数 | 最近修改 |
|---|---|---|
| S2-QA | 9004 | 11-08 00:19 |
| S2-E5-MEM01 | 4 | 11-07 23:29 |
| S2-E5-BND10 | 7 | 11-07 23:29 |
| S2-GATE | 8 | 11-07 23:26 |
| S2-EXTANNb | 6 | 11-07 23:23 |
| S2-E3-proto | 14 | 11-07 22:58 |
| S2-E3-ext | 3 | 11-07 22:56 |
| S2-EXT | 6 | 11-07 22:55 |
| S2-BND0914b | 6 | 11-07 22:51 |
| S2-PROTO | 6 | 11-07 22:44 |

---
本文件由 `xnull dev board` 生成；手工编辑无效。
