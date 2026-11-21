# `SqlDialect`

| 项 | 值 |
| --- | --- |
| 类型 | `enum SqlDialect` |
| 包 | `xdk.sql` |
| 稳定性 | `preview` |
| 依赖 | 无 |

> 包索引见 [`README.md`](README.md)。

---

## 1. 定位

SQL 方言标识：`Postgres`、`MySql`、`Sqlite`、`Mssql`、`Oracle`、`Generic`。

用于驱动/连接报告方言，帮助调用方选择驱动、记录诊断、决定是否使用生态扩展。

不做：方言版本探测、标识符引用、占位符改写、SQL 生成/解析、能力协商。

---

## 2. 设计逻辑

- 方言是封闭集合，用 enum 而不是字符串；驱动实现不能私造方言值。
- `Generic` 表示“通用/未报告具体方言”，不是通配符；方言特定 SQL 仍由调用方与驱动文档决定。
- 方言只描述语法家族，不承诺功能；不支持的能力返回 `Unsupported`。
- 不定义数值码；稳定名由 `sqlDialectName` 提供，供日志/配置使用。
- 值语义；无 close；可共享。
- 核心层不做 `Postgres -> $1`、`MySql -> ?` 的占位符转换；参数绑定由驱动完成。

---

## 3. 表示与不变量

| 成员 | 含义 |
| --- | --- |
| `Postgres` | PostgreSQL 语法家族 |
| `MySql` | MySQL/MariaDB 语法家族 |
| `Sqlite` | SQLite 语法家族 |
| `Mssql` | Microsoft SQL Server 语法家族 |
| `Oracle` | Oracle Database 语法家族 |
| `Generic` | 通用/ANSI 子集，或驱动未报告具体方言 |

不变量：成员固定；只允许在后续版本追加；`Generic` 不得被解释为任一具体方言；无隐式 Int 转换。

---

## 4. 生命周期

值类型；无 close；可共享。

---

## 5. 构造契约

枚举成员直接使用；不提供文本 `parse`。驱动从自身配置/URI 决定方言，并通过 `SqlConnection.dialect()` 报告。

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

无实例方法。相关顶层函数：

| 函数 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `sqlDialectName` | 稳定小写名 | `SqlDialect dialect` | `String` | 无 | 用于日志/配置；名称稳定，不随 locale 变化 |

详细契约：

- `Postgres -> "postgres"`、`MySql -> "mysql"`、`Sqlite -> "sqlite"`、`Mssql -> "mssql"`、`Oracle -> "oracle"`、`Generic -> "generic"`。
- 参数为非 null 枚举值；传入 null 是合同错误（panic）。
- 不提供反向解析；配置层若需反向映射，由驱动/应用自行维护名称表。

---

## 8. 使用的技术

- 简单枚举；
- 稳定名称表；
- 值语义。

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

正确：`SqlDialect.Postgres`；比较 `connection.dialect() == SqlDialect.Sqlite`；日志用 `sqlDialectName(connection.dialect())`。  
反例：用方言拼接/改写 SQL；把 `Generic` 当 Postgres；持久化枚举序号；用字符串比较代替枚举。

---

## 13. 测试/场景义务

成员完整性；`sqlDialectName` 名称稳定性；`Generic` 语义；无隐式数值转换；驱动报告与实际方言一致；名称往返用于日志/配置；null 合同错误。

---

## 14. XNull 伪代码

```xnull
enum SqlDialect {
    Postgres,
    MySql,
    Sqlite,
    Mssql,
    Oracle,
    Generic,
}

String sqlDialectName(SqlDialect dialect) {
    if dialect == null { throw "sqlDialectName: null dialect" }
    if dialect == SqlDialect.Postgres { return "postgres" }
    if dialect == SqlDialect.MySql { return "mysql" }
    if dialect == SqlDialect.Sqlite { return "sqlite" }
    if dialect == SqlDialect.Mssql { return "mssql" }
    if dialect == SqlDialect.Oracle { return "oracle" }
    return "generic"
}
```
