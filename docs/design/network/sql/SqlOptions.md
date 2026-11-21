# `SqlOptions`

| 项 | 值 |
| --- | --- |
| 类型 | `class SqlOptions` |
| 包 | `xdk.sql` |
| 稳定性 | `preview` |
| 依赖 | 无 |

> 包索引见 [`README.md`](README.md)。

---

## 1. 定位

单次执行的配置：超时毫秒、最大返回行数、取数提示。

不做：连接配置、事务隔离级别、重试策略、SQL 文本/参数、驱动专有选项。

---

## 2. 设计逻辑

- 可变构建期对象；执行开始时复制数值快照，之后修改不影响在途调用。
- 三个值都非负；0 是“未设置/不限制/驱动默认”的统一定义。
- `timeoutMillis` 是相对本次执行的毫秒数；与 `Context` 截止时间同时存在时，先到者生效。
- `maxRows` 是本结果集行数硬上限；只限制查询返回行，不改变 `rowsAffected`。
- `fetchSize` 是驱动取数提示；驱动可以忽略，不承诺内存/网络行为。
- 不把 options 放进 `SqlStatement`：同一语句可用不同 options 重复执行。
- 无 close；非线程安全；由调用方在单任务内构建。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_timeoutMillis` | `Long` | 可变 | ≥0；0 = 无超时 |
| `_maxRows` | `Int` | 可变 | ≥0；0 = 不限制 |
| `_fetchSize` | `Int` | 可变 | ≥0；0 = 驱动默认 |

不变量：三个字段始终非负；构造默认全 0；`copy` 产生独立对象；执行方只读快照。

`maxRows` 与 `fetchSize` 用 `Int`（计数）；`timeoutMillis` 用 `Long`（时间量）。

---

## 4. 生命周期

构造/设置期间可变；无 close；可反复 `copy`；GC 管理内存。执行开始时由实现复制数值。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `SqlOptions()` | 无 | 默认全 0 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `timeoutMillis` | 设置超时 | `Long value` | `SqlOptions` | <0 → panic | 0 = 无超时；返回 self |
| `maxRows` | 设置行数上限 | `Int value` | `SqlOptions` | <0 → panic | 0 = 不限制；返回 self |
| `fetchSize` | 设置取数提示 | `Int value` | `SqlOptions` | <0 → panic | 0 = 驱动默认；返回 self |
| `getTimeoutMillis` | 读超时 | 无 | `Long` | 无 | 纯读取 |
| `getMaxRows` | 读行数上限 | 无 | `Int` | 无 | 纯读取 |
| `getFetchSize` | 读取数提示 | 无 | `Int` | 无 | 纯读取 |
| `copy` | 独立副本 | 无 | `SqlOptions` | 无 | 新对象 |
| `describe` | 单行诊断 | 无 | `String` | 无 | 只含三个数字 |

详细契约：

- `timeoutMillis(0)` 清除超时；正数表示从 `execute` 开始计算的相对毫秒。
- `maxRows(0)` 清除上限；正数表示最多返回该行数，驱动可提前停止取数。
- `fetchSize(0)` 恢复驱动默认；正数是提示，不是硬保证；允许大于 `maxRows`。
- setter 返回 `self` 以支持链式调用；非法值立即 panic，不保留部分修改。
- `copy` 逐字段复制；副本与原对象互不影响。
- `describe` 形如 `"SqlOptions(timeoutMillis=2000 maxRows=1000 fetchSize=100)"`。
- 不提供 `equals`；按引用身份比较；需要值比较时逐字段读取。

---

## 8. 使用的技术

- 可变 builder；
- 非负校验；
- 零值语义；
- 数值快照；
- 链式 setter。

---

## 9. 需要的支撑

- 语言：class、Long、Int、String；
- 运行时：`str(Int)`、`str(Long)`；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。被 [`SqlConnection.execute`](SqlConnection.md) 与 [`SqlTransaction.execute`](SqlTransaction.md) 消费。

---

## 11. 所有权与并发

- 可变；非线程安全；不跨任务共享；需要共享时先 `copy`。
- 执行方在调用开始时读取三个数值；之后修改 options 不影响本次执行。
- 相等：引用身份；不提供 `equals`/哈希；不推荐作 `Map` 键。
- 排序：不提供。
- 无资源；无取消点。

---

## 12. 示例与反例

正确：`new SqlOptions().timeoutMillis(2000).maxRows(1000).fetchSize(100)`。  
反例：负超时/负行数；把 `maxRows` 当总行数统计；把 `fetchSize` 当硬上限；执行开始后修改 options 期望影响本次结果；跨任务共享同一可变 options；用 0 表示“立即超时”。

---

## 13. 测试/场景义务

默认全 0；三个 setter 的正值/0/负值；链式返回 self；`copy` 独立；执行快照；`maxRows=0` 不限制；`fetchSize=0` 驱动默认；`timeoutMillis=0` 无超时；`describe` 文本；并发修改不影响已开始执行。

---

## 14. XNull 伪代码

```xnull
class SqlOptions {
    Long _timeoutMillis = 0
    Int _maxRows = 0
    Int _fetchSize = 0

    SqlOptions() {
    }

    SqlOptions timeoutMillis(Long value) {
        if value < 0 {
            throw "SqlOptions.timeoutMillis: negative"
        }
        _timeoutMillis = value
        return self
    }

    SqlOptions maxRows(Int value) {
        if value < 0 {
            throw "SqlOptions.maxRows: negative"
        }
        _maxRows = value
        return self
    }

    SqlOptions fetchSize(Int value) {
        if value < 0 {
            throw "SqlOptions.fetchSize: negative"
        }
        _fetchSize = value
        return self
    }

    Long getTimeoutMillis() { return _timeoutMillis }
    Int getMaxRows() { return _maxRows }
    Int getFetchSize() { return _fetchSize }

    SqlOptions copy() {
        SqlOptions result = new SqlOptions()
        result.timeoutMillis(_timeoutMillis)
        result.maxRows(_maxRows)
        result.fetchSize(_fetchSize)
        return result
    }

    String describe() {
        return "SqlOptions(timeoutMillis=" + str(_timeoutMillis)
            + " maxRows=" + str(_maxRows)
            + " fetchSize=" + str(_fetchSize) + ")"
    }
}
```
