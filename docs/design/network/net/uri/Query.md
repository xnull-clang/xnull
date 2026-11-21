# `Query`

| 项 | 值 |
| --- | --- |
| 类型 | `class Query` |
| 包 | `xdk.net.uri` |
| 稳定性 | `preview` |
| 依赖 | `Error`、`queryDecode`、`queryEncode` |

---

## 1. 定位

可变查询串构造器：解析 `a=1&b=2`、增删改、按名读取、编码。

不做：URI 解析、表单 multipart、HTTP 头、URL 抓取、键排序。

---

## 2. 设计逻辑

- 两个平行列表 `_names`/`_values` 保持顺序和重复键。
- `add` 追加；`set` 删除同名全部后追加一个；`remove` 删除全部同名。
- `getOrNull` 返回首个值；`getAll` 返回全部；缺失用 null，不用空串哨兵。
- `parse` 按 `&` 切分，跳过空段；首个 `=` 分隔；无 `=` 的值按空串。
- 键值用 `queryDecode` 解码；`+` 当空格；非法编码/UTF-8 → `DataCorrupted`。
- `encode` 使用 `queryEncode`，保留顺序；空 Query 编码为空串。
- 可变；非线程安全；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_names` | `List<String>` | 键，按插入顺序 |
| `_values` | `List<String>` | 值，与 names 等长 |

不变量：names.length == values.length；键非空；允许重复键。

---

## 4. 生命周期

构造/解析后可变；无 close；`copy` 独立；非线程安全。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Query()` | 无 | 空查询 | 无 |
| `Query.parse(String text)` | text | 非 null | 非法 → `DataCorrupted` |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `parse` | 解析查询串 | `String text` | `Result<Query, Error>` | `DataCorrupted` |
| `add` | 追加键值 | `String name, String value` | `void` | 空/null → panic |
| `set` | 替换同名 | `String name, String value` | `void` | 空/null → panic |
| `getOrNull` | 首个值/缺失 | `String name` | `String?` | 无 |
| `getOr` | 首个值/兜底 | `String name, String fallback` | `String` | null fallback → panic |
| `getAll` | 全部值 | `String name` | `List<String>` | 无 |
| `has` | 是否存在 | `String name` | `Bool` | 无 |
| `remove` | 删除同名 | `String name` | `Bool` | 无 |
| `length` | 键值对数 | 无 | `Int` | 无 |
| `names` | 键快照 | 无 | `List<String>` | 无 |
| `values` | 值快照 | 无 | `List<String>` | 无 |
| `encode` | 编码查询串 | 无 | `String` | 无 |
| `clear` | 清空 | 无 | `void` | 无 |
| `copy` | 独立副本 | 无 | `Query` | 无 |
| `toString` | 编码文本 | 无 | `String` | 无 |

说明：

- `set` 删除所有同名键后追加，位置移到末尾。
- `remove` 至少删除一个才返回 true。
- `getOrNull` 不区分“缺失”和“值为空串”；空串是合法值。
- `names`/`values` 返回副本，索引一一对应。

---

## 8. 使用的技术

- 平行列表；
- 首 `=` 分隔；
- 百分号/查询解码；
- 插入顺序。

---

## 9. 需要的支撑

- 语言：class、List、String、Bool、Int、Result；
- 运行时：`split`、`queryDecode`、`queryEncode`；
- 接口：`Error`、`DataCorrupted`。

---

## 10. 依赖的特性/接口/类

`Error`、`queryDecode`、`queryEncode`、`split`。

---

## 11. 所有权与并发

可变；非线程安全；`copy` 独立；无资源。

---

## 12. 示例与反例

正确：`Query.parse("a=1&a=2").getAll("a")` → 两个值。  
反例：用空串表示缺失；期望 `set` 保留原位置；把 `+` 当字面加号；并发修改同一 Query。

---

## 13. 测试/场景义务

空串；单/多键；重复键；空值；无 `=`；`+`；非法 `%`；`set/remove`；编码往返；copy 独立性。

---

## 14. XNull 伪代码

```xnull
class Query {
    List<String> _names = []
    List<String> _values = []

    Query() {
    }

    static Result<Query, Error> parse(String text) {
        if text == null { throw "Query.parse: null text" }
        Query result = new Query()
        if text == "" { return Ok(result) }
        List<String> parts = split(text, "&")
        Int index = 0
        while index < parts.length() {
            String part = parts.get(index)
            if part != "" {
                Int separator = part.indexOf("=")
                String rawName = part
                String rawValue = ""
                if separator >= 0 {
                    rawName = part.substring(0, separator)
                    rawValue = part.substring(separator + 1, part.length() - separator - 1)
                }
                Result<String, Error> name = queryDecode(rawName)
                if name.isErr() { return Err(name.error()) }
                Result<String, Error> value = queryDecode(rawValue)
                if value.isErr() { return Err(value.error()) }
                result.add(name.value(), value.value())
            }
            index = index + 1
        }
        return Ok(result)
    }

    void add(String name, String value) {
        if name == null || name == "" { throw "Query.add: empty name" }
        if value == null { throw "Query.add: null value" }
        _names.push(name)
        _values.push(value)
    }

    void set(String name, String value) {
        if name == null || name == "" { throw "Query.set: empty name" }
        if value == null { throw "Query.set: null value" }
        self.remove(name)
        self.add(name, value)
    }

    String? getOrNull(String name) {
        Int index = 0
        while index < _names.length() {
            if _names.get(index) == name {
                return _values.get(index)
            }
            index = index + 1
        }
        return null
    }

    String getOr(String name, String fallback) {
        if fallback == null { throw "Query.getOr: null fallback" }
        String? value = self.getOrNull(name)
        if value == null { return fallback }
        return value as String
    }

    List<String> getAll(String name) {
        List<String> result = []
        Int index = 0
        while index < _names.length() {
            if _names.get(index) == name {
                result.push(_values.get(index))
            }
            index = index + 1
        }
        return result
    }

    Bool has(String name) {
        return self.getOrNull(name) != null
    }

    Bool remove(String name) {
        Bool removed = false
        Int index = _names.length() - 1
        while index >= 0 {
            if _names.get(index) == name {
                _names.remove(index)
                _values.remove(index)
                removed = true
            }
            index = index - 1
        }
        return removed
    }

    Int length() { return _names.length() }
    List<String> names() { return _names.copy() }
    List<String> values() { return _values.copy() }

    String encode() {
        String result = ""
        Int index = 0
        while index < _names.length() {
            if index > 0 { result = result + "&" }
            result = result + queryEncode(_names.get(index)) + "=" + queryEncode(_values.get(index))
            index = index + 1
        }
        return result
    }

    void clear() {
        _names.clear()
        _values.clear()
    }

    Query copy() {
        Query result = new Query()
        Int index = 0
        while index < _names.length() {
            result.add(_names.get(index), _values.get(index))
            index = index + 1
        }
        return result
    }

    String toString() { return self.encode() }
}
```
