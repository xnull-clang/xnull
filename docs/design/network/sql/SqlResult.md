# `SqlResult`

| 项 | 值 |
| --- | --- |
| 类型 | `class SqlResult` |
| 包 | `xdk.sql` |
| 稳定性 | `preview` |
| 依赖 | `SqlColumn`、`SqlRow` |

> 包索引见 [`README.md`](README.md)。

---

## 1. 定位

一次执行的完整结果快照：列元数据、行数据、影响行数、是否查询。

不做：流式游标、增量取数、按列名查找、结果集更新、多结果集、类型转换。

---

## 2. 设计逻辑

- 结果在 `execute` 返回时已完整物化；不持有活游标/连接资源。
- `isQuery=true` 表示有结果集：列非空，行可空；`isQuery=false` 表示命令结果：列/行必须为空。
- `rowsAffected` 是 `Long`；查询通常为 0，命令为驱动报告值。`INSERT ... RETURNING` 等既返回结果集又影响行的语句：`isQuery=true`，`rowsAffected` 可为非 0。0 也可能表示“未知”，见包 README 缺口。
- 行长度必须等于列数；构造时逐行校验，避免下游越界。
- 列允许重名；按索引访问，不提供按名查找。
- `columns()`/`rows()` 返回列表副本；元素不可变，无需深拷贝。
- 不可变；无 close；可共享；大结果集的内存成本由列数 × 行数决定。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_columns` | `List<SqlColumn>` | final | 构造时复制；元素非 null |
| `_rows` | `List<SqlRow>` | final | 构造时复制；元素非 null；每行长度 = 列数 |
| `_rowsAffected` | `Long` | final | ≥0 |
| `_isQuery` | `Bool` | final | 是否有结果集 |

不变量：

- 列表非 null；元素非 null。
- `_isQuery=true`：`_columns` 非空；每行 `length() == _columns.length()`；`_rows` 可为空。
- `_isQuery=false`：`_columns` 与 `_rows` 都为空。
- `_rowsAffected >= 0`。
- 对象不可变；返回列表为副本。

---

## 4. 生命周期

由 `execute` 创建并返回；构造后不可变；无 close；GC 管理内存；可共享。连接关闭不影响已返回的结果。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `SqlResult(List<SqlColumn> columns, List<SqlRow> rows, Long rowsAffected, Bool isQuery)` | columns/rows/rowsAffected/isQuery | 列表非 null；元素非 null；行长度 = 列数；rowsAffected ≥0；isQuery 与空列/空行一致 | 非法 → panic |

构造复制 `columns`/`rows` 列表；调用方之后修改原列表不影响结果。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `columns` | 列快照 | 无 | `List<SqlColumn>` | 无 | 列表副本；元素不可变 |
| `columnCount` | 列数 | 无 | `Int` | 无 | 查询 ≥1；命令 0 |
| `rows` | 行快照 | 无 | `List<SqlRow>` | 无 | 列表副本；元素不可变 |
| `rowCount` | 行数 | 无 | `Int` | 无 | 本次快照行数，不是总行数 |
| `rowsAffected` | 影响行数 | 无 | `Long` | 无 | 0 可能表示未知 |
| `isQuery` | 是否查询 | 无 | `Bool` | 无 | true = 有结果集 |
| `equals` | 值相等 | `SqlResult other` | `Bool` | null → false | 列/行/影响数/查询标志 |
| `describe` | 单行诊断 | 无 | `String` | 无 | 只输出计数，不输出数据 |

详细契约：

- `columns()`/`rows()` 返回独立列表；调用方修改列表不影响结果对象。元素 `SqlColumn`/`SqlRow` 不可变。
- `rowCount()` 是本次快照实际行数；受 `SqlOptions.maxRows` 限制时可能小于数据库总行数。
- `rowsAffected()` 对查询通常为 0；对 DML/DDL 为驱动报告值。0 不区分“未知”与“确实为 0”。
- `isQuery()` 为 false 时 `columns()`/`rows()` 返回空列表；调用方应先判断再读取。
- `equals` 比较四个字段与列表顺序；复杂度 O(rows × columns)；null 返回 false。
- `describe` 形如 `"SqlResult(query=true columns=3 rows=10 affected=0)"` 或 `"SqlResult(query=false affected=1)"`；不含行内容。
- 不提供按列名/行号查找；需要时用 `columns()`/`rows()` 副本自行建立索引。

---

## 8. 使用的技术

- 不可变结果快照；
- 列表复制；
- 行列一致性校验；
- 查询/命令双态；
- Long 影响行数；
- 无数据诊断字符串。

---

## 9. 需要的支撑

- 语言：class、final 字段、List、Long、Int、Bool、String；
- 运行时：`List.copy`、`str(Int)`、`str(Long)`；
- 接口：`SqlColumn`、`SqlRow`。

---

## 10. 依赖的特性/接口/类

[`SqlColumn`](SqlColumn.md)、[`SqlRow`](SqlRow.md)。由 [`SqlConnection`](SqlConnection.md) 与 [`SqlTransaction`](SqlTransaction.md) 返回。

---

## 11. 所有权与并发

- 不可变；可跨任务共享；无资源；无取消点。
- 构造复制列/行列表；元素不可变；`columns`/`rows` 再复制列表，O(列数)/O(行数)。
- 相等：`equals` 值比较；`==` 引用身份；不提供哈希；大结果作 `Map` 键代价高，不推荐。
- 排序：不提供；列顺序与行顺序由驱动结果决定。

---

## 12. 示例与反例

正确：先 `isQuery()` 再读 `columns()`/`rows()`；用 `rowCount()` 记录本次返回行数；用 `rowsAffected()` 处理 DML。  
反例：假设 `SELECT` 一定返回行；把 `rowCount()` 当数据库总行数；用 `rowsAffected()` 判断查询是否成功；修改 `rows()` 返回列表期望改变结果；把大结果长期缓存而不设 `maxRows`；把 0 影响行数当“未知”的唯一判断。

---

## 13. 测试/场景义务

查询 0 行/多行；命令 0/正影响行数；查询列空 panic；查询行长度不等于列数 panic；非查询带列/行 panic；负影响行数 panic；null 列表/元素 panic；构造入参复制独立；`columns`/`rows` 副本；`equals` 顺序/字段；`describe` 不含数据；重名列；大结果 `maxRows` 截断；连接关闭后结果仍可读。

---

## 14. XNull 伪代码

```xnull
class SqlResult {
    final List<SqlColumn> _columns
    final List<SqlRow> _rows
    final Long _rowsAffected
    final Bool _isQuery

