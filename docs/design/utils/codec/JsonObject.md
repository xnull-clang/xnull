# `JsonObject`

| 项 | 值 |
| --- | --- |
| 类型 | `class JsonObject` |
| 包 | `xdk.codec` |
| 稳定性 | `preview` |
| 依赖 | `JsonValue` |

---

## 1. 定位

有序可变 JSON 对象：键值读取/设置/删除/键值快照。

不做：JSON 解析、Schema、深层合并。

---

## 2. 设计逻辑

- 字段 `_values: Map<String,JsonValue>`、`_order: List<String>`。
- 键大小写敏感；`set` 新键追加顺序，已有键原位替换。
- `getOrNull` 缺失 null；`remove` 删除并清顺序。
- 可变；非线程安全；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_values` | `Map<String,JsonValue>` | 键值 |
| `_order` | `List<String>` | 插入顺序 |

不变量：order 与 values 键一致。

---

## 4. 生命周期

可变；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `JsonObject()` | 无 | 空 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `getOrNull` | 值/无 | `String name` | `JsonValue?` | 无 |
| `getOr` | 值/兜底 | `String name, JsonValue fallback` | `JsonValue` | null fallback → panic |
| `has` | 是否存在 | `String name` | `Bool` | 无 |
| `set` | 设置 | `String name, JsonValue value` | `void` | null → panic |
| `remove` | 删除 | `String name` | `Bool` | 无 |
| `keys` | 键快照 | 无 | `List<String>` | 无 |
| `values` | 值快照 | 无 | `List<JsonValue>` | 无 |
| `length` | 键数 | 无 | `Int` | 无 |
| `copy` | 浅拷贝 | 无 | `JsonObject` | 无 |

---

## 8. 使用的技术

- 有序 Map；
- 快照。

---

## 9. 需要的支撑

- 语言：class、Map、List、String、Bool、Int；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

`JsonValue`。

---

## 11. 所有权与并发

可变；非线程安全；无资源；copy 浅拷贝。

---

## 12. 示例与反例

正确：`object.set("id", JsonValue.string("a"))`。  
反例：空键；期望 copy 深拷贝；修改 keys 快照。

---

## 13. 测试/场景义务

set/替换顺序；getOrNull/getOr；remove；keys/values；length；copy。

---

## 14. XNull 伪代码

```xnull
class JsonObject {
    Map<String, JsonValue> _values = [:]
    List<String> _order = []

    JsonObject() {
    }

    JsonValue? getOrNull(String name) {
        if name == null || !_values.has(name) { return null }
        return _values.getOr(name, null)
    }

    JsonValue getOr(String name, JsonValue fallback) {
        if fallback == null { throw "JsonObject.getOr: null fallback" }
        JsonValue? value = self.getOrNull(name)
        if value == null { return fallback }
        return value as JsonValue
    }

    Bool has(String name) {
        if name == null { return false }
        return _values.has(name)
    }

    void set(String name, JsonValue value) {
        if name == null || name == "" { throw "JsonObject.set: empty name" }
        if value == null { throw "JsonObject.set: null value" }
        if !_values.has(name) { _order.push(name) }
        _values.put(name, value)
    }

    Bool remove(String name) {
        if name == null || !_values.has(name) { return false }
        _values.remove(name)
        _order.remove(_order.indexOf(name))
        return true
    }

    List<String> keys() { return _order.copy() }

    List<JsonValue> values() {
        List<JsonValue> result = []
        Int index = 0
        while index < _order.length() {
            result.push(_values.getOr(_order.get(index), JsonValue.nullValue()))
            index = index + 1
        }
        return result
    }

    Int length() { return _order.length() }

    JsonObject copy() {
        JsonObject result = new JsonObject()
        Int index = 0
        while index < _order.length() {
            String key = _order.get(index)
            result.set(key, _values.getOr(key, JsonValue.nullValue()))
            index = index + 1
        }
        return result
    }
}
```
