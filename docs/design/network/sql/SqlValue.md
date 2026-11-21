# `SqlValue`

| 项 | 值 |
| --- | --- |
| 类型 | `class SqlValue` |
| 包 | `xdk.sql` |
| 稳定性 | `preview` |
| 依赖 | `SqlKind`、`Bytes`、`Error` |

> 包索引见 [`README.md`](README.md)。

---

## 1. 定位

非泛型 SQL 值：一个 `SqlKind` 标签加一个有效载荷。提供类型工厂与类型检查读取，SQL NULL 是显式值。

不做：数据库类型名解析、Decimal/时间/UUID/JSON、隐式数值/文本转换、值序列化、SQL 字面量拼接。

---

## 2. 设计逻辑

- 非泛型，避免 `SqlValue<T>` 在参数列表/结果行中产生类型擦除与装箱歧义。
- 用 7 个 kind 覆盖可移植子集；`Null` 是独立 kind，不用 null 引用表示 SQL NULL。
- 每个值只保留一个有效载荷；未使用的载荷字段保持默认值，读取必须经过 `as*` 类型检查。
- `Int`、`Long`、`Double` 不互相转换；跨类型读取返回 `InvalidArgument`，不做截断/舍入。
- `String` 与 `Bytes` 在边界复制；`Bytes` 可变，不能把调用方缓冲别名进值对象。
- `Double` 保留 NaN/Inf；相等比较把两个 NaN 视为相等，避免值对象反射性失败。
- `describe` 只输出 kind，不输出值，避免日志泄漏参数/结果内容。
- 无 close；不可变；可跨任务共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_kind` | `SqlKind` | final | 判别标签，非 null |
| `_boolValue` | `Bool` | final | `Bool` 载荷；其他 kind 为 false |
| `_intValue` | `Int` | final | `Int` 载荷；其他 kind 为 0 |
| `_longValue` | `Long` | final | `Long` 载荷；其他 kind 为 0 |
| `_doubleValue` | `Double` | final | `Double` 载荷；其他 kind 为 0.0 |
| `_stringValue` | `String` | final | `String` 载荷；其他 kind 为空串；非 null |
| `_bytesValue` | `Bytes` | final | `Bytes` 载荷；其他 kind 为空字节串；非 null；构造时复制 |

不变量：

- `_kind` 非 null；`_stringValue`/`_bytesValue` 非 null。
- 只有 `_kind` 对应的载荷有意义；其他载荷保持默认值，`as*` 必须先检查 kind。
- `Bytes` 载荷不与调用方共享；`asBytes` 返回副本。
- 值对象构造后不可变；`_stringValue` 本身不可变。

---

## 4. 生命周期

由静态工厂创建；构造后不可变；无 close；GC 管理内存；可共享。

---

## 5. 构造契约

私有构造只供工厂使用。公开工厂：

| 工厂 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `SqlValue.nullValue()` | 无 | 创建 SQL NULL | 无 |
| `SqlValue.ofBool(Bool value)` | value | 任意 Bool | 无 |
| `SqlValue.ofInt(Int value)` | value | 任意 Int | 无 |
| `SqlValue.ofLong(Long value)` | value | 任意 Long | 无 |
| `SqlValue.ofDouble(Double value)` | value | 任意 binary64（含 NaN/Inf） | 无 |
| `SqlValue.ofString(String value)` | value | 非 null；可空串 | null → panic |
| `SqlValue.ofBytes(Bytes value)` | value | 非 null；构造时复制 | null → panic |

工厂总是返回非 null `SqlValue`；非法输入是合同错误（panic），不返回 `Result`。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `nullValue` | 创建 SQL NULL | 无 | `SqlValue` | 无 | 静态工厂 |
| `ofBool` | 创建 Bool 值 | `Bool value` | `SqlValue` | 无 | 静态工厂 |
| `ofInt` | 创建 Int 值 | `Int value` | `SqlValue` | 无 | 静态工厂 |
| `ofLong` | 创建 Long 值 | `Long value` | `SqlValue` | 无 | 静态工厂 |
| `ofDouble` | 创建 Double 值 | `Double value` | `SqlValue` | 无 | 静态工厂；保留 NaN/Inf |
| `ofString` | 创建 String 值 | `String value` | `SqlValue` | null → panic | 静态工厂；可空串 |
| `ofBytes` | 创建 Bytes 值 | `Bytes value` | `SqlValue` | null → panic | 静态工厂；复制 |
| `kind` | 读取标签 | 无 | `SqlKind` | 无 | 纯读取 |
| `isNull` | 是否 SQL NULL | 无 | `Bool` | 无 | 等价于 `kind() == SqlKind.Null` |
| `asBool` | 读 Bool | 无 | `Result<Bool, Error>` | 非 Bool → `InvalidArgument` | 不转换 |
| `asInt` | 读 Int | 无 | `Result<Int, Error>` | 非 Int → `InvalidArgument` | 不转换 |
| `asLong` | 读 Long | 无 | `Result<Long, Error>` | 非 Long → `InvalidArgument` | 不转换 |
| `asDouble` | 读 Double | 无 | `Result<Double, Error>` | 非 Double → `InvalidArgument` | 保留 NaN/Inf |
| `asString` | 读 String | 无 | `Result<String, Error>` | 非 String → `InvalidArgument` | 借用不可变 String |
| `asBytes` | 读 Bytes 副本 | 无 | `Result<Bytes, Error>` | 非 Bytes → `InvalidArgument` | O(n) 复制 |
| `equals` | 值相等 | `SqlValue other` | `Bool` | null → false | Bytes 按内容；两个 NaN 相等 |
| `describe` | 单行诊断 | 无 | `String` | 无 | 只输出 kind，不输出载荷 |

详细契约：

- `as*` 对 `Null` 或错误 kind 返回 `InvalidArgument`；错误消息只含期望 kind 与实际 kind 名，不含载荷。
- `asInt` 不把 `Long` 截断；`asLong` 不把 `Int` 扩展；需要转换时由调用方显式决定。
- `asString` 返回不可变 String；`asBytes` 每次返回独立副本，调用方可修改而不会影响值对象。
- `equals`：kind 不同为 false；`Null` 之间为 true；`Double` 两个 NaN 为 true，其他按 `==`；`Bytes` 逐字节比较。
- `describe` 形如 `"SqlValue(kind=long)"`；不包含字符串内容、字节内容、数值。
- 不提供 `hash`；`==` 是引用身份；需要值比较用 `equals`；不推荐作 `Map` 键。

---

## 8. 使用的技术

- 判别联合（tagged union）的类表示；
- 非泛型值对象；
- 工厂方法；
- 类型检查读取；
- Bytes 边界复制；
- NaN 反射性处理；
- 无载荷诊断字符串。

---

## 9. 需要的支撑

- 语言：class、final 字段、Bool、Int、Long、Double、String、Bytes、Result；
- 运行时：`Bytes.empty`、`copy(Bytes)`、`equals(Bytes, Bytes)`、`isNaN(Double)`；
- 接口：`SqlKind`、`Error`、`BasicError`、`ErrorKind`、`sqlKindName`。

---

## 10. 依赖的特性/接口/类

`SqlKind`、[`Bytes`](../../core/bytes/Bytes.md)、[`Error`](../../core/errors/Error.md)、[`BasicError`](../../core/errors/BasicError.md)、[`ErrorKind`](../../core/errors/ErrorKind.md)、`sqlKindName`、`isNaN`。

---

## 11. 所有权与并发

- 不可变；可跨任务共享；无资源；无取消点。
- `ofBytes` 复制入参；`asBytes` 返回新副本；调用方缓冲与值对象互不影响。
- 相等：`equals` 值比较；`==` 引用身份；不提供哈希，不推荐作 `Map` 键。
- 排序：不提供；需要排序时调用方按 kind 与业务语义决定。

---

## 12. 示例与反例

正确：`SqlValue.ofLong(42).asLong()`；`SqlValue.nullValue().isNull()`；`SqlValue.ofString("Ada").asString()`。  
反例：用 null 引用表示 SQL NULL；对 `SqlValue.ofLong(42)` 调 `asInt()` 期望截断；把 `Bytes` 入参直接存进值对象；日志打印 `asString()` 造成敏感数据泄漏；用 `==` 比较值。

---

## 13. 测试/场景义务

7 个 kind 的工厂与读取；Null 与 null 引用区分；错误 kind 的 `as*`；Int/Long 不互通；Double 的 NaN/Inf/-0.0；String 空串/Unicode；Bytes 空串/复制独立性；`equals` 的 Null/Bytes/NaN；`describe` 不含载荷；null 工厂参数 panic；长时间共享无状态变化。

---

## 14. XNull 伪代码

```xnull
class SqlValue {
    final SqlKind _kind
    final Bool _boolValue
    final Int _intValue
    final Long _longValue
    final Double _doubleValue
    final String _stringValue
    final Bytes _bytesValue

