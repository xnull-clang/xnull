# `MediaType`

| 项 | 值 |
| --- | --- |
| 类型 | `class MediaType` |
| 包 | `xdk.net.mime` |
| 稳定性 | `preview` |
| 依赖 | `Error` |

---

## 1. 定位

不可变 Media Type：`type/subtype; name=value` 解析、参数读取、派生、常用判断、规范文本。

不做：内容嗅探、编码转换、multipart 解析、完整 IANA 校验。

---

## 2. 设计逻辑

- 字段 `_type`、`_subtype` 小写；`_parameters` 参数名小写、值保留。
- `parse` 调用运行时 token 解析；非法 → `InvalidArgument`。
- `withParameter` 返回新实例；同名参数替换。
- `charset` 是 `charset` 参数的快捷读取。
- `isText` = `text/*`；`isJson` = `application/json` 或 `+json` 后缀；`isFormUrlEncoded`、`isMultipart` 精确匹配。
- 不可变；无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_type` | `String` | 小写主类型 |
| `_subtype` | `String` | 小写子类型 |
| `_parameters` | `Map<String,String>` | 参数 |

不变量：type/subtype 非空；参数名非空；不可变。

---

## 4. 生命周期

解析/派生后不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `MediaType.parse(String text)` | text | 非 null | `InvalidArgument` |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `parse` | 解析 | `String text` | `Result<MediaType, Error>` | `InvalidArgument` |
| `type` | 主类型 | 无 | `String` | 无 |
| `subtype` | 子类型 | 无 | `String` | 无 |
| `parameter` | 参数/无 | `String name` | `String?` | 无 |
| `parameters` | 参数快照 | 无 | `Map<String,String>` | 无 |
| `charset` | charset/无 | 无 | `String?` | 无 |
| `withParameter` | 派生参数 | `String name, String value` | `MediaType` | 非法 → panic |
| `text` | 规范文本 | 无 | `String` | 无 |
| `isText` | text/* | 无 | `Bool` | 无 |
| `isJson` | JSON | 无 | `Bool` | 无 |
| `isFormUrlEncoded` | form | 无 | `Bool` | 无 |
| `isMultipart` | multipart | 无 | `Bool` | 无 |
| `equals` | 值相等 | `MediaType other` | `Bool` | 无 |
| `toString` | 文本 | 无 | `String` | 无 |

---

## 8. 使用的技术

- token/参数解析；
- 小写归一；
- 不可变派生。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Map、Result；
- 运行时：`parseMediaTypeRaw`、`formatMediaTypeRaw`、`MediaTypeRaw`；
- 接口：`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Error`、`BasicError`、`ErrorKind`、MediaType 运行时原语。

---

## 11. 所有权与并发

不可变；参数快照；无资源；可共享。

---

## 12. 示例与反例

正确：`MediaType.parse("text/html; charset=utf-8").charset()` → `"utf-8"`。  
反例：把参数值转小写；用内容嗅探替代显式类型；修改 parameters 期望变化。

---

## 13. 测试/场景义务

基本类型；参数；引号值；大小写；charset；is*；withParameter；非法 token；equals/text。

---

## 14. XNull 伪代码

```xnull
class MediaType {
    final String _type
    final String _subtype
    final Map<String, String> _parameters

    private MediaType(String type, String subtype, Map<String, String> parameters) {
        _type = type
        _subtype = subtype
        _parameters = parameters.copy()
    }

    static Result<MediaType, Error> parse(String text) {
        if text == null { throw "MediaType.parse: null text" }
        Result<MediaTypeRaw, Error> raw = parseMediaTypeRaw(text)
        if raw.isErr() { return Err(raw.error()) }
        MediaTypeRaw value = raw.value()
        return Ok(new MediaType(value.type(), value.subtype(), value.parameters()))
    }

    String type() { return _type }
    String subtype() { return _subtype }

    String? parameter(String name) {
        if name == null { return null }
        String key = name.toLower()
        if !_parameters.has(key) { return null }
        return _parameters.getOr(key, "")
    }

    Map<String, String> parameters() { return _parameters.copy() }

    String? charset() { return self.parameter("charset") }

    MediaType withParameter(String name, String value) {
        if name == null || name == "" { throw "MediaType.withParameter: empty name" }
        if value == null { throw "MediaType.withParameter: null value" }
        Map<String, String> next = _parameters.copy()
        next.put(name.toLower(), value)
        return new MediaType(_type, _subtype, next)
    }

    String text() { return formatMediaTypeRaw(_type, _subtype, _parameters) }

    Bool isText() { return _type == "text" }

    Bool isJson() {
        if _type == "application" && _subtype == "json" { return true }
        return _subtype.endsWith("+json")
    }

    Bool isFormUrlEncoded() {
        return _type == "application" && _subtype == "x-www-form-urlencoded"
    }

    Bool isMultipart() { return _type == "multipart" }

    Bool equals(MediaType other) {
        if other == null { return false }
        return self.text() == other.text()
    }

    String toString() { return self.text() }
}
```

> `MediaTypeRaw`、`parseMediaTypeRaw`、`formatMediaTypeRaw` 是运行时 MIME 原语；不是 XDK 公共类型。
