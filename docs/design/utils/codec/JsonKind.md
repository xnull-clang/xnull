# `JsonKind`

| 项 | 值 |
| --- | --- |
| 类型 | `enum JsonKind` |
| 包 | `xdk.codec` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

JSON 值类型标签：Null/Bool/Number/String/Array/Object。

不做：子类型多态、JSON Schema、业务类型。

---

## 2. 设计逻辑

- 简单枚举；`JsonValue.kind()` 返回。
- XNull 类方法静态分派，因此 JSON 用单一 `JsonValue` + kind，不用子类继承。
- 值语义；无 close。

---

## 3. 表示与不变量

| 成员 | 含义 |
| --- | --- |
| `Null` | null |
| `Bool` | 布尔 |
| `Number` | 数字 |
| `String` | 字符串 |
| `Array` | 数组 |
| `Object` | 对象 |

---

## 4. 生命周期

值类型；无 close。

---

## 5. 构造契约

枚举成员直接使用。

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `jsonKindName` | 稳定名 | `JsonKind kind` | `String` | 无 |

---

## 8. 使用的技术

- 简单枚举；
- 名称映射。

---

## 9. 需要的支撑

- 语言：enum、String。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

值语义；无资源。

---

## 12. 示例与反例

正确：`value.kind() == JsonKind.Object`。  
反例：用子类判断类型；把 Number 当 String。

---

## 13. 测试/场景义务

六成员；名称；JsonValue kind。

---

## 14. XNull 伪代码

```xnull
enum JsonKind {
    Null,
    Bool,
    Number,
    String,
    Array,
    Object,
}

String jsonKindName(JsonKind kind) {
    if kind == JsonKind.Null { return "null" }
    if kind == JsonKind.Bool { return "bool" }
    if kind == JsonKind.Number { return "number" }
    if kind == JsonKind.String { return "string" }
    if kind == JsonKind.Array { return "array" }
    return "object"
}
```
