# `SqlKind`

| 项 | 值 |
| --- | --- |
| 类型 | `enum SqlKind` |
| 包 | `xdk.sql` |
| 稳定性 | `preview` |
| 依赖 | 无 |

> 包索引见 [`README.md`](README.md)。

---

## 1. 定位

`SqlValue` 的值类型标签：`Null`、`Bool`、`Int`、`Long`、`Double`、`String`、`Bytes`。

用于标记参数/结果值的可移植类型，不表示数据库列的完整类型系统。

不做：SQL 类型名解析、列类型推断、Decimal/时间/UUID/JSON 专用类型、隐式类型转换。

---

## 2. 设计逻辑

- `SqlValue` 是非泛型值类；`SqlKind` 是它的判别标签，避免 `Object?`/泛型擦除。
- `Int` 是 32 位有符号整数；`Long` 是 64 位有符号整数；二者不互相转换。
- `Double` 是 IEEE 754 binary64；NaN/Inf 是合法值，但数据库是否可存储由驱动/方言决定。
- `String` 是 Unicode 文本；驱动负责数据库字符集与 UTF-8 边界转换。
- `Bytes` 是不透明二进制；不解释编码。
- `Null` 是显式值，不是 null 引用；`SqlValue.nullValue().kind()` 返回 `Null`。
- 数据库类型映射由驱动负责；核心不做截断、舍入、精度转换。驱动必须文档化映射，禁止静默有损转换。
- `SqlColumn.typeName` 保留数据库原生类型名；`SqlKind` 只描述传输值。

---

## 3. 表示与不变量

| 成员 | 含义 | 备注 |
| --- | --- | --- |
| `Null` | SQL NULL | 唯一表示空值的方式 |
| `Bool` | 布尔 | true/false |
| `Int` | 32 位有符号 | 不升级为 Long |
| `Long` | 64 位有符号 | 不降级为 Int |
| `Double` | binary64 | 含 NaN/Inf |
| `String` | Unicode 文本 | 可为空串 |
| `Bytes` | 二进制 | 可为空字节串 |

不变量：成员固定；只允许在后续版本追加；`Null` 不是“缺失的 kind”；无隐式数值码。

---

## 4. 生命周期

值类型；无 close；可共享。

---

## 5. 构造契约

枚举成员直接使用；不提供文本 `parse`。文本名只用于诊断，由 `sqlKindName` 生成。

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

无实例方法。相关顶层函数：

| 函数 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `sqlKindName` | 稳定小写名 | `SqlKind kind` | `String` | 无 | 用于日志/诊断；名称稳定，不随 locale 变化 |

详细契约：

- `Null -> "null"`、`Bool -> "bool"`、`Int -> "int"`、`Long -> "long"`、`Double -> "double"`、`String -> "string"`、`Bytes -> "bytes"`。
- 参数为非 null 枚举值；传入 null 是合同错误（panic）。
- 不提供反向解析；需要从配置构造值的场景由驱动/应用自行映射。

---

## 8. 使用的技术

- 判别标签；
- 简单枚举；
- 稳定名称表；
- 可移植值子集。

---

## 9. 需要的支撑

- 语言：enum、String；
- 运行时：无；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

值语义；无资源；可共享；相等按成员身份；可作 `Map` 键。无取消点。

---

## 12. 示例与反例

正确：`SqlValue.ofLong(42).kind() == SqlKind.Long`；`SqlValue.nullValue().kind() == SqlKind.Null`。  
反例：用 `Int` 承载 64 位值；用 `String` 表示 SQL NULL；把 `SqlKind` 当数据库列类型；依赖隐式 Int/Long 转换。

---

## 13. 测试/场景义务

全部 7 个成员；`sqlKindName` 名称稳定性；`Null` 与 null 引用区分；`Int`/`Long` 不互通；`Double` 的 NaN/Inf；`String` 空串；`Bytes` 空字节串；null 合同错误。

---

## 14. XNull 伪代码

```xnull
enum SqlKind {
    Null,
    Bool,
    Int,
    Long,
    Double,
    String,
    Bytes,
}

String sqlKindName(SqlKind kind) {
    if kind == null { throw "sqlKindName: null kind" }
    if kind == SqlKind.Null { return "null" }
    if kind == SqlKind.Bool { return "bool" }
    if kind == SqlKind.Int { return "int" }
    if kind == SqlKind.Long { return "long" }
    if kind == SqlKind.Double { return "double" }
    if kind == SqlKind.String { return "string" }
    return "bytes"
}
```
