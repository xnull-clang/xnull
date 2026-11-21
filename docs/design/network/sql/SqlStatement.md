# `SqlStatement`

| 项 | 值 |
| --- | --- |
| 类型 | `class SqlStatement` |
| 包 | `xdk.sql` |
| 稳定性 | `preview` |
| 依赖 | `SqlParameter`、`SqlValue` |

> 包索引见 [`README.md`](README.md)。

---

## 1. 定位

不可变 SQL 语句：SQL 文本加参数列表。提供位置绑定、显式参数追加、清空参数。

不做：SQL 解析/校验、占位符改写、值字符串拼接、方言生成、参数名到驱动语法的映射、执行。

---

## 2. 设计逻辑

- 语句只携带文本与参数；SQL 文本原样保留，不裁剪、不改写。
- 不可变构建：`bind`/`withParameter`/`clear` 返回新语句，原语句可安全复用/共享。
- 一条语句只能全索引或全命名；空语句尚未决定风格，第一个参数决定。
- 索引参数按列表顺序连续编号 1..n；命名参数唯一，顺序保留。
- 不解析 SQL 中的 `?`/`$1`/`:name` 数量；参数数量与占位符是否匹配由驱动在 `execute` 时校验。
- 语句不含 `SqlOptions`；每次执行的控制面由 `execute` 重载传入。
- 不提供字符串插值 API；调用方必须使用参数。
- `describe` 不输出 SQL 文本，避免日志泄漏字面量/敏感条件。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_sql` | `String` | final | 非 null；trim 后非空；原样保留 |
| `_parameters` | `List<SqlParameter>` | final | 构造时复制；元素非 null |

不变量：

- `_sql` 非空（至少一个非空白字符）；保留原始空白/大小写/注释。
- `_parameters` 非 null；每个元素非 null。
- 参数要么全索引、要么全命名；空列表两者都不是。
- 索引参数：第 i 个（0 起）的 `parameterIndex == i + 1`，即连续 1..n。
- 命名参数：名称非空且互不重复；列表顺序保留。
- 对象不可变；`parameters()` 返回列表副本。

---

## 4. 生命周期

构造后不可变；无 close；GC 管理内存；可共享。`bind`/`withParameter`/`clear` 产生新对象，旧对象不受影响。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `SqlStatement(String sqlText)` | sqlText | 非 null；trim 后非空 | 非法 → panic |
| `SqlStatement(String sqlText, List<SqlParameter> parameterList)` | sqlText/parameterList | sqlText 同上；列表非 null；元素非 null；风格单一；索引连续；命名唯一 | 非法 → panic |

第二个构造复制参数列表；调用方之后修改原列表不影响语句。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `sql` | SQL 文本 | 无 | `String` | 无 | 原样；不可变 |
| `parameters` | 参数快照 | 无 | `List<SqlParameter>` | 无 | 列表副本 |
| `parameterCount` | 参数数 | 无 | `Int` | 无 | 列表长度 |
| `isNamedParameters` | 是否命名参数 | 无 | `Bool` | 无 | 空语句返回 false |
| `bind` | 追加索引参数 | `SqlValue value` | `SqlStatement` | 命名语句/null → panic | 返回新语句；索引自动加 1 |
| `withParameter` | 追加显式参数 | `SqlParameter parameter` | `SqlStatement` | null/混用/索引不连续/重名 → panic | 返回新语句 |
| `clear` | 清空参数 | 无 | `SqlStatement` | 无 | 保留 SQL 文本；返回新语句 |
| `equals` | 值相等 | `SqlStatement other` | `Bool` | null → false | 文本 + 参数顺序 |
| `describe` | 单行诊断 | 无 | `String` | 无 | 只输出长度/参数数/风格，不输出 SQL |

详细契约：

- `sql()` 返回原字符串；String 不可变，无需复制。
- `parameters()` 返回参数列表副本；元素 `SqlParameter` 不可变，无需深拷贝。
- `bind` 只能用于空语句或索引语句；在命名语句上调用是合同错误（panic）。新参数索引为 `parameterCount() + 1`。
- `withParameter` 在空语句上接受任一风格；之后必须同风格。索引参数必须满足 `parameterIndex == parameterCount() + 1`；命名参数必须唯一。违反任一条件是合同错误（panic）。
- `clear()` 返回同一 SQL 文本、空参数列表的新语句；原语句不变。
- `equals` 比较 SQL 文本与参数列表顺序；命名参数顺序不同视为不相等；不提供哈希。
- `describe` 形如 `"SqlStatement(sqlLength=42 parameters=2 style=named)"`；不输出 SQL 文本与参数值。
- 语句不校验占位符数量；`execute` 时由驱动返回 `InvalidArgument`。

---

## 8. 使用的技术

- 不可变构建器；
- 参数风格判别；
- 列表复制；
- 1 起连续索引；
- 命名唯一性校验；
- 无 SQL 解析。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Int、Bool、List；
- 运行时：`trim(String)`、`List.copy`、`List.push`、`str(Int)`；
- 接口：`SqlParameter`、`SqlValue`。

---

## 10. 依赖的特性/接口/类

[`SqlParameter`](SqlParameter.md)、[`SqlValue`](SqlValue.md)。被 [`SqlConnection`](SqlConnection.md) 与 [`SqlTransaction`](SqlTransaction.md) 消费。

---

## 11. 所有权与并发

- 不可变；可跨任务共享；无资源；无取消点。
- `bind`/`withParameter`/`clear` 每次复制参数列表，复杂度 O(n)；适合参数数量有限的语句。
- 相等：`equals` 值比较（文本 + 参数顺序）；`==` 引用身份；不提供哈希，不推荐作 `Map` 键。
- 排序：不提供；参数顺序由列表决定。

---

## 12. 示例与反例

正确：`new SqlStatement("select user_key from users where user_key = ?").bind(SqlValue.ofLong(42))`；`new SqlStatement("select user_key from users where name = :name").withParameter(SqlParameter.named("name", SqlValue.ofString("Ada")))`。  
反例：把值拼进 SQL 字符串；在命名语句上 `bind`；索引参数跳号；命名参数重名；期望 `bind` 校验占位符数量；修改 `parameters()` 返回列表期望改变语句；用 `describe()` 打印 SQL 原文。

---

## 13. 测试/场景义务

空/全空白 SQL panic；单个/多个索引参数；索引连续；索引跳号 panic；命名参数唯一/重名 panic；混用风格 panic；`bind` 在命名语句 panic；`withParameter` 空语句决定风格；`clear` 保留 SQL；构造入参列表复制独立；不可变链式调用原语句不变；`parameters()` 副本；`equals` 顺序敏感；`describe` 不含 SQL；Unicode SQL/参数名。

---

## 14. XNull 伪代码

```xnull
class SqlStatement {
    final String _sql
    final List<SqlParameter> _parameters

