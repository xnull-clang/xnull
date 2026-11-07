# 验收：S6-XDK-07（collections）

> **验收人**：QA1（独立质量线）
> **结论：PASS**（E4 `892c46e` 特化容器发射后复签；编译端到端通过）
> **复验点**：main `e3f551f`（含 E4 `892c46e` XDK-07 codegen）
> **时间**：2026-11-08
> **证据**：`evidence/S6-QA/XDK-07b/`
> **依据**：S6 §4.5、XDK-07；S6-XDK07 E4 回执；`tests/s6/xdk07/`
> **确认方式**：main 版本读取 `.git/refs/heads/main`；未做分支/提交操作。

---

## 一、结论

| 验收点 | 结果 |
|---|---|
| `RingBuffer.isEmpty/isFull/push/pop/length` | **PASS**：compiled 输出与 expect 一致 |
| `OrderedMap.get/indexOf/put/length` | **PASS** |
| `BTreeMap.lowerBound/getOr/keysArray` | **PASS** |
| `PriorityQueue.less/swap/siftUp/siftDown/push/pop/peek` | **PASS**（函数指针 comparator + 间接调用） |
| `T?` 可空返回（pop/get/peek） | **PASS**：`xn_opt_*` + 判空收窄 |
| `new T[n]` 数组返回 | **PASS**：`keysArray` 长度/元素正确 |
| sema / interp / compiled 三层 | **PASS**：`TestXDK07SemaSurface/InterpE2E/CompiledE2E` |
| 内建容器回归 | **PASS**（既有 List/Map/Set） |

**判定：PASS。** `collections_basic` / `collections_nonnull` 双路径输出与 `.expect` 逐行匹配；8 类特化容器成员均可编译运行。

---

## 二、实测

```text
$ go test ./internal/cli -run 'TestXDK07' -count=1 -v
PASS TestXDK07SemaSurface
PASS TestXDK07InterpE2E
PASS TestXDK07CompiledE2E
```

`collections_basic.x` 覆盖：
`isEmpty/isFull/push/pop/length`、`OrderedMap.get/indexOf/put/length`、
`BTreeMap.lowerBound/getOr/keysArray`、`PriorityQueue(less).push/pop/isEmpty`。
编译输出 19 行与 `.expect` 完全一致；`collections_nonnull` 17 行同样一致。

```text
true/false/true/true/true/false/1/1/10/0/2/1/20/1/3/false/1/2/3
```

---

## 三、边界

| 项 | 说明 |
|---|---|
| 闭包捕获外部变量 | 仍显式报错（未装箱 env）；本轮 comparator 无捕获 |
| 数组 | 固定长度仅体现在 `len` 语义；GC 容器指针 |
| 函数指针字段 deinit | 无引用计数语义（无泄漏断言） |

---

## 四、证据

- `evidence/S6-QA/XDK-07b/matrix.tsv`
- `cli-xdk07.log`（Sema/Interp/Compiled E2E）
- `codegen.log`（TestXdkCollectionsMemberSignatures）
- `collections_basic.x` / `.expect`、`collections_nonnull.x` / `.expect`
- `evidence/S6-XDK07/`、`收件箱/回执箱/回执-S6-XDK07-E4.md`
