# `DbBatch`

| 项 | 值 |
| --- | --- |
| 类型 | `class DbBatch` |
| 包 | `xdk.db` |
| 稳定性 | `preview` |
| 依赖 | `SqlStatement`、`List`、`Error` |
| 被依赖 | [`Database`](Database.md) |

> 包索引见 [`README.md`](README.md)。

---

## 1. 定位

语句批量构建器：按添加顺序保存一组 `SqlStatement`，由 [`Database.executeBatch`](Database.md) 或 [`Database.executeBatchAtomic`](Database.md) 在一个连接上顺序执行。

不做：执行、事务控制、结果聚合、参数绑定、SQL 拼接、去重、语句缓存、并行执行、失败重试、每语句独立 options、存储过程批处理。

---

## 2. 设计逻辑

- `DbBatch` 只负责**收集**，不持有连接/事务；执行策略由 `Database` 决定。这样批量值可安全传递，不会把池/事务生命周期埋进集合。
- 可空构造 + 增量 `add` 适合导入循环；也可用列表构造一次性复制。
- 顺序即执行顺序；不排序、不去重。相同语句重复添加会重复执行。
- 一条语句保持 `xdk.sql` 语义：索引/命名参数、参数值、SQL 文本均由 `SqlStatement` 携带；`DbBatch` 不解析、不改写。
- 空 `DbBatch` 合法；执行时返回空结果列表，不借连接、不产生 I/O。
- 非线程安全：构建阶段单任务独占；构建完成后可只读共享（不再调用 `add`/`addAll`/`clear`）。
- 执行时 `Database` 读取 `statements()` 快照；执行期间修改原 `DbBatch` 不影响本次执行。
- 不提供每语句 `SqlOptions`：批量的超时/行数上限由 `Database.executeBatch` 的 `SqlOptions` 统一应用；需要不同控制面时拆成多个批次。
- 失败语义由 `Database` 定义：非原子批量遇到第一个错误停止；原子批量回滚并返回错误。`DbBatch` 不吞错、不重试。
- 无 close；GC 管理内存；列表可能很大，调用方负责规模控制。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_statements` | `List<SqlStatement>` | final 引用，内容可变 | 按添加顺序；元素非 null |

不变量：

- 列表非 null；每个元素非 null。
- 顺序稳定；允许重复；允许为空。
- 构造时复制入参；`statements()` 返回副本。
- 构建方法（`add`/`addAll`/`clear`）只在单任务内调用；之后只读共享。
- 对象不持有连接、事务、结果、错误或 options。

---

## 4. 生命周期

由 `DbBatch()`/`DbBatch(List<SqlStatement>)` 创建；构建期可变；无 close；GC 管理内存。

- 可以反复执行同一个 `DbBatch`；`Database` 不修改它。
- 执行期间的修改不影响已开始的执行（执行方先复制语句列表）。
- 执行失败不改变 `DbBatch` 内容；调用方可修复后重试或重新构建。
- 不建议长期保留超大 `DbBatch`；它是语句引用的容器，不会自动限流。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `DbBatch()` | 无 | 空批次 | 无 |
| `DbBatch(List<SqlStatement> statements)` | statements | 非 null；元素非 null | 非法 → panic |

第二个构造复制列表；调用方之后修改原列表不影响批次。元素 `SqlStatement` 不可变，无需深拷贝。

---

## 6. 字段表

见 §3；字段私有。`_statements` 是唯一字段；不暴露内部列表。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `add` | 追加一条语句 | `SqlStatement statement` | `DbBatch` | null → panic | 返回 self；允许重复 |
| `addAll` | 追加多条语句 | `List<SqlStatement> statements` | `DbBatch` | null/元素 null → panic | 复制；返回 self |
| `statements` | 语句快照 | 无 | `List<SqlStatement>` | 无 | 列表副本；元素不可变 |
| `size` | 语句数 | 无 | `Int` | 无 | 计数 |
| `isEmpty` | 是否为空 | 无 | `Bool` | 无 | `size() == 0` |
| `clear` | 清空 | 无 | `DbBatch` | 无 | 返回 self；保留对象 |
| `copy` | 独立副本 | 无 | `DbBatch` | 无 | 新对象；列表复制 |
| `describe` | 单行诊断 | 无 | `String` | 无 | 只输出语句数；不含 SQL |

详细契约：

- `add(null)` 是合同错误（panic）；成功返回 `self`，支持链式构建。
- `addAll(null)` panic；列表中的 null 元素在第几个位置由错误文本指出（只含索引，不含 SQL）。
- `addAll` 先校验整个列表，再追加；不会出现“前半部分已追加、后半部分 panic”的部分修改。实现可先复制/校验，再 push。
- `statements()` 返回独立列表；调用方修改副本不影响批次。元素 `SqlStatement` 不可变，无需复制。
- `clear()` 清空内部列表并返回 `self`；之后可继续 `add`。
- `copy()` 返回新 `DbBatch`，包含相同语句引用的副本；修改副本不影响原批次。
- `describe()` 形如 `"DbBatch(statements=12)"`；不输出 SQL 文本、参数值或表名。
- 不提供 `get(Int index)`/`remove`：需要逐条访问时用 `statements()` 快照；避免在构建器上做随机编辑。
- 不提供 `execute`：执行依赖 `Database`/连接池，放在 `Database` 上避免双向依赖。
- 不提供 `equals`：引用身份；需要比较时逐条比较 `SqlStatement`（`SqlStatement.equals`）。

---

## 8. 使用的技术

- 可变构建器；
- 列表防御性复制；
- 先校验后追加；
- 顺序容器；
- 无 SQL 解析/拼接；
- 无资源生命周期。

---

## 9. 需要的支撑

- 语言：class、final 字段、List、Int、Bool、String；
- 运行时：`List.copy`、`List.push`、`List.clear`、`str(Int)`；
- 接口：`SqlStatement`、`Error`、`BasicError`。

---

## 10. 依赖的特性/接口/类

[`SqlStatement`](../../network/sql/SqlStatement.md)、[`Database`](Database.md)（执行方）、[`SqlResult`](../../network/sql/SqlResult.md)（执行结果）。`DbBatch` 不依赖驱动、连接、事务或池类型。

---

## 11. 所有权与并发

- `DbBatch` 拥有自己的列表；构造/`addAll`/`statements` 都复制列表边界。
- 构建期非线程安全；不得多任务并发 `add`/`clear`。
- 构建完成后可作为只读值跨任务共享；共享前必须停止修改。
- 执行方在开始时复制语句列表，之后调用方修改 `DbBatch` 不影响在途执行。
- 语句借用且不可变；`DbBatch` 不复制 `SqlStatement` 内部数据（不可变，无需）。
- 相等：引用身份；不提供 `equals`/哈希；不推荐作 `Map` 键。
- 排序：保持添加顺序；不提供排序方法。

---

## 12. 示例与反例

正确：

```text
DbBatch batch = new DbBatch()
    .add(new SqlStatement("insert into audit(event_key, body) values (?, ?)")
        .bind(SqlValue.ofLong(1))
        .bind(SqlValue.ofString("created")))
    .add(new SqlStatement("update counters set value = value + 1 where name = ?")
        .bind(SqlValue.ofString("audit")))

