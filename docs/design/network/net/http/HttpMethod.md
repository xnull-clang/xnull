# `HttpMethod`

| 项 | 值 |
| --- | --- |
| 类型 | `enum HttpMethod` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | `Error` |

---

## 1. 定位

HTTP 请求方法：GET/POST/PUT/DELETE/PATCH/HEAD/OPTIONS/TRACE/CONNECT。

不做：自定义方法（X）、方法语义执行、路由。

---

## 2. 设计逻辑

- 简单枚举；固定成员。
- 文本解析/格式化由顶层函数完成；枚举无实例方法。
- 值语义；无 close；可共享。

---

## 3. 表示与不变量

| 成员 | 文本 |
| --- | --- |
| `Get` | GET |
| `Post` | POST |
| `Put` | PUT |
| `Delete` | DELETE |
| `Patch` | PATCH |
| `Head` | HEAD |
| `Options` | OPTIONS |
| `Trace` | TRACE |
| `Connect` | CONNECT |

---

## 4. 生命周期

值类型；无 close。

---

## 5. 构造契约

枚举成员直接使用。

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

顶层函数：

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `httpMethodName` | 文本 | `HttpMethod method` | `String` | 无 |
| `parseHttpMethod` | 解析 | `String text` | `Result<HttpMethod, Error>` | `InvalidArgument` |

---

## 8. 使用的技术

- 简单枚举；
- 文本映射。

---

## 9. 需要的支撑

- 语言：enum、String、Result；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

值语义；无资源；可共享。

---

## 12. 示例与反例

正确：`parseHttpMethod("POST")`。  
反例：小写方法当非法（解析大小写不敏感）；把 CONNECT 当普通请求。

---

## 13. 测试/场景义务

9 个成员；大小写解析；未知方法；名称往返。

---

## 14. XNull 伪代码

```xnull
enum HttpMethod {
    Get,
    Post,
    Put,
    Delete,
    Patch,
    Head,
    Options,
    Trace,
    Connect,
}

String httpMethodName(HttpMethod method) {
    if method == HttpMethod.Get { return "GET" }
    if method == HttpMethod.Post { return "POST" }
    if method == HttpMethod.Put { return "PUT" }
    if method == HttpMethod.Delete { return "DELETE" }
    if method == HttpMethod.Patch { return "PATCH" }
    if method == HttpMethod.Head { return "HEAD" }
    if method == HttpMethod.Options { return "OPTIONS" }
    if method == HttpMethod.Trace { return "TRACE" }
    return "CONNECT"
}

Result<HttpMethod, Error> parseHttpMethod(String text) {
    if text == null { throw "parseHttpMethod: null" }
    String value = text.toUpper()
    if value == "GET" { return Ok(HttpMethod.Get) }
    if value == "POST" { return Ok(HttpMethod.Post) }
    if value == "PUT" { return Ok(HttpMethod.Put) }
    if value == "DELETE" { return Ok(HttpMethod.Delete) }
    if value == "PATCH" { return Ok(HttpMethod.Patch) }
    if value == "HEAD" { return Ok(HttpMethod.Head) }
    if value == "OPTIONS" { return Ok(HttpMethod.Options) }
    if value == "TRACE" { return Ok(HttpMethod.Trace) }
    if value == "CONNECT" { return Ok(HttpMethod.Connect) }
    return Err(new BasicError(ErrorKind.InvalidArgument, "unknown method: " + text))
}
```