    private SqlValue(SqlKind kind, Bool boolValue, Int intValue,
                     Long longValue, Double doubleValue, String stringValue,
                     Bytes bytesValue) {
        if kind == null { throw "SqlValue: null kind" }
        if stringValue == null { throw "SqlValue: null string" }
        if bytesValue == null { throw "SqlValue: null bytes" }
        _kind = kind
        _boolValue = boolValue
        _intValue = intValue
        _longValue = longValue
        _doubleValue = doubleValue
        _stringValue = stringValue
        _bytesValue = copy(bytesValue)
    }

    static SqlValue nullValue() {
        return new SqlValue(SqlKind.Null, false, 0, 0, 0.0, "", Bytes.empty())
    }

    static SqlValue ofBool(Bool value) {
        return new SqlValue(SqlKind.Bool, value, 0, 0, 0.0, "", Bytes.empty())
    }

    static SqlValue ofInt(Int value) {
        return new SqlValue(SqlKind.Int, false, value, 0, 0.0, "", Bytes.empty())
    }

    static SqlValue ofLong(Long value) {
        return new SqlValue(SqlKind.Long, false, 0, value, 0.0, "", Bytes.empty())
    }

    static SqlValue ofDouble(Double value) {
        return new SqlValue(SqlKind.Double, false, 0, 0, value, "", Bytes.empty())
    }