Result<List<SqlResult>, Error> result =
    database.executeBatchAtomic(context, batch)
```

反例：

- 在多个任务中并发 `batch.add(...)`；构建器非线程安全。
- 期望 `DbBatch` 自动开启事务；原子性由 `executeBatchAtomic` 决定。
- 在批量中混入需要不同 `SqlOptions` 的语句；拆成多个批次。
- 用 `DbBatch` 拼接 SQL 字符串；仍应使用 `SqlStatement` 参数。
- 执行失败后期望 `DbBatch` 自动删除失败语句；它不变。
- 修改 `statements()` 返回列表期望改变批次。
- 把 `describe()` 当 SQL 日志；它只输出语句数。
- 长期保留超大 `DbBatch` 并期望自动限流。

---

## 13. 测试/场景义务

- 空构造；列表构造；列表构造复制独立；
- `add` 单条/多条/重复；链式返回 self；
- `add(null)` panic；`addAll(null)` panic；`addAll` 含 null panic 且不部分追加；
- `statements()` 副本独立；元素顺序保持；
- `size`/`isEmpty`；`clear` 后为空且可继续添加；`clear` 返回 self；
- `copy` 独立；修改副本不影响原批次；
- `describe` 只含数量；
- 执行空批次不借连接/无 I/O；
- 执行期间修改批次不影响在途执行；
- 大批量计数/内存边界（文档义务，不强制上限）；
- 多任务只读共享；
- 失败后批次内容不变。

---

## 14. XNull 伪代码

```xnull
class DbBatch {
    final List<SqlStatement> _statements

    DbBatch() {
        _statements = []
    }

    DbBatch(List<SqlStatement> statements) {
        if statements == null {
            throw "DbBatch: null statements"
        }
        List<SqlStatement> copied = statements.copy()
        Int index = 0
        while index < copied.length() {
            if copied.get(index) == null {
                throw "DbBatch: null statement at " + str(index)
            }
            index = index + 1
        }
        _statements = copied
    }

    DbBatch add(SqlStatement statement) {
        if statement == null {
            throw "DbBatch.add: null statement"
        }
        _statements.push(statement)
        return self
    }

    DbBatch addAll(List<SqlStatement> statements) {
        if statements == null {
            throw "DbBatch.addAll: null statements"
        }
        List<SqlStatement> copied = statements.copy()
        Int index = 0
        while index < copied.length() {
            if copied.get(index) == null {
                throw "DbBatch.addAll: null statement at " + str(index)
            }
            index = index + 1
        }
        index = 0
        while index < copied.length() {
            _statements.push(copied.get(index))
            index = index + 1
        }
        return self
    }

    List<SqlStatement> statements() {
        return _statements.copy()
    }

    Int size() {
        return _statements.length()
    }

    Bool isEmpty() {
        return _statements.length() == 0
    }

    DbBatch clear() {
        _statements.clear()
        return self
    }

    DbBatch copy() {
        return new DbBatch(_statements)
    }

    String describe() {
        return "DbBatch(statements=" + str(_statements.length()) + ")"
    }
}
```

> 伪代码非可执行。`addAll` 先复制并全量校验，再追加，避免部分修改；执行方应调用 `statements()` 获取快照。
