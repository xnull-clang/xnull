# 验收：S6-XDK-07（collections）

> **验收人**：QA1（独立质量线）
> **结论：BLOCKED/P2**（解释路径算法/特化容器通过；编译端到端未实现）
> **复验点**：main `64e7052`
> **时间**：2026-11-08
> **证据**：`evidence/S6-QA/XDK-07/`
> **依据**：S6 §4.5、XDK-07；S6-07 回执
> **确认方式**：main 版本读取 `.git/refs/heads/main`；未做分支/提交操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `sortBy/dedup/find/groupByInt` 解释执行 | **PASS**：`TestXdkCollectionsRuntime` |
| `RingBuffer/OrderedMap/BTreeMap/PriorityQueue` 解释执行 | **PASS** |
| 内建容器语义回归 | **PASS**（既有 List/Map/Set 用例） |
| 编译端到端 | **BLOCKED/P2**：`TestXdkCollectionsUnitSurface` FAIL，成员 `isFull/isEmpty/indexOf/lowerBound/get/less/swap/sift*` → `TY-229` |

**判定：BLOCKED/P2。** 源码单元与解释路径可用；编译路径尚未登记特化容器成员，不能判完整 PASS。

---

## 二、精确缺口

| 项 | 证据 | 归属 |
|---|---|---|
| collections.x 成员未被 sema XDK 白名单登记 | `codegen.log`：TY-229 列表 | E2 S6-01 |
| codegen 端到端无法覆盖 4 特化容器 | 同上 | E4 |

---

## 三、证据

- `evidence/S6-QA/XDK-07/matrix.tsv`
- `interp.log`（TestXdkCollectionsRuntime PASS）
- `codegen.log`（TestXdkCollectionsUnitSurface FAIL）
- `impl/lib/xdk/collections.x`
