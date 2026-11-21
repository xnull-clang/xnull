# `SqlRow`

| 项 | 值 |
| --- | --- |
| 类型 | `class SqlRow` |
| 包 | `xdk.sql` |
| 稳定性 | `preview` |
| 依赖 | `SqlValue` |

> 包索引见 [`README.md`](README.md)。

---

## 1. 定位

不可变结果行：按列索引读取 `SqlValue`，提供长度、直接读取、越界安全读取。

不做：按列名查找、类型转换、行列绑定、可变更新、流式游标。

---

## 2. 设计逻辑

- 行是 `List<SqlValue>` 的不可变快照；构造时复制列表，元素本身不可变。
- 每个位置必须是 `SqlValue`；SQL NULL 用 `SqlValue.nullValue()`，禁止 null 元素。
- `get` 越界是合同错误（panic）；`tryGet` 返回 `SqlValue?`，null 只表示“索引不存在”，不表示 SQL NULL。
- 列名查找不在行上做；重名列时按索引才无歧义。
- 行长度由 `SqlResult` 校验与列数一致；独立构造的行允许长度为 0。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_values` | `List<SqlValue>` | final | 值列表；构造时复制；元素非 null |

不变量：列表非 null；每个元素非 null；列表长度固定；对象不可变；SQL NULL 用 `SqlValue.nullValue()`。

---

## 4. 生命周期

构造后不可变；无 close；GC 管理内存；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `SqlRow(List<SqlValue> values)` | values | 非 null；元素非 null | 非法 → panic |

`values` 在构造时复制；调用方之后修改原列表不影响行。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `length` | 列数 | 无 | `Int` | 无 | 固定 |
| `get` | 按索引读取 | `Int columnIndex` | `SqlValue` | 越界 → panic | O(1) |
| `tryGet` | 越界安全读取 | `Int columnIndex` | `SqlValue?` | 无 | 越界返回 null |
| `equals` | 值相等 | `SqlRow other` | `Bool` | null → false | 逐元素 `SqlValue.equals` |
| `describe` | 单行诊断 | 无 | `String` | 无 | 只输出列数，不输出值 |

详细契约：

- `get` 合法域 `0..length()-1`；越界是调用方错误，panic。
- `tryGet` 对负数与 `>= length()` 返回 null；对合法索引返回非 null `SqlValue`，即使该值是 SQL NULL。
- `equals` 长度相同且每个位置的 `SqlValue.equals` 为 true；不比较列名。
- `describe` 形如 `"SqlRow(values=3)"`；不包含任何值内容。
- 不提供 `values()` 列表副本；需要遍历时用 `length`/`get`，避免额外分配。

---

## 8. 使用的技术

- 不可变行快照；
- 列表复制；
- 越界检查（panic 与 nullable 两条通道）；
- 逐元素值比较。

---

## 9. 需要的支撑

- 语言：class、final 字段、List、Int、Bool、String、nullable 类型；
- 运行时：`List.copy`、`str(Int)`；
- 接口：`SqlValue`。

---

## 10. 依赖的特性/接口/类

[`SqlValue`](SqlValue.md)。可被 [`SqlResult`](SqlResult.md) 持有。

---

## 11. 所有权与并发

- 不可变；可共享；无资源；无取消点。
- 构造时复制列表；元素 `SqlValue` 不可变，无需深拷贝。
- 相等：`equals` 值比较；`==` 引用身份；不提供哈希，不推荐作 `Map` 键。
- 排序：不提供；行顺序由 `SqlResult.rows()` 决定。

---

## 12. 示例与反例

正确：`row.get(0).asLong()`；`row.tryGet(3)` 判断可选列；`while index < row.length()` 遍历。  
反例：把 `tryGet` 返回 null 当 SQL NULL；用 null 元素表示 SQL NULL；`get(-1)` 期望返回 null；修改构造入参列表期望行变化；按列名猜索引。

---

## 13. 测试/场景义务

空行；单列/多列；首/末索引；`get` 越界 panic；`tryGet` 负数/等于长度/合法索引；SQL NULL 与缺失索引区分；null 元素 panic；构造后修改原列表不影响行；`equals` 不同长度/不同值；`describe` 不含值；Unicode/二进制值。

---

## 14. XNull 伪代码

```xnull
class SqlRow {
    final List<SqlValue> _values

    SqlRow(List<SqlValue> values) {
        if values == null { throw "SqlRow: null values" }
        Int index = 0
        while index < values.length() {
            if values.get(index) == null {
                throw "SqlRow: null value at " + str(index)
            }
            index = index + 1
        }
        _values = values.copy()
    }

    Int length() { return _values.length() }

    SqlValue get(Int columnIndex) {
        if columnIndex < 0 || columnIndex >= _values.length() {
            throw "SqlRow.get: columnIndex out of range"
        }
        return _values.get(columnIndex)
    }

    SqlValue? tryGet(Int columnIndex) {
        if columnIndex < 0 || columnIndex >= _values.length() {
            return null
        }
        return _values.get(columnIndex)
    }

    Bool equals(SqlRow other) {
        if other == null { return false }
        if _values.length() != other.length() { return false }
        Int index = 0
        while index < _values.length() {
            if !_values.get(index).equals(other.get(index)) {
                return false
            }
            index = index + 1
        }
        return true
    }

    String describe() {
        return "SqlRow(values=" + str(_values.length()) + ")"
    }
}
```
