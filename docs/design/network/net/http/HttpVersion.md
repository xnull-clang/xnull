# `HttpVersion`

| 项 | 值 |
| --- | --- |
| 类型 | `enum HttpVersion` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | `Error` |

---

## 1. 定位

HTTP 协议版本：1.0、1.1、2。

不做：HTTP/3/QUIC；需要 QUIC 传输层，后续层。

---

## 2. 设计逻辑

- 简单枚举：`Http10`、`Http11`。
- 文本 `HTTP/1.0`、`HTTP/1.1`；解析/格式化由顶层函数提供。
- 值语义；无 close。

---

## 3. 表示与不变量

| 成员 | 文本 |
| --- | --- |
| `Http10` | HTTP/1.0 |
| `Http11` | HTTP/1.1 |
| `Http2` | HTTP/2 |

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

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `httpVersionName` | 文本 | `HttpVersion version` | `String` | 无 |
| `parseHttpVersion` | 解析 | `String text` | `Result<HttpVersion, Error>` | `InvalidArgument` |

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

正确：`parseHttpVersion("HTTP/1.1")`。  
反例：把 HTTP/2 塞进本枚举；接受 `HTTP/1` 无次版本。

---

## 13. 测试/场景义务

三个成员；大小写；非法文本；名称往返；HTTP/2 解析；HTTP/3 拒绝。

---

## 14. XNull 伪代码

```xnull
enum HttpVersion {
    Http10,
    Http11,
    Http2,
}

String httpVersionName(HttpVersion version) {
    if version == HttpVersion.Http10 { return "HTTP/1.0" }
    if version == HttpVersion.Http11 { return "HTTP/1.1" }
    return "HTTP/2"
}

Result<HttpVersion, Error> parseHttpVersion(String text) {
    if text == null { throw "parseHttpVersion: null" }
    String value = text.toUpper()
    if value == "HTTP/1.0" { return Ok(HttpVersion.Http10) }
    if value == "HTTP/1.1" { return Ok(HttpVersion.Http11) }
    if value == "HTTP/2" || value == "HTTP/2.0" { return Ok(HttpVersion.Http2) }
    return Err(new BasicError(ErrorKind.InvalidArgument, "unsupported version: " + text))
}
```
