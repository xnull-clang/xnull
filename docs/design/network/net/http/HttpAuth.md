# `HttpAuth`

| 项 | 值 |
| --- | --- |
| 类型 | `class HttpAuth` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | `HttpCredentials`、`Error` |

---

## 1. 定位

HTTP Authorization 工具：Basic/Bearer 头值、解析 Authorization。

不做：挑战处理、令牌刷新、OAuth 流程、加密。

---

## 2. 设计逻辑

- 无状态；构造器私有；全部静态方法。
- `basic` 用 UTF-8 + Base64；`bearer` 校验无 CR/LF。
- `parse` 解析方案与参数；失败 `InvalidArgument`。
- 无 close；可并发。

---

## 3. 表示与不变量

无实例字段。

---

## 4. 生命周期

静态命名空间；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `HttpAuth()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `basic` | Basic 头值 | `String username, String password` | `String` | null/换行 → panic |
| `bearer` | Bearer 头值 | `String token` | `String` | null/换行 → panic |
| `parse` | 解析 Authorization | `String header` | `Result<HttpCredentials, Error>` | `InvalidArgument` |

---

## 8. 使用的技术

- Base64；
- 方案/参数解析。

---

## 9. 需要的支撑

- 语言：class、String、Result；
- 运行时：`base64Encode`、`parseHttpAuthRaw`；
- 接口：`HttpCredentials`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`HttpCredentials`、`Error`、`base64Encode`、`parseHttpAuthRaw`。

---

## 11. 所有权与并发

无状态；无资源；可并发。

---

## 12. 示例与反例

正确：`HttpAuth.basic("user","pass")`。  
反例：把凭据写日志；Bearer 含换行；解析未知方案静默成功。

---

## 13. 测试/场景义务

Basic 编码；Bearer；解析 Basic/Bearer/未知；空参数；CRLF；大小写。

---

## 14. XNull 伪代码

```xnull
class HttpAuth {
    private HttpAuth() {
    }

    static String basic(String username, String password) {
        if username == null || password == null { throw "HttpAuth.basic: null" }
        if username.indexOf("\n") >= 0 || password.indexOf("\n") >= 0 {
            throw "HttpAuth.basic: multiline"
        }
        String encoded = base64Encode(fromUtf8(username + ":" + password))
        return "Basic " + encoded
    }

    static String bearer(String token) {
        if token == null || token == "" { throw "HttpAuth.bearer: empty token" }
        if token.indexOf("\n") >= 0 || token.indexOf("\r") >= 0 {
            throw "HttpAuth.bearer: multiline"
        }
        return "Bearer " + token
    }

    static Result<HttpCredentials, Error> parse(String header) {
        if header == null || header == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "empty authorization"))
        }
        return parseHttpAuthRaw(header)
    }
}
```

> `base64Encode`、`parseHttpAuthRaw` 是运行时 HTTP 认证原语；不是 XDK 公共类型。
