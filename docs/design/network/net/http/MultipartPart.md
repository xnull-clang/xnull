# `MultipartPart`

| 项 | 值 |
| --- | --- |
| 类型 | `class MultipartPart` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | `HttpHeaders`、`HttpBody` |

---

## 1. 定位

multipart 单个 part：表单名、文件名、part 头、body、关闭。

不做：解析边界、写 multipart、流控。

---

## 2. 设计逻辑

- 字段 name/fileName/headers/body；headers 副本。
- `body` 拥有流式内容；`close` 幂等并关闭 body。
- 不可变结构；无全局。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 表单名 |
| `_fileName` | `String?` | 文件名/无 |
| `_headers` | `HttpHeaders` | part 头 |
| `_body` | `HttpBody` | 内容 |

---

## 4. 生命周期

构造；body close；part close 幂等。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `MultipartPart(String name, String? fileName, HttpHeaders headers, HttpBody body)` | 见字段 | name/headers/body 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 名称 | 无 | `String` | 无 |
| `fileName` | 文件名 | 无 | `String?` | 无 |
| `headers` | 头副本 | 无 | `HttpHeaders` | 无 |
| `body` | body | 无 | `HttpBody` | 无 |
| `close` | 关闭 body | 无 | `Result<Unit, Error>` | `Io`（诊断） |

---

## 8. 使用的技术

- part 值对象；
- body 所有权。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Result；
- 运行时：无；
- 接口：`HttpHeaders`、`HttpBody`、`Error`。

---

## 10. 依赖的特性/接口/类

`HttpHeaders`、`HttpBody`、`Error`。

---

## 11. 所有权与并发

引用语义；拥有 body；close 可并发；无全局。

---

## 12. 示例与反例

正确：`part.close()` 释放流。  
反例：多 part 共享 body；close 后读取。

---

## 13. 测试/场景义务

名称/文件名；头副本；body；close 幂等；流式 close。

---

## 14. XNull 伪代码

```xnull
class MultipartPart {
    final String _name
    final String? _fileName
    final HttpHeaders _headers
    final HttpBody _body

    MultipartPart(String name, String? fileName, HttpHeaders headers, HttpBody body) {
        if name == null || headers == null || body == null {
            throw "MultipartPart: null argument"
        }
        _name = name
        _fileName = fileName
        _headers = headers.copy()
        _body = body
    }

    String name() { return _name }
    String? fileName() { return _fileName }
    HttpHeaders headers() { return _headers.copy() }
    HttpBody body() { return _body }
    Result<Unit, Error> close() { return _body.close() }
}
```
