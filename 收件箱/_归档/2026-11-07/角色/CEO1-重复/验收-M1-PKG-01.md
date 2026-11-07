# M1-PKG-01 独立验收：包与导入（S1 §3.2/§3.4/§3.5）

> **验收人**：CEO1-QA2-回归（实现者：CEO1-RD1，不自验）
> **验收对象**：PKG-01，代码 `9bb6bef`（分支 `pod/c1-rd1`）
> **代码基线**：main `2c00cf5`（已合 ERR-01、DET-01、TYPE-01、GEN-01）
> **合并后验收点**：`a6fb48d`（`39552bc` 将 main@2c00cf5 合入 pod/c1-rd1）
> **验收方式**：在 `a6fb48d` 上跑独立用例 49 个子用例（不复用实现者测试）
> **日期**：2026-11-07　**结论**：**FAIL**

---

## 0. 结论

**FAIL。3 个独立子用例失败，归为 2 条缺陷；其中 1 条是本提交引入的回归。**

| # | 缺陷 | 性质 | 严重度 | 证据 |
|---|---|---|---|---|
| **F1** | 同包不同符号共用同一 `as` 别名时**无任何诊断**（应 `RES-103`） | **本提交回归**（main `2c00cf5` 正确报 `RES-103`，合并后丢失） | P1 | `merged-independent-sema.log`；`main-2c00cf5-alias.log` |
| **F2** | 合法多级 XDK 包 `import xdk.net.http` 被误报 `RES-106`（应无诊断） | 基线遗留；PKG-01 宣称"包导入诊断闭合"但未覆盖 | P1 | `merged-independent-sema.log`；§3.2 第 1544 行 |
| F3 | 别名与同包裸导入简单名同名时静默接受（同类别名唯一性问题） | 基线亦存在，非本提交引入 | P2 | `main-2c00cf5-alias.log`（ReproB） |

**其余通过**：sema 全量 57/57、`go vet` exit 0、`examples/multi` 双路径逐字节一致、9 单文件示例 9/9 一致。失败项未被现有测试覆盖，故"57 全绿"不能推出 PKG-01 通过。

**合并态说明**：`9bb6bef` 直接合入 `2c00cf5` 曾在 `impl/internal/sema/xdk.go` 冲突（DET-01 与 PKG-01 都改 `analyzeImports`）。RD1 已在 `39552bc` 完成合并，冲突解只增加 `sort.Strings(pkgs)`（DET-01），PKG-01 逻辑未变；`a6fb48d` 为合并后复跑点。本次验收全部基于 `a6fb48d`，sema 全量 57/57 通过，但下文 3 个独立子用例仍失败。

---

## 1. 台账 7 项 → 独立验收结果

| # | 台账验收要点 | 独立用例 | 结果 |
|---|---|---|---|
| ① | 包导入 | 用户包导入/私有过滤/顶层遮蔽 4 例；XDK 包导入 4 例 | **FAIL**（XDK 多级包误拒，F2） |
| ② | 符号导入 | 单符号可见、兄弟不可见、不存在、private、protected、类符号、私有类 7 例 | PASS 7/7 |
| ③ | 同名消歧别名 | 双别名、别名替换原名、单边消歧 3 例 | PASS 3/3 |
| ④ | 非冲突别名被拒绝 | 单符号 needless、包别名、XDK 包别名、跨源冲突、同源冲突、顶层冲突、预定义冲突 10 例 | **FAIL**（F1/F3） |
| ⑤ | 简单名歧义 | 双裸导入、重复包、重复符号、顶层遮蔽、双包同符号、三源一别名、别名与裸名 7 例 | PASS 7/7 |
| ⑥ | XDK 未导入 | 使用点、显式导入、用户包不掩盖、类型位置缺导入/有导入 5 例 | PASS 5/5 |
| ⑦ | 导入环 | 两节点、三节点、自环、菱形 DAG、XDK 边不误报 5 例 | PASS 5/5 |

> 统计：49 个子用例，46 PASS / 3 FAIL（F1、F3 各 1 例，F2 1 例）。

---

## 2. 失败复现

### F1（阻断，回归）：同包不同符号共用别名 → 无诊断

```x
package app
import lib.a.X as P      // 需要 as（X 在 lib.a / lib.b 同名）
import lib.b.X as BX
import lib.a.Y as P      // 别名 P 再次使用：X 与 Y 是两个符号
import lib.b.Y as BY
static Int main() { return 0 }
```

| 代码 | 期望 | 实际 |
|---|---|---|
| main `2c00cf5`（合并前） | `RES-103` | **`RES-103`** ✅ |
| `9bb6bef` / 合并后 `a6fb48d` | `RES-103` | **无诊断** ❌ |

**根因**：`impl/internal/sema/xdk.go:168` 把 `info.src` 设为**包路径**（`lib.a`），`:216` 在别名重复时用 `prev != b.src` 判定，导致"同包不同符号"被当成"同一来源重复导入"而跳过。基线代码的 `src` 是完整导入路径（含符号名），故能报错。

**影响**：`P` 只绑定到先出现的 `lib.a.X`，`lib.a.Y` 静默不可达；编译器既不报错也不提示，属于诊断漏报 + 静默错绑定。

### F2（不通过，基线遗留）：`xdk.net.http` 被误拒

```x
import xdk.net.http
static Int main() { return 0 }
```

| 期望 | 实际 |
|---|---|
| 无诊断（合法包导入） | **`RES-106`**：XDK 包 `xdk.net` 没有导出符号 `http` |

**规范依据**：`XNull解决方案-第1部分-基础语法-v3.3.0.md:1544`——"XDK 包路径可以多级；包名取路径末段，例如 `xdk.net.http` 的包名是 `http`"；§3.2 第 588 行、§11.1 第 1540 行均以该导入为例。

