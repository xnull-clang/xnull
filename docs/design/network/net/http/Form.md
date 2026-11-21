# `Form`

| 项 | 值 |
| --- | --- |
| 类型 | `class Form` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | `FormEntry`、`HttpBody`、`Error` |

---

## 1. 定位

`application/x-www-form-urlencoded` 表单：解析、增删改、读取、编码、转 body。

不做：multipart、文件上传、自动 Content-Type 头。

---

## 2. 设计逻辑

- 字段 `_entries: List<FormEntry>`；保留顺序/重复键。
- `set` 删除同名后追加；`add` 追加；`getOrNull` 首个。
- `parse` 按 `&` 切分，首个 `=`，query decode；空段跳过。
- `encode` 使用 `queryEncode`；`toBody` 返回文本 body，不设置头。
- 可变；非线程安全；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_entries` | `List<FormEntry>` | 条目 |

不变量：name 非空；允许重复。

---

## 4. 生命周期

可变；无 close；`copy` 独立。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Form()` | 无 | 空表单 | 无 |
| `Form.parse(String text)` | text | 非 null | `DataCorrupted` |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `parse` | 解析 | `String text` | `Result<Form, Error>` | `DataCorrupted` |
| `add` | 追加 | `String name, String value` | `void` | 空/null → panic |
| `set` | 替换同名 | `String name, String value` | `void` | 空/null → panic |
| `getOrNull` | 首个值/无 | `String name` | `String?` | 无 |
| `getOr` | 首个值/兜底 | `String name, String fallback` | `String` | null fallback → panic |
| `getAll` | 全部值 | `String name` | `List<String>` | 无 |
| `remove` | 删除同名 | `String name` | `Bool` | 无 |
| `entries` | 快照 | 无 | `List<FormEntry>` | 无 |
| `length` | 条目数 | 无 | `Int` | 无 |
| `encode` | URL 编码 | 无 | `String` | 无 |
| `toBody` | 转 body | 无 | `HttpBody` | 无 |
| `clear` | 清空 | 无 | `void` | 无 |
| `copy` | 独立副本 | 无 | `Form` | 无 |

---

## 8. 使用的技术

- 键值列表；
- URL 编码/解码；
- 表单 body。

---

## 9. 需要的支撑

- 语言：class、List、String、Bool、Result；
- 运行时：`queryDecode`、`queryEncode`、`HttpBody.fromText`；
- 接口：`FormEntry`、`HttpBody`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`FormEntry`、`HttpBody`、`Error`、`queryDecode`、`queryEncode`。

---

## 11. 所有权与并发

可变；非线程安全；无资源；`copy` 独立。

---

## 12. 示例与反例

正确：`Form.parse("a=1&a=2").getAll("a")`。  
反例：空名；把空串当缺失；`set` 保留原位置。

---

## 13. 测试/场景义务

空表单；重复键；空值；无 `=`；非法 `%`；set/remove；编码往返；toBody；copy。

---

## 14. XNull 伪代码

```xnull
class Form {
    List<FormEntry> _entries = []

    Form() {
    }

    static Result<Form, Error> parse(String text) {
        if text == null { throw "Form.parse: null" }
        Form result = new Form()
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
        _entries.push(new FormEntry(name, value))
    }

    void set(String name, String value) {
        self.remove(name)
        self.add(name, value)
    }

    String? getOrNull(String name) {
        if name == null { return null }
        Int index = 0
        while index < _entries.length() {
            if _entries.get(index).name() == name {
                return _entries.get(index).value()
            }
            index = index + 1
        }
        return null
    }

    String getOr(String name, String fallback) {
        if fallback == null { throw "Form.getOr: null fallback" }
        String? value = self.getOrNull(name)
        if value == null { return fallback }
        return value as String
    }

    List<String> getAll(String name) {
        List<String> result = []
        Int index = 0
        while index < _entries.length() {
            if _entries.get(index).name() == name {
                result.push(_entries.get(index).value())
            }
            index = index + 1
        }
        return result
    }

    Bool remove(String name) {
        Bool removed = false
        Int index = _entries.length() - 1
        while index >= 0 {
            if _entries.get(index).name() == name {
                _entries.remove(index)
                removed = true
            }
            index = index - 1
        }
        return removed
    }

    List<FormEntry> entries() { return _entries.copy() }
    Int length() { return _entries.length() }

    String encode() {
        String result = ""
        Int index = 0
        while index < _entries.length() {
            if index > 0 { result = result + "&" }
            FormEntry entry = _entries.get(index)
            result = result + queryEncode(entry.name()) + "=" + queryEncode(entry.value())
            index = index + 1
        }
        return result
    }

    HttpBody toBody() { return HttpBody.fromText(self.encode()) }

    void clear() { _entries.clear() }

    Form copy() {
        Form result = new Form()
        Int index = 0
        while index < _entries.length() {
            result.add(_entries.get(index).name(), _entries.get(index).value())
            index = index + 1
        }
        return result
    }
}
```