    SqlResult(List<SqlColumn> columns, List<SqlRow> rows,
              Long rowsAffected, Bool isQuery) {
        if columns == null || rows == null { throw "SqlResult: null list" }
        if rowsAffected < 0 { throw "SqlResult: negative rowsAffected" }
        List<SqlColumn> columnCopy = columns.copy()
        List<SqlRow> rowCopy = rows.copy()
        Int columnIndex = 0
        while columnIndex < columnCopy.length() {
            if columnCopy.get(columnIndex) == null {
                throw "SqlResult: null column"
            }
            columnIndex = columnIndex + 1
        }
        Int rowIndex = 0
        while rowIndex < rowCopy.length() {
            SqlRow row = rowCopy.get(rowIndex)
            if row == null { throw "SqlResult: null row" }
            if row.length() != columnCopy.length() {
                throw "SqlResult: row length mismatch"
            }
            rowIndex = rowIndex + 1
        }
        if isQuery && columnCopy.length() == 0 {
            throw "SqlResult: query without columns"
        }
        if !isQuery && (columnCopy.length() > 0 || rowCopy.length() > 0) {
            throw "SqlResult: non-query with columns or rows"
        }
        _columns = columnCopy
        _rows = rowCopy
        _rowsAffected = rowsAffected
        _isQuery = isQuery
    }

    List<SqlColumn> columns() { return _columns.copy() }
    Int columnCount() { return _columns.length() }
    List<SqlRow> rows() { return _rows.copy() }
    Int rowCount() { return _rows.length() }
    Long rowsAffected() { return _rowsAffected }
    Bool isQuery() { return _isQuery }

    Bool equals(SqlResult other) {
        if other == null { return false }
        if _rowsAffected != other.rowsAffected() { return false }
        if _isQuery != other.isQuery() { return false }
        List<SqlColumn> otherColumns = other.columns()
        if _columns.length() != otherColumns.length() { return false }
        Int index = 0
        while index < _columns.length() {
            if !_columns.get(index).equals(otherColumns.get(index)) {
                return false
            }
            index = index + 1
        }
        List<SqlRow> otherRows = other.rows()
        if _rows.length() != otherRows.length() { return false }
        index = 0
        while index < _rows.length() {
            if !_rows.get(index).equals(otherRows.get(index)) {
                return false
            }
            index = index + 1
        }
        return true
    }

    String describe() {
        if _isQuery {
            return "SqlResult(query=true columns=" + str(_columns.length())
                + " rows=" + str(_rows.length())
                + " affected=" + str(_rowsAffected) + ")"
        }
        return "SqlResult(query=false affected=" + str(_rowsAffected) + ")"
    }
}
```
