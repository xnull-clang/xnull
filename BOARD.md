# SSOT 看板（脚本生成，手改即作废）

- 生成时间：2026-11-07 14:46:20 +0800
- 仓库：`XNull-Lang`　分支：`main`　HEAD：`453026b`
- 窗口：近 7 天（起点提交 `852c141`）
- 数据源：git log / go test / impl/docs/conformance/status.tsv / evidence/ / handoff/
- 断链协议：ADR-003（接力棒 + last-green；`--record-green` 在测试绿时记录 HEAD）

## 四数

| # | 指标 | 值 |
|---|---|---|
| 1 | 窗口内 commit 数 | 199 |
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
| 自举线 | E4 | 22 | b23fa42 fix(codegen): G11 list-param element get |
| 运行时线 | E5 | 8 | 2948e82 feat(runtime): xdkc_utf8_valid + utf8Val |
| QA 线 | QA1 | 68 | 5d59c95 evidence(NEG-01): 60/60 on pod/e2-sema@3 |
| 发布线 | COO | 0 | — |

## 最近提交（最多 15 条）

| sha | 日期 | 作者 | 主题 |
|---|---|---|---|
| 453026b | 11-07 14:46 | 李飞恒 | docs(handoff): close IDE-SOURCE on main; open XNFMT-CI baton |
| 15f52e4 | 11-07 14:45 | 李飞恒 | docs(E4): G11 baton — QA1 independent 26/26 on e2-sema tree |
| 5d59c95 | 11-07 14:44 | 李飞恒 | evidence(NEG-01): 60/60 on pod/e2-sema@3749bd3 (read-only re |
| e53e201 | 11-07 14:44 | 李飞恒 | docs(e5): B0-07c 接力棒记录合入 main 与合入后基线 |
| 713eea2 | 11-07 14:43 | 李飞恒 | test(e5): 合入 main 后 numeric 测试包基线（PASS=2 BLOCKED=5 FAIL=0） |
| 840a11c | 11-07 14:42 | 李飞恒 | merge(main): sync board/B1/E4 codegen; keep integrated B1-02 |
| 20f101d | 11-07 14:42 | 李飞恒 | evidence(NEG-01): rerun 51/60 main, 59/60 e2-sema@33d11ee |
| 9bf370c | 11-07 14:41 | 李飞恒 | docs(ide): machine interface + spec index entries for IDE (I |
| 9bd0c91 | 11-07 14:36 | 李飞恒 | chore(board): regenerate SSOT board at main a65fd4d (B0 6 /  |
| e70e08e | 11-07 14:35 | 李飞恒 | docs(E4): G11 baton + B2 language-surface checklist v0 |
| b23fa42 | 11-07 14:34 | 李飞恒 | fix(codegen): G11 list-param element get — evaluate return b |
| 26bc80c | 11-07 14:34 | 李飞恒 | docs(e5): B0-07c 接力棒补 numeric 前置测试包与 codegen 补点清单 |
| 3ae57a5 | 11-07 14:34 | 李飞恒 | test(ffi): B0-07c numeric 前置测试包 + 句柄失败打开回 NULL（E5） |
| a65fd4d | 11-07 14:33 | 李飞恒 | handoff(PKG-01): TUPLE interp F1/F2 green on e91e33c; NEG 9  |
| e91e33c | 11-07 14:32 | 李飞恒 | merge(pod/e3-interp): NEG interp closure + TUPLE-01 F1/F2 id |

## 断链与最后绿点（ADR-003）

| 线 | last-green | 落后 HEAD | 状态 | 最近 commit |
|---|---|---|---|---|
| 前端线 | 49cbb27 | 74 | 有效（该线最近提交） | ba4458a（11h17m） |
| 自举线 | b23fa42 | 21 | 有效（该线最近提交） | fe19e7c（13h43m） |
| 运行时线 | c9e8a5d | 52 | 有效（该线最近提交） | db74cc7（16h20m） |
| QA 线 | 5d59c95 | 2 | 有效（支撑线：活动路径最近提交） | 2597b36（13h23m） |
| 发布线 | d000b43 | 68 | 有效（支撑线：活动路径最近提交） | — |

## 接力棒（handoff/）

已有接力棒 14 根；应覆盖卡片 52 张。

| 卡片 | 接力棒 | 字段 |
|---|---|---|
| B0-02 | 缺失 | — |
| B0-07b | 缺失 | — |
| B0-07c | 有 | 完整 |
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
| NEG-01 | 缺失 | — |
| NEG-3 | 缺失 | — |
| NEG-INTERP | 缺失 | — |
| P1-INIT-FWD | 缺失 | — |
| PKG-01 | 有 | 缺 已知缺口 |
| QA1-B1-03 | 有 | 完整 |
| QA1-EXP-004 | 有 | 完整 |
| TUPLE-01 | 缺失 | — |
| XFRONT-FIX-NEG-GEN | 缺失 | — |
| XNFMT-CI | 有 | 完整 |
| e5-2026-11-07 | 缺失 | — |

## 告警（ADR-003 断链判据）

- QA 线：13h23m 无 commit（ADR-003 2h 阈值）
- 前端线：11h17m 无 commit（ADR-003 2h 阈值）
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
- 接力棒缺失：NEG-01
- 接力棒缺失：NEG-3
- 接力棒缺失：NEG-INTERP
- 接力棒缺失：P1-INIT-FWD
- 接力棒缺失：TUPLE-01
- 接力棒缺失：XFRONT-FIX-NEG-GEN
- 接力棒缺失：e5-2026-11-07
- 接力棒缺字段：PKG-01（已知缺口）
- 自举线：13h43m 无 commit（ADR-003 2h 阈值）
- 运行时线：16h20m 无 commit（ADR-003 2h 阈值）

## evidence（按最近修改，最多 10 项；共 67 项）

| 目录 | 文件数 | 最近修改 |
|---|---|---|
| PKG-01 | 1 | 11-07 14:47 |
| TUPLE-01 | 1 | 11-07 14:47 |
| NEG-01 | 2 | 11-07 14:44 |
| e5-2026-11-07 | 16 | 11-07 14:44 |
| B0-07c | 12 | 11-07 14:44 |
| NEG-3 | 3 | 11-07 14:44 |
| M1-ERR-01-qa | 22 | 11-07 14:36 |
| GEN-G11 | 6 | 11-07 14:34 |
| NEG-INTERP | 11 | 11-07 14:32 |
| M6-B1-03 | 68 | 11-07 14:30 |

---
本文件由 `xnull dev board` 生成；手工编辑无效。
