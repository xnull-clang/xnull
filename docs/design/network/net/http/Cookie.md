# `Cookie`

| 项 | 值 |
| --- | --- |
| 类型 | `class Cookie` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | `SameSite`、`Uri`、`Error` |

---

## 1. 定位

HTTP Cookie：名称/值、域/路径、过期、Secure/HttpOnly、SameSite、请求匹配、Set-Cookie 文本。

不做：CookieJar 存储、PSL、CSRF、加密签名。

---

## 2. 设计逻辑

- 字段 name/value/domain/path/expiresMillis/isSecure/isHttpOnly/sameSite。
- `parseSetCookie` 解析单个 Set-Cookie；`parseCookieHeader` 解析请求 Cookie 头。
- `headerValue` 输出 Set-Cookie（含属性）；请求头由 CookieJar 拼接。
- `matches(Uri)` 检查域/路径/Secure；不实现 PSL。
- 不可变；无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 非空 |
| `_value` | `String` | 可为空 |
| `_domain` | `String` | 空=未设置 |
| `_path` | `String` | 空=未设置 |
| `_expiresMillis` | `Long?` | 会话 null |
| `_isSecure` | `Bool` | Secure |
| `_isHttpOnly` | `Bool` | HttpOnly |
| `_sameSite` | `SameSite?` | 未设置 null |

不变量：name 合法；无 CR/LF；不可变。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Cookie(String name, String value)` | name/value | 非空/单行 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `parseSetCookie` | 解析 Set-Cookie | `String header` | `Result<Cookie, Error>` | `InvalidArgument` |
| `parseCookieHeader` | 解析 Cookie 头 | `String header` | `Result<List<Cookie>, Error>` | `InvalidArgument` |
| `name` | 名称 | 无 | `String` | 无 |
| `value` | 值 | 无 | `String` | 无 |
| `domain` | 域 | 无 | `String` | 无 |
| `path` | 路径 | 无 | `String` | 无 |
| `expiresMillis` | 过期/会话 | 无 | `Long?` | 无 |
| `isSecure` | Secure | 无 | `Bool` | 无 |
| `isHttpOnly` | HttpOnly | 无 | `Bool` | 无 |
| `sameSite` | SameSite/无 | 无 | `SameSite?` | 无 |
| `headerValue` | Set-Cookie 文本 | 无 | `String` | 无 |
| `matches` | 请求匹配 | `Uri requestUri` | `Bool` | 无 |

---

## 8. 使用的技术

- Cookie 解析；
- 域/路径匹配；
- Set-Cookie 格式化。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Long、Result；
- 运行时：`parseSetCookieRaw`、`parseCookieHeaderRaw`、`cookieMatchesRaw`、`formatCookieRaw`；
- 接口：`SameSite`、`Uri`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`SameSite`、`Uri`、`Error`、Cookie 运行时原语。

---

## 11. 所有权与并发

不可变；无资源；可共享。

---

## 12. 示例与反例

正确：`Cookie.parseSetCookie("a=1; Path=/; HttpOnly")`。  
反例：用 Cookie 做认证令牌存储；忽略 Secure；实现 PSL。

---

## 13. 测试/场景义务

Set-Cookie 属性；Cookie 头多对；域/路径/Secure 匹配；过期；空值；非法；headerValue。

---

## 14. XNull 伪代码

```xnull
class Cookie {
    final String _name
    final String _value
    final String _domain
    final String _path
    final Long? _expiresMillis
    final Bool _isSecure
    final Bool _isHttpOnly
    final SameSite? _sameSite

    Cookie(String name, String value) {
        if name == null || name == "" { throw "Cookie: empty name" }
        if value == null { throw "Cookie: null value" }
        if name.indexOf("\n") >= 0 || value.indexOf("\n") >= 0 {
            throw "Cookie: multiline"
        }
        _name = name
        _value = value
        _domain = ""
        _path = ""
        _expiresMillis = null
        _isSecure = false
        _isHttpOnly = false
        _sameSite = null
    }

    private Cookie(String name, String value, String domain, String path,
                   Long? expiresMillis, Bool isSecure, Bool isHttpOnly, SameSite? sameSite) {
        _name = name
        _value = value
        _domain = domain
        _path = path
        _expiresMillis = expiresMillis
        _isSecure = isSecure
        _isHttpOnly = isHttpOnly
        _sameSite = sameSite
    }

    static Result<Cookie, Error> parseSetCookie(String header) {
        if header == null { throw "Cookie.parseSetCookie: null" }
        return parseSetCookieRaw(header)
    }

    static Result<List<Cookie>, Error> parseCookieHeader(String header) {
        if header == null { throw "Cookie.parseCookieHeader: null" }
        return parseCookieHeaderRaw(header)
    }

    String name() { return _name }
    String value() { return _value }
    String domain() { return _domain }
    String path() { return _path }
    Long? expiresMillis() { return _expiresMillis }
    Bool isSecure() { return _isSecure }
    Bool isHttpOnly() { return _isHttpOnly }
    SameSite? sameSite() { return _sameSite }
    String headerValue() { return formatCookieRaw(self) }

    Bool matches(Uri requestUri) {
        if requestUri == null { return false }
        return cookieMatchesRaw(self, requestUri)
    }
}
```

> `parseSetCookieRaw`、`parseCookieHeaderRaw`、`cookieMatchesRaw`、`formatCookieRaw` 是运行时 Cookie 原语；不是 XDK 公共类型。
