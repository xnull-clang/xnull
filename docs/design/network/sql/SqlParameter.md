# `SqlParameter`

| 项 | 值 |
| --- | --- |
| 类型 | `class SqlParameter` |
| 包 | `xdk.sql` |
| 稳定性 | `preview` |
| 依赖 | `SqlValue` |

> 包索引见 [`README.md`](README.md)。

---

## 1. 定位

语句参数：索引参数或命名参数，携带一个不可变 `SqlValue`。

不做：占位符解析、SQL 文本改写、参数名到驱动语法的映射、默认值、输出参数。

---

## 2. 设计逻辑

- 一条参数只能是索引或命名之一；用私有构造与两个工厂保证。
- 索引从 1 开始；`parameterIndex=0` 只作为命名参数的哨兵，不是合法索引。
- 命名参数是逻辑名，不含 `:name`、`@name`、`$1` 等驱动前缀；驱动负责映射到自己的占位符。
- `name` 保留原样，不裁剪；只拒绝 null 与全空白。
- `value` 非 null；SQL NULL 用 `SqlValue.nullValue()`。
- 不可变；无 close；可共享。
- `describe` 不输出值，只输出模式与 kind。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_parameterIndex` | `Int` | final | 索引参数为 `>=1`；命名参数为 0 |
| `_name` | `String` | final | 命名参数为非空字符串；索引参数为空串 |
| `_value` | `SqlValue` | final | 非 null |

不变量：`isIndexed()` 与 `isNamed()` 恰好一个为 true；索引参数 `_parameterIndex >= 1` 且 `_name == ""`；命名参数 `_parameterIndex == 0` 且 `_name` 非空；`_value` 非 null。

---

## 4. 生命周期

由静态工厂创建；构造后不可变；无 close；GC 管理内存；可共享。

---

## 5. 构造契约

私有构造只供工厂使用。公开工厂：

| 工厂 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `SqlParameter.indexed(Int parameterIndex, SqlValue value)` | parameterIndex/value | parameterIndex ≥1；value 非 null | 非法 → panic |
| `SqlParameter.named(String name, SqlValue value)` | name/value | name 非 null 且 trim 后非空；value 非 null | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `indexed` | 创建索引参数 | `Int parameterIndex, SqlValue value` | `SqlParameter` | 非法 → panic | 静态工厂；索引 1 起 |
| `named` | 创建命名参数 | `String name, SqlValue value` | `SqlParameter` | 非法 → panic | 静态工厂；name 不含前缀 |
| `parameterIndex` | 索引值 | 无 | `Int` | 无 | 命名参数返回 0 哨兵 |
| `name` | 逻辑名 | 无 | `String` | 无 | 索引参数返回空串 |
| `value` | 参数值 | 无 | `SqlValue` | 无 | 不可变值 |
| `isIndexed` | 是否索引参数 | 无 | `Bool` | 无 | `parameterIndex > 0` |
| `isNamed` | 是否命名参数 | 无 | `Bool` | 无 | `name` 非空 |
| `equals` | 值相等 | `SqlParameter other` | `Bool` | null → false | 比较索引/名称/值 |
| `describe` | 单行诊断 | 无 | `String` | 无 | 不含值 |

详细契约：

- `indexed` 的 `parameterIndex` 是语句内位置，从 1 开始；`0` 与负数非法。
- `named` 的 `name` 是裸逻辑名；`":userId"`、`"@userId"` 不作为约定，是否接受由驱动决定，核心推荐传入 `"userId"`。
- `parameterIndex()` 在命名参数上返回 0；`name()` 在索引参数上返回空串；调用方应先用 `isIndexed`/`isNamed` 分支。
- `value()` 返回不可变 `SqlValue`；调用方不能通过参数对象修改值。
- `equals` 比较模式、索引/名称与值；null 返回 false。
- `describe` 形如 `"SqlParameter(indexed=1 kind=long)"` 或 `"SqlParameter(named=userId kind=string)"`；不输出值内容。

---

## 8. 使用的技术

- 判别式参数（索引/命名）；
- 私有构造 + 静态工厂；
- 1 起索引；
- 逻辑名与驱动占位符分离；
- 不可变值对象。

---

## 9. 需要的支撑

- 语言：class、final 字段、Int、String、Bool；
- 运行时：`trim(String)`、`str(Int)`；
- 接口：`SqlValue`、`SqlKind`、`sqlKindName`。

---

## 10. 依赖的特性/接口/类

[`SqlValue`](SqlValue.md)、[`SqlKind`](SqlKind.md)、`sqlKindName`。被 [`SqlStatement`](SqlStatement.md) 持有。

---

## 11. 所有权与并发

- 不可变；可共享；无资源；无取消点。
- `SqlValue` 不可变，`value()` 直接返回；无需复制。
- 相等：`equals` 值比较；`==` 引用身份；不提供哈希，不推荐作 `Map` 键。
- 排序：不提供；参数顺序由 `SqlStatement` 列表决定。

---

## 12. 示例与反例

正确：`SqlParameter.indexed(1, SqlValue.ofLong(42))`；`SqlParameter.named("userId", SqlValue.ofLong(42))`。  
反例：索引 0；同时传索引与名称；名称传 `":userId"` 期望核心剥离前缀；用 null 值表示 SQL NULL；把命名参数的 `parameterIndex()` 当合法索引使用。

---

## 13. 测试/场景义务

索引 1/最大合法值；索引 0/负数 panic；命名空串/全空白 panic；命名合法 Unicode；value null panic；`isIndexed`/`isNamed` 互斥；`parameterIndex`/`name` 哨兵；equals；describe 不含值；索引/命名参数在语句中混用被拒绝。

---

## 14. XNull 伪代码

```xnull
class SqlParameter {
    final Int _parameterIndex
    final String _name
    final SqlValue _value

    private SqlParameter(Int parameterIndex, String name, SqlValue value) {
        if name == null { throw "SqlParameter: null name" }
        if value == null { throw "SqlParameter: null value" }
        if parameterIndex < 0 { throw "SqlParameter: negative index" }
        Bool indexed = parameterIndex > 0
        Bool named = name.length() > 0
        if indexed == named {
            throw "SqlParameter: exactly one of index/name is required"
        }
        _parameterIndex = parameterIndex
        _name = name
        _value = value
    }

    static SqlParameter indexed(Int parameterIndex, SqlValue value) {
        if parameterIndex < 1 {
            throw "SqlParameter.indexed: parameterIndex < 1"
        }
        return new SqlParameter(parameterIndex, "", value)
    }

    static SqlParameter named(String name, SqlValue value) {
        if name == null || trim(name) == "" {
            throw "SqlParameter.named: empty name"
        }
        return new SqlParameter(0, name, value)
    }

    Int parameterIndex() { return _parameterIndex }
    String name() { return _name }
    SqlValue value() { return _value }

    Bool isIndexed() { return _parameterIndex > 0 }
    Bool isNamed() { return _name.length() > 0 }

    Bool equals(SqlParameter other) {
        if other == null { return false }
        return _parameterIndex == other.parameterIndex()
            && _name == other.name()
            && _value.equals(other.value())
    }

    String describe() {
        String mode = ""
        if self.isIndexed() {
            mode = "indexed=" + str(_parameterIndex)
        }
        if self.isNamed() {
            mode = "named=" + _name
        }
        return "SqlParameter(" + mode + " kind=" + sqlKindName(_value.kind()) + ")"
    }
}
```
