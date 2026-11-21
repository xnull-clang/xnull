# `JsonValue`

| 项 | 值 |
| --- | --- |
| 类型 | `class JsonValue` |
| 包 | `xdk.codec` |
| 稳定性 | `preview` |
| 依赖 | `JsonKind`、`JsonNumber`、`JsonObject`、`JsonArray` |

---

## 1. 定位

JSON 值树节点：kind + 对应负载；null/bool/number/string/array/object。

不做：子类多态、对象映射、Schema、流式 SAX。

---

## 2. 设计逻辑

- XNull 类无动态覆盖；单一类 + `JsonKind` 避免子类继承。
- 字段按 kind 可空；工厂校验；不可变包装（对象/数组本身可变）。
- `as*` 失败返回 null；调用方先 `kind`/`is*`。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_kind` | `JsonKind` | 类型 |
| `_bool` | `Bool?` | Bool |
| `_number` | `JsonNumber?` | Number |
| `_string` | `String?` | String |
| `_array` | `JsonArray?` | Array |
| `_object` | `JsonObject?` | Object |

不变量：kind 与负载一致；不可变包装。

---

## 4. 生命周期

不可变包装；无 close。

---

## 5. 构造契约

工厂：`nullValue`、`bool`、`number`、`string`、`array`、`object`；私有构造。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `kind` | 类型 | 无 | `JsonKind` | 无 |
| `isNull`/`isBool`/`isNumber`/`isString`/`isArray`/`isObject` | 判定 | 无 | `Bool` | 无 |
| `asBool`/`asNumber`/`asString`/`asArray`/`asObject` | 读取 | 无 | 对应? | 无 |
| 静态工厂 | 构造 | 值 | `JsonValue` | 非法 → panic |

---

## 8. 使用的技术

- 标签联合；
- 工厂。

---

## 9. 需要的支撑

- 语言：class、Bool、String、Result；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

`JsonKind`、`JsonNumber`、`JsonObject`、`JsonArray`。

---

## 11. 所有权与并发

包装不可变；对象/数组引用可变；无资源。

---

## 12. 示例与反例

正确：`JsonValue.string("x").asString()`。  
反例：不查 kind 就 asObject；期望 JsonValue 深拷贝对象。

---

## 13. 测试/场景义务

六种 kind；as*；工厂；不匹配返回 null。

---

## 14. XNull 伪代码

```xnull
class JsonValue {
    final JsonKind _kind
    final Bool? _bool
    final JsonNumber? _number
    final String? _string
    final JsonArray? _array
    final JsonObject? _object

    private JsonValue(JsonKind kind, Bool? boolValue, JsonNumber? number,
                      String? text, JsonArray? array, JsonObject? object) {
        _kind = kind
        _bool = boolValue
        _number = number
        _string = text
        _array = array
        _object = object
    }

    static JsonValue nullValue() { return new JsonValue(JsonKind.Null, null, null, null, null, null) }
    static JsonValue bool(Bool value) { return new JsonValue(JsonKind.Bool, value, null, null, null, null) }
    static JsonValue number(JsonNumber value) { return new JsonValue(JsonKind.Number, null, value, null, null, null) }
    static JsonValue string(String value) { return new JsonValue(JsonKind.String, null, null, value, null, null) }
    static JsonValue array(JsonArray value) { return new JsonValue(JsonKind.Array, null, null, null, value, null) }
    static JsonValue object(JsonObject value) { return new JsonValue(JsonKind.Object, null, null, null, null, value) }

    JsonKind kind() { return _kind }
    Bool isNull() { return _kind == JsonKind.Null }
    Bool isBool() { return _kind == JsonKind.Bool }
    Bool isNumber() { return _kind == JsonKind.Number }
    Bool isString() { return _kind == JsonKind.String }
    Bool isArray() { return _kind == JsonKind.Array }
    Bool isObject() { return _kind == JsonKind.Object }

    Bool? asBool() { return _bool }
    JsonNumber? asNumber() { return _number }
    String? asString() { return _string }
    JsonArray? asArray() { return _array }
    JsonObject? asObject() { return _object }
}
```
