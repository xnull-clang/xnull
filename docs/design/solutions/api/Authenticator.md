# `Authenticator`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol Authenticator` |
| 包 | `xdk.api` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`ApiContext`、`AuthScheme`、`Error` |

---

## 1. 定位

认证协议：声明认证方案、OpenAPI 方案名、凭据参数名、realm，并验证一次请求的凭据；成功后把主体、角色、属性写入 `ApiContext`。

不做：登录、注册、令牌签发/刷新、Session、用户库、OAuth2/OIDC 流程、密码哈希算法、身份提供方。

---

## 2. 设计逻辑

- `scheme()` 固定认证类别：Basic/Bearer/API key 位置。
- `name()` 是 OpenAPI `components.securitySchemes` 的键，必须非空且在应用内唯一。
- `parameterName()` 是凭据参数名：HTTP 认证为 `Authorization`；API key 为实际 header/query/cookie 名。
- `realm()` 用于 Basic 挑战；可为空；不得含引号、反斜杠、CR/LF。
- `authenticate` 读取凭据并验证；成功时调用 `exchange.setPrincipal(name)`，可选 `setRoles`/`setAttribute`。
- 认证失败返回 `Err`，不得自行写响应；`ApiServer` 统一映射 401/403/500/503/504。
- `PermissionDenied` → 403；`Unavailable`/`Busy` → 503；`Timeout` → 504；后端 IO/数据/内部错误 → 500；`Cancelled` → 原样返回且不响应；凭据缺失/非法 → 401。
- 401 时 `ApiServer` 根据 `scheme()`/`realm()` 生成 `WWW-Authenticate`；API key 无标准挑战头。
- 认证器可被并发调用；共享状态必须线程安全。
- 不做身份提供方；凭据来源、用户库、令牌校验由实现注入。

---

## 3. 表示与不变量

协议无字段。实现必须保证：

- `scheme()`/`name()`/`parameterName()` 在生命周期内稳定；
- `name()` 非空且唯一；
- `parameterName()` 非空；
- `realm()` 非 null 且无控制字符；
- 成功认证只设置一次 principal；
- 不把密码/令牌写入日志、错误消息、响应头；
- 比较凭据使用常量时间；
- 不响应、不关闭 `ApiContext`。

---

## 4. 生命周期

协议无构造；实现通常长期存活；无 close；认证器实例由应用持有并注入 `ApiOptions`/`ApiRoute`。

---

## 5. 构造契约

协议无构造。

---

## 6. 字段表

无协议字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `scheme` | 认证类别 | 无 | `AuthScheme` | 无 |
| `name` | OpenAPI 方案名 | 无 | `String` | 无 |
| `parameterName` | 凭据参数名 | 无 | `String` | 无 |
| `realm` | 认证域 | 无 | `String` | 无 |
| `authenticate` | 验证凭据 | `Context context, ApiContext exchange` | `Result<Unit, Error>` | `PermissionDenied`/`Unavailable`/`Cancelled`/其他 |

说明：

- `authenticate` 必须检查 `context.isCancelled()`；取消返回 `Cancelled`。
- 缺少凭据/格式错误返回 `InvalidArgument`（服务器映射 401），不要返回 `NotFound` 以免泄露。
- 凭据正确但无权限返回 `PermissionDenied`（403）。
- 后端不可用返回 `Unavailable`/`Busy`（503）。
- 成功后 `exchange.isAuthenticated()` 必须为 true。
- 同一请求重复调用 `authenticate` 不应发生；实现不必支持重入。

---

## 8. 使用的技术

- 非泛型协议；
- 凭据解析；
- 常量时间比较；
- 上下文写入；
- Result；
- 挑战头生成（由服务器完成）。

---

## 9. 需要的支撑

- 语言：protocol、String、Result；
- 运行时：常量时间比较原语（实现使用）；
- 接口：`Context`、`ApiContext`、`AuthScheme`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Context`、`ApiContext`、`AuthScheme`、`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

协议引用；实现可被并发请求调用；`ApiContext` 只在当前请求内有效；不得保存请求级凭据；无资源；无取消回调。

---

## 12. 示例与反例

正确：

```text
class BearerAuthenticator implements Authenticator {
    AuthScheme scheme() { return AuthScheme.Bearer }
    String name() { return "bearerAuth" }
    String parameterName() { return "Authorization" }
    String realm() { return "" }
    Result<Unit, Error> authenticate(Context context, ApiContext exchange) {
        String? header = exchange.header("Authorization")
        if header == null { return Err(new BasicError(ErrorKind.InvalidArgument,
            "missing bearer token")) }
        if !constantTimeEquals(header, "Bearer " + token) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "invalid bearer token"))
        }
        exchange.setPrincipal("service-account")
        exchange.setRoles(["reader"])
        return Ok(unit)
    }
}
```

反例：

- 认证器自己写 401 响应；
- 把令牌写入日志；
- 失败返回 `NotFound` 泄露用户是否存在；
- 成功不设置 principal；
- 对同一 `ApiContext` 重复设置 principal；
- 信任客户端 `X-User` 头而不验证凭据。

---

## 13. 测试/场景义务

Basic/Bearer/API key 成功/失败；缺失/格式错误；权限不足；后端不可用；取消；principal/roles/属性写入；重复 principal；并发调用；不泄露秘密；挑战头字段。

---

## 14. XNull 伪代码

> 非可执行设计伪代码。

```xnull
protocol Authenticator {
    AuthScheme scheme();
    String name();
    String parameterName();
    String realm();
    Result<Unit, Error> authenticate(Context context, ApiContext exchange);
}
```