    SqlStatement(String sqlText) {
        if sqlText == null { throw "SqlStatement: null sql" }
        if trim(sqlText) == "" { throw "SqlStatement: empty sql" }
        _sql = sqlText
        _parameters = []
    }

    SqlStatement(String sqlText, List<SqlParameter> parameterList) {
        if sqlText == null { throw "SqlStatement: null sql" }
        if trim(sqlText) == "" { throw "SqlStatement: empty sql" }
        if parameterList == null { throw "SqlStatement: null parameters" }
        List<SqlParameter> copied = parameterList.copy()
        Bool hasIndexed = false
        Bool hasNamed = false
        Int index = 0
        while index < copied.length() {
            SqlParameter parameter = copied.get(index)
            if parameter == null {
                throw "SqlStatement: null parameter"
            }
            if parameter.isIndexed() {
                hasIndexed = true
                if parameter.parameterIndex() != index + 1 {
                    throw "SqlStatement: non-contiguous index"
                }
            }
            if parameter.isNamed() {
                hasNamed = true
                Int scan = 0
                while scan < index {
                    SqlParameter previous = copied.get(scan)
                    if previous.isNamed()
                            && previous.name() == parameter.name() {
                        throw "SqlStatement: duplicate parameter name"
                    }
                    scan = scan + 1
                }
            }
            index = index + 1
        }
        if hasIndexed && hasNamed {
            throw "SqlStatement: mixed parameter styles"
        }
        _sql = sqlText
        _parameters = copied
    }

    String sql() { return _sql }
    List<SqlParameter> parameters() { return _parameters.copy() }
    Int parameterCount() { return _parameters.length() }

    Bool isNamedParameters() {
        if _parameters.length() == 0 { return false }
        return _parameters.get(0).isNamed()
    }

    SqlStatement bind(SqlValue value) {
        if value == null { throw "SqlStatement.bind: null value" }
        if self.isNamedParameters() {
            throw "SqlStatement.bind: named statement"
        }
        List<SqlParameter> next = _parameters.copy()
        next.push(SqlParameter.indexed(next.length() + 1, value))
        return new SqlStatement(_sql, next)
    }

    SqlStatement withParameter(SqlParameter parameter) {
        if parameter == null { throw "SqlStatement.withParameter: null parameter" }
        List<SqlParameter> next = _parameters.copy()
        if _parameters.length() == 0 {
            if parameter.isIndexed() && parameter.parameterIndex() != 1 {
                throw "SqlStatement.withParameter: first index must be 1"
            }
        } else {
            Bool currentNamed = _parameters.get(0).isNamed()
            if currentNamed != parameter.isNamed() {
                throw "SqlStatement.withParameter: mixed styles"
            }
            if parameter.isIndexed()
                    && parameter.parameterIndex() != next.length() + 1 {
                throw "SqlStatement.withParameter: non-contiguous index"
            }
        }
        next.push(parameter)
        return new SqlStatement(_sql, next)
    }

    SqlStatement clear() {
        return new SqlStatement(_sql)
    }

    Bool equals(SqlStatement other) {
        if other == null { return false }
        if _sql != other.sql() { return false }
        List<SqlParameter> otherParameters = other.parameters()
        if _parameters.length() != otherParameters.length() { return false }
        Int index = 0
        while index < _parameters.length() {
            if !_parameters.get(index).equals(otherParameters.get(index)) {
                return false
            }
            index = index + 1
        }
        return true
    }

    String describe() {
        String style = "none"
        if self.isNamedParameters() {
            style = "named"
        } else if _parameters.length() > 0 {
            style = "indexed"
        }
        return "SqlStatement(sqlLength=" + str(_sql.length())
            + " parameters=" + str(_parameters.length())
            + " style=" + style + ")"
    }
}
```
