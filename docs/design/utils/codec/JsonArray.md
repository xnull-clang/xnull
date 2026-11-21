# `JsonArray`

| 项 | 值 |
| --- | --- |
| 类型 | `class JsonArray` |
| 包 | `xdk.codec` |
| 稳定性 | `preview` |
| 依赖 | `JsonValue` |

---

## 1. 定位

可变 JSON 数组：索引读取/追加/删除/长度/快照。

不做：JSON 解析、类型转换、深拷贝。

---

## 2. 设计逻辑

- 字段 `_values: List<JsonValue>`。
- 可变构建期；`copy` 浅拷贝；值元素是 JsonValue 引用。
- 无 close；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_values` | `List<JsonValue>` | 元素 |

---

## 4. 生命周期

可变；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `JsonArray()` | 无 | 空 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `get` | 索引 | `Int` | `JsonValue` | 越界 → panic |
| `add` | 追加 | `JsonValue` | `void` | null → panic |
| `remove` | 删除 | `Int` | `JsonValue` | 越界 → panic |
| `length` | 长度 | 无 | `Int` | 无 |
| `toList` | 快照 | 无 | `List<JsonValue>` | 无 |
| `copy` | 浅拷贝 | 无 | `JsonArray` | 无 |

---

## 8. 使用的技术

- 可变列表；
- 快照。

---

## 9. 需要的支撑

- 语言：class、List、Int；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

`JsonValue`。

---

## 11. 所有权与并发

可变；非线程安全；无资源。

---

## 12. 示例与反例

正确：`array.add(JsonValue.string("x"))`。  
反例：负索引；期望 copy 深拷贝子对象。

---

## 13. 测试/场景义务

get/add/remove；越界；length；toList；copy 独立列表。

---

## 14. XNull 伪代码

```xnull
class JsonArray {
    List<JsonValue> _values = []

    JsonArray() {
    }

    JsonValue get(Int index) { return _values.get(index) }

    void add(JsonValue value) {
        if value == null { throw "JsonArray.add: null" }
        _values.push(value)
    }

    JsonValue remove(Int index) { return _values.remove(index) }
    Int length() { return _values.length() }
    List<JsonValue> toList() { return _values.copy() }

    JsonArray copy() {
        JsonArray result = new JsonArray()
        Int index = 0
        while index < _values.length() {
            result.add(_values.get(index))
            index = index + 1
        }
        return result
    }
}
```