**根因**：`xdk.go:123` 把 `len(p) == 3` 一律当作"符号导入"。实现无法区分 `xdk.text.Regex`（符号）与 `xdk.net.http`（子包）。建议判定改为：`p[2]` 是已知符号则符号导入，否则按子包（包导入）处理；多级符号再另行定义。

### F3（P2，基线同类）：别名与同包裸导入同名

```x
package app
import lib.a.X as Y
import lib.b.X as BX
import lib.a.Y
static Int main() { return 0 }
```

期望 `RES-103`（别名 `Y` 与已导入简单名 `Y` 冲突），实际无诊断；main `2c00cf5` 亦无诊断（`main-2c00cf5-alias.log` 中 ReproB FAIL）。与 F1 同属"别名唯一性"未闭合，一并要求修复。

---

## 3. 通过项明细（独立用例，非实现者用例）

| 组 | 子用例 | 结果 |
|---|---|---|
| 符号导入 | single-visible / sibling-hidden / missing / private / protected / class-symbol / private-class | 7/7 |
| 消歧别名 | both-aliased / alias-replaces-original / one-aliased-one-bare | 3/3 |
| 简单名歧义 | two-bare / duplicate-package / duplicate-symbol / top-level-shadow / two-package-share / three-sources-one-aliased / alias-vs-bare | 7/7 |
| XDK 未导入 | use-without-import / explicit-import / user-import-no-mask / type-position-missing / type-position-imported | 5/5 |
| 导入环 | two-node / three-node / self-cycle / diamond-dag / xdk-edge-not-cycle | 5/5 |
| 目标规则 | package-missing / default-package / default-symbol / default-fragment / private-use | 5/5 |
| 诊断质量 | 位置 `entry.x:3` + 列/消息/提示；10 次重复诊断码+位置一致 | 2/2 |
| 语法守门 | `package xdk.*` → SYN-111；通配符导入报错；声明后 import 报错 | 3/3 |
| 其他别名 | needless / package-alias / xdk-package-alias / cross-source / top-level / builtin | 6/6 |

**观察（不作为失败项）**：

1. 使用歧义简单名时会同时出现 `RES-104` + `RES-101`（级联噪声，非本次否决理由，建议后续去重）。
2. 依赖包自身的缺失导入不会被诊断（`Package` 只携带导入路径，不分析依赖单元）；属多包切片边界。
3. `AnalyzeWithDeps` 尚未接 CLI，导入诊断目前只在 sema API 可达（回执已声明）；本次按 API 验收，`examples/multi` 走 codegen 加载器另测。
4. 完全限定名（§3.2 末条）未实现，回执已列为未测项；不在 PKG-01 台账枚举内。

---

## 4. 回归与双路径（合并树）

| 项 | 命令 | 结果 |
|---|---|---|
| sema 全量 | `go test ./internal/sema -count=1 -v`（`a6fb48d`） | **57 PASS / 0 FAIL**，`ok 2.642s` |
| 静态检查 | `go vet ./internal/sema`（`a6fb48d`） | exit 0 |
| multi 双路径 | `xnull run --interp examples/multi/main.x` vs `xnull run …` | stdout 逐字节一致，退出码 0/0，stderr 均 0 B |
| 9 单文件示例 | 同上逐个 `cmp` | 9/9 一致，0/0 |
| main 基线对照 | `TestQA2MainAliasReproA` on `2c00cf5` | PASS（`RES-103` 存在）→ 证明 F1 为回归 |

---

## 5. 证据

`收件箱/CEO1/evidence-M1-PKG-01/`：

| 文件 | 内容 |
|---|---|
| `merged-independent-sema.log` | `a6fb48d` 上 49 个子用例原始输出（3 FAIL） |
| `merged-sema-full.log` | `a6fb48d` sema 全量 57 PASS |
| `merged-vet.log` | `a6fb48d` vet |
| `main-2c00cf5-alias.log` | main 基线 ReproA PASS / ReproB FAIL |
| `baseline-81ec33d-alias.log` | 原始基线对照 |
| `merge-conflict.log` | `2c00cf5` + `9bb6bef` 合并冲突原文（xdk.go，已在 `39552bc` 解决） |
| `qa2_independent_test.go` | 独立用例全文（仅存在于 /tmp 临时副本，未入仓库） |
| `dualpath/`、`dualpath-merged9/` | multi 与 9 示例的双路径原始输出 |
| `sha.txt` | 各提交 sha（main / 9bb6bef / 39552bc / a6fb48d）与结果记录 |

独立用例运行方式：`git archive a6fb48d` 导出到 `/tmp`，仅向临时副本注入 `qa2_independent_test.go`；**未修改主工作区与 `wt/*` 的任何文件**，验收不使用工作树中的未提交改动。

---

## 6. 通过条件（复验口径）

1. F1/F3：别名重复判定改为比较"完整导入来源（包 + 符号）"或维护"已绑定名 → 符号身份"；同一别名指向不同符号必须 `RES-103`。
2. F2：`xdk.<pkg>.<seg>` 仅当 `<seg>` 是该包已知符号时按符号导入，否则按多级包导入；补 `xdk.net.http` 用例。
3. 先红后绿：新增 3 个负向/正向用例，且在 `2c00cf5` 基线上先证明红。
4. 在 `a6fb48d` 上修复后重跑 sema 全量 + 本文件的 49 个独立子用例 + multi/9 示例双路径（`39552bc` 已完成 main 合并，无需再次 rebase；若再动 main 需重新集成）。
5. 提供新 sha 与七件套；QA2 复验通过后才可改判 PASS。
