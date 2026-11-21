# `AuthScheme`

| 项 | 值 |
| --- | --- |
| 类型 | `enum AuthScheme` |
| 包 | `xdk.api` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

认证方案枚举：HTTP Basic、HTTP Bearer、API key header/query/cookie；以及对应的 OpenAPI 映射与挑战头生成。

不做：OAuth2、OIDC、mTLS、Digest、NTLM、令牌签发、凭据存储。

---

## 2. 设计逻辑

- 简单枚举；固定 5 个成员。
- Basic/Bearer 属于 HTTP Authentication，凭据在 `Authorization` 头。
- API key 三种位置对应 OpenAPI `apiKey` 的 `in: header|query|cookie`。
- 名称/映射/挑战由顶层函数提供，枚举无实例方法。
- 挑战头只对 Basic/Bearer 生成；API key 无标准挑战。
- 值语义；无 close；可共享。

---

## 3. 表示与不变量

| 成员 | 含义 | 凭据位置 | OpenAPI 映射 | 挑战头 |
| --- | --- | --- | --- | --- |
| `Basic` | HTTP Basic（RFC 7617） | `Authorization: Basic ...` | `type: http`, `scheme: basic` | `Basic realm="..."` |
| `Bearer` | HTTP Bearer（RFC 6750） | `Authorization: Bearer ...` | `type: http`, `scheme: bearer` | `Bearer` |
| `ApiKeyHeader` | API key 头 | 自定义头 | `type: apiKey`, `in: header` | 无 |
| `ApiKeyQuery` | API key 查询参数 | 查询串 | `type: apiKey`, `in: query` | 无 |
| `ApiKeyCookie` | API key Cookie | Cookie | `type: apiKey`, `in: cookie` | 无 |

不变量：成员固定；名称小写稳定；映射稳定。

---

## 4. 生命周期

值类型；无 close；可共享。

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
| `authSchemeName` | 稳定小写名 | `AuthScheme scheme` | `String` | 无 |
| `authSchemeOpenApiType` | OpenAPI type | `AuthScheme scheme` | `String` | 无 |
| `authSchemeOpenApiLocation` | OpenAPI in | `AuthScheme scheme` | `String` | 无 |
| `authSchemeChallenge` | 挑战头值 | `AuthScheme scheme, String realm` | `String` | 非法 realm → panic |

说明：

- `authSchemeName` 返回 `basic`/`bearer`/`api-key-header`/`api-key-query`/`api-key-cookie`。
- `authSchemeOpenApiType` 返回 `http`（Basic/Bearer）或 `apiKey`（三种 API key）。
- `authSchemeOpenApiLocation` 对 Basic/Bearer 返回 `header`；API key 返回 `header`/`query`/`cookie`。
- `authSchemeChallenge`：Basic 空 realm 返回 `Basic`，非空返回 `Basic realm="..."`；Bearer 返回 `Bearer`；API key 返回空串。
- realm 中的 `"`、`\`、CR/LF 是合同错误。

---

## 8. 使用的技术

- 简单枚举；
- 名称/映射表；
- 挑战头格式化；
- RFC 7617/6750 语义。

---

## 9. 需要的支撑

- 语言：enum、String、Bool；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

值语义；无资源；可共享；无取消点。

---

## 12. 示例与反例

正确：

```text
if authenticator.scheme() == AuthScheme.Bearer {
    response.setHeader("WWW-Authenticate", "Bearer")
}
String name = authSchemeName(AuthScheme.ApiKeyHeader)
```

反例：

- 把 API key 当 HTTP Bearer；
- Basic realm 含引号/反斜杠；
- 给 API key 生成 `WWW-Authenticate`；
- 期望枚举携带参数名（由 `Authenticator.parameterName` 提供）；
- 增加 OAuth2 成员但不实现流程。

---

## 13. 测试/场景义务

5 个成员；名称；OpenAPI type/location；Basic 空/非空 realm；Bearer；API key 空挑战；非法 realm 字符；往返映射。

---

## 14. XNull 伪代码

> 非可执行设计伪代码。

```xnull
enum AuthScheme {
    Basic,
    Bearer,
    ApiKeyHeader,
    ApiKeyQuery,
    ApiKeyCookie,
}

String authSchemeName(AuthScheme scheme) {
    if scheme == AuthScheme.Basic { return "basic" }
    if scheme == AuthScheme.Bearer { return "bearer" }
    if scheme == AuthScheme.ApiKeyHeader { return "api-key-header" }
    if scheme == AuthScheme.ApiKeyQuery { return "api-key-query" }
    return "api-key-cookie"
}

String authSchemeOpenApiType(AuthScheme scheme) {
    if scheme == AuthScheme.Basic || scheme == AuthScheme.Bearer {
        return "http"
    }
    return "apiKey"
}

String authSchemeOpenApiLocation(AuthScheme scheme) {
    if scheme == AuthScheme.ApiKeyQuery { return "query" }
    if scheme == AuthScheme.ApiKeyCookie { return "cookie" }
    return "header"
}

String authSchemeChallenge(AuthScheme scheme, String realm) {
    if realm == null { throw "authSchemeChallenge: null realm" }
    if realm.indexOf("\"") >= 0 || realm.indexOf("\\") >= 0
        || realm.indexOf("\n") >= 0 || realm.indexOf("\r") >= 0 {
        throw "authSchemeChallenge: invalid realm"
    }
    if scheme == AuthScheme.Basic {
        if realm == "" { return "Basic" }
        return "Basic realm=\"" + realm + "\""
    }
    if scheme == AuthScheme.Bearer { return "Bearer" }
    return ""
}
```