    static SqlValue ofString(String value) {
        if value == null { throw "SqlValue.ofString: null value" }
        return new SqlValue(SqlKind.String, false, 0, 0, 0.0, value, Bytes.empty())
    }

    static SqlValue ofBytes(Bytes value) {
        if value == null { throw "SqlValue.ofBytes: null value" }
        return new SqlValue(SqlKind.Bytes, false, 0, 0, 0.0, "", value)
    }

    SqlKind kind() { return _kind }

    Bool isNull() { return _kind == SqlKind.Null }

    Result<Bool, Error> asBool() {
        if _kind != SqlKind.Bool {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SqlValue.asBool: kind=" + sqlKindName(_kind)))
        }
        return Ok(_boolValue)
    }

    Result<Int, Error> asInt() {
        if _kind != SqlKind.Int {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SqlValue.asInt: kind=" + sqlKindName(_kind)))
        }
        return Ok(_intValue)
    }

    Result<Long, Error> asLong() {
        if _kind != SqlKind.Long {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SqlValue.asLong: kind=" + sqlKindName(_kind)))
        }
        return Ok(_longValue)
    }

    Result<Double, Error> asDouble() {
        if _kind != SqlKind.Double {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SqlValue.asDouble: kind=" + sqlKindName(_kind)))
        }
        return Ok(_doubleValue)
    }

    Result<String, Error> asString() {
        if _kind != SqlKind.String {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SqlValue.asString: kind=" + sqlKindName(_kind)))
        }
        return Ok(_stringValue)
    }

    Result<Bytes, Error> asBytes() {
        if _kind != SqlKind.Bytes {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SqlValue.asBytes: kind=" + sqlKindName(_kind)))
        }
        return Ok(copy(_bytesValue))
    }

    Bool equals(SqlValue other) {
        if other == null { return false }
        if _kind != other._kind { return false }
        if _kind == SqlKind.Null { return true }
        if _kind == SqlKind.Bool { return _boolValue == other._boolValue }
        if _kind == SqlKind.Int { return _intValue == other._intValue }
        if _kind == SqlKind.Long { return _longValue == other._longValue }
        if _kind == SqlKind.Double {
            if isNaN(_doubleValue) && isNaN(other._doubleValue) { return true }
            return _doubleValue == other._doubleValue
        }
        if _kind == SqlKind.String { return _stringValue == other._stringValue }
        return equals(_bytesValue, other._bytesValue)
    }

    String describe() {
        return "SqlValue(kind=" + sqlKindName(_kind) + ")"
    }
}
```
