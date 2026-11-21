# `HttpHeaders`

| 项 | 值 |
| --- | --- |
| 类型 | `class HttpHeaders` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | `HttpHeader`、`MediaType` |

---

## 1. 定位

HTTP 头集合：大小写不敏感、多值、插入顺序、常用类型/长度/UA 快捷读取。

不做：连接级头策略、代理头、Cookie 解析、序列化。

---

## 2. 设计逻辑

- 字段 `_values: Map<String,List<String>>`（键小写）、`_order: List<String>`（首次插入顺序）。
- `add` 追加；`set` 替换；`getOrNull` 首个；`getAll` 全部快照。
- `entries` 按首次出现顺序展开每条值。
- `contentType` 解析失败返回 null；`contentLength` 解析失败返回 null。
- 可变构建期；发送后调用方不得修改；无 close；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_values` | `Map<String,List<String>>` | 小写名 → 值列表 |
| `_order` | `List<String>` | 首次出现顺序 |

不变量：order 与 values 键一致；值列表非空；名称小写。

---

## 4. 生命周期

可变；无 close；`copy` 独立；非线程安全。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `HttpHeaders()` | 无 | 空集合 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `add` | 追加值 | `String name, String value` | `void` | 非法 → panic |
| `set` | 替换值 | `String name, String value` | `void` | 非法 → panic |
| `getOrNull` | 首个值/无 | `String name` | `String?` | 无 |
| `getOr` | 首个值/兜底 | `String name, String fallback` | `String` | null fallback → panic |
| `getAll` | 全部值 | `String name` | `List<String>` | 无 |
| `has` | 是否存在 | `String name` | `Bool` | 无 |
| `remove` | 删除 | `String name` | `void` | 无 |
| `entries` | 头快照 | 无 | `List<HttpHeader>` | 无 |
| `length` | 头数量 | 无 | `Int` | 无 |
| `clear` | 清空 | 无 | `void` | 无 |
| `copy` | 深拷贝 | 无 | `HttpHeaders` | 无 |
| `contentType` | Content-Type | 无 | `MediaType?` | 无 |
| `contentLength` | Content-Length | 无 | `Long?` | 无 |
| `userAgent` | User-Agent | 无 | `String?` | 无 |

---

## 8. 使用的技术

- 小写键 Map；
- 多值列表；
- 插入顺序。

---

## 9. 需要的支撑

- 语言：class、Map、List、String、Bool、Long；
- 运行时：`parseLong`、`MediaType.parse`；
- 接口：`HttpHeader`、`MediaType`。

---

## 10. 依赖的特性/接口/类

`HttpHeader`、`MediaType`、`parseLong`。

---

## 11. 所有权与并发

可变；非线程安全；`entries`/`getAll` 快照；无资源。

---

## 12. 示例与反例

正确：`headers.add("Accept","text/plain"); headers.getAll("accept")`。  
反例：用原名当 Map 键；`get` 缺失返回空串；发送后修改头。

---

## 13. 测试/场景义务

大小写；多值；顺序；add/set/remove/clear；copy 独立；contentType/length/UA；非法名称。

---

## 14. XNull 伪代码

```xnull
class HttpHeaders {
    Map<String, List<String>> _values = [:]
    List<String> _order = []

    HttpHeaders() {
    }

    void add(String name, String value) {
        HttpHeader header = new HttpHeader(name, value)
        String key = header.name().toLower()
        if !_values.has(key) {
            _values.put(key, [])
            _order.push(key)
        }
        List<String> values = _values.getOr(key, [])
        values.push(header.value())
    }

    void set(String name, String value) {
        HttpHeader header = new HttpHeader(name, value)
        String key = header.name().toLower()
        if !_values.has(key) { _order.push(key) }
        _values.put(key, [header.value()])
    }

    String? getOrNull(String name) {
        if name == null { return null }
        String key = name.toLower()
        if !_values.has(key) { return null }
        List<String> values = _values.getOr(key, [])
        if values.length() == 0 { return null }
        return values.get(0)
    }

    String getOr(String name, String fallback) {
        if fallback == null { throw "HttpHeaders.getOr: null fallback" }
        String? value = self.getOrNull(name)
        if value == null { return fallback }
        return value as String
    }

    List<String> getAll(String name) {
        if name == null { return [] }
        String key = name.toLower()
        if !_values.has(key) { return [] }
        return _values.getOr(key, []).copy()
    }

    Bool has(String name) {
        if name == null { return false }
        return _values.has(name.toLower())
    }

    void remove(String name) {
        if name == null { return }
        String key = name.toLower()
        if _values.has(key) {
            _values.remove(key)
            _order.remove(_order.indexOf(key))
        }
    }

    List<HttpHeader> entries() {
        List<HttpHeader> result = []
        Int index = 0
        while index < _order.length() {
            String key = _order.get(index)
            List<String> values = _values.getOr(key, [])
            Int valueIndex = 0
            while valueIndex < values.length() {
                result.push(new HttpHeader(key, values.get(valueIndex)))
                valueIndex = valueIndex + 1
            }
            index = index + 1
        }
        return result
    }

    Int length() { return _order.length() }

    void clear() {
        _values.clear()
        _order.clear()
    }

    HttpHeaders copy() {
        HttpHeaders result = new HttpHeaders()
        List<HttpHeader> all = self.entries()
        Int index = 0
        while index < all.length() {
            result.add(all.get(index).name(), all.get(index).value())
            index = index + 1
        }
        return result
    }

    MediaType? contentType() {
        String? value = self.getOrNull("content-type")
        if value == null { return null }
        Result<MediaType, Error> parsed = MediaType.parse(value as String)
        if parsed.isErr() { return null }
        return parsed.value()
    }

    Long? contentLength() {
        String? value = self.getOrNull("content-length")
        if value == null { return null }
        Result<Long, Error> parsed = parseLong(value as String)
        if parsed.isErr() { return null }
        return parsed.value()
    }

    String? userAgent() { return self.getOrNull("user-agent") }
}
```
