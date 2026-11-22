# `SqlColumn`

| 项 | 值 |
| --- | --- |
| 类型 | `class SqlColumn` |
| 包 | `xdk.sql` |
| 稳定性 | `preview` |
| 依赖 | 无 |

> 包索引见 [`README.md`](README.md)。

---

> 注解合同（A8，planned）：`@Value` 生成 `equals`/`hash`/`toString`/`copy`；字段保持 `final`；引用字段按值语义比较。实现由处理器生成，不手写；实现时删除同名手写成员，避免生成冲突；伪代码中的 `equals`/`hash`/`toString`/`copy` 只描述生成物行为，不是手写实现。

## 1. 定位

结果集列元数据：列名、数据库原生类型名、是否可空。

不做：列类型解析、列值读取、列排序、列名唯一性校验、标识符引用。

---

## 2. 设计逻辑

- 只保留三个字段；列值在 `SqlRow`，类型解释由调用方/驱动负责。
- `name` 与 `typeName` 保留驱动返回值，不裁剪、不改大小写；调用方需要规范化时自行处理。
- `isNullable` 是驱动报告的元数据；未知时驱动应报告 `true`，不要把未知当非空。
- 允许重名列：SQL 结果可以出现同名标签；按索引访问行，不按名查找。
- 不可变；无 close；可共享。
- 列名/类型名非空；空字符串是非法元数据，驱动必须给出可诊断名称。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_name` | `String` | final | 列名；非空 |
| `_typeName` | `String` | final | 数据库原生类型名；非空 |
| `_isNullable` | `Bool` | final | 是否可空 |

不变量：`_name`/`_typeName` 非 null 且非空；列名不要求唯一；对象不可变。

---

## 4. 生命周期

构造后不可变；无 close；GC 管理内存；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `SqlColumn(String name, String typeName, Bool isNullable)` | name/typeName/isNullable | name/typeName 非 null 且非空 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `name` | 列名 | 无 | `String` | 无 | 原样返回 |
| `typeName` | 数据库类型名 | 无 | `String` | 无 | 原样返回 |
| `isNullable` | 是否可空 | 无 | `Bool` | 无 | 驱动元数据 |
| `equals` | 值相等 | `SqlColumn other` | `Bool` | null → false | 比较三个字段 |
| `describe` | 单行诊断 | 无 | `String` | 无 | 含列名/类型；不含数据 |

详细契约：

- `name`/`typeName` 返回不可变 String；调用方不能通过返回值修改列对象。
- `equals` 对 null 返回 false；列名、类型名、可空性全部相等才为 true；区分大小写。
- `describe` 形如 `"name:type nullable"` 或 `"name:type not null"`；用于诊断，不用于 SQL 生成。
- 不提供排序；需要稳定顺序时使用 `SqlResult.columns()` 的列表顺序。

---

## 8. 使用的技术

- 不可变值对象；
- 列元数据快照；
- 原样保留驱动类型名；
- 字符串描述。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Bool；
- 运行时：无；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。可被 [`SqlResult`](SqlResult.md) 持有。

---

## 11. 所有权与并发

- 不可变；可共享；无资源；无取消点。
- String 不可变，无需复制；直接返回。
- 相等：`equals` 值比较；`==` 引用身份；不提供哈希，不推荐作 `Map` 键。
- 排序：不提供；列顺序由 `SqlResult.columns()` 决定。

---

## 12. 示例与反例

正确：`column.name()`；`column.typeName()`；`column.isNullable()` 判断是否要处理 NULL。  
反例：假设列名唯一；用 `typeName` 做类型转换；把 `isNullable=false` 当“一定有值”（驱动可能报告不准确）；修改 `SqlResult.columns()` 返回列表期望影响结果。

---

## 13. 测试/场景义务

列名/类型名非空；空名 panic；可空 true/false；重名列；大小写保留；equals；describe 文本；返回列表副本后原列不变；Unicode 列名。

---

## 14. XNull 伪代码

```xnull
@Value
class SqlColumn {
    final String _name
    final String _typeName
    final Bool _isNullable

    SqlColumn(String name, String typeName, Bool isNullable) {
        if name == null || name.length() == 0 {
            throw "SqlColumn: empty name"
        }
        if typeName == null || typeName.length() == 0 {
            throw "SqlColumn: empty typeName"
        }
        _name = name
        _typeName = typeName
        _isNullable = isNullable
    }

    String name() { return _name }
    String typeName() { return _typeName }
    Bool isNullable() { return _isNullable }

    Bool equals(SqlColumn other) {
        if other == null { return false }
        return _name == other.name()
            && _typeName == other.typeName()
            && _isNullable == other.isNullable()
    }

    String describe() {
        String nullability = "not null"
        if _isNullable { nullability = "nullable" }
        return _name + ":" + _typeName + " " + nullability
    }
}
```
