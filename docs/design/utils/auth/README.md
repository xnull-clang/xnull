# `xdk.auth` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.auth` |
| 层 | L8 安全/认证 |
| 依赖 | `xdk.errors`、`xdk.tasks` |
| 被依赖 | 应用、HTTP 服务/客户端、注解层 |
| 稳定性 | `preview` |
| 实现状态 | M16.1：`AuthScheme`/`Credential`/`Principal`/`Authenticator`/`AuthService` implemented；JWT authenticator 在 `xdk.jwt` 接入（M16.3）；不是全局认证器 |

## 1. 定位

认证域：认证（你是谁）与授权（能做什么）分离。`Credential` 是待验证凭据，`Principal` 是已验证身份；`Authenticator` 负责单个 scheme，`AuthService` 显式组合多个 scheme。

不做：角色继承、数据库权限查询、刷新令牌、全局上下文、反射、全局注册表、JWT 实现。

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 认证/授权分离 | `Authenticator` 只认证；角色/权限由 Principal 携带或应用判定 |
| 显式组合 | `AuthService` 持有调用方传入的 authenticator 列表 |
| 无全局 | 无默认 AuthService / 默认密钥 |
| 凭据不缓存 | service 只选择并调用 authenticator |
| 防御性复制 | Principal roles/permissions/claims 返回副本 |
| 错误分类 | scheme 不匹配 Unsupported；取消 Cancelled；验证失败由 authenticator 返回 |

## 3. 类型索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `AuthScheme` | enum | Jwt/Bearer/ApiKey/Basic/Anonymous | [`AuthScheme.md`](AuthScheme.md) |
| `Credential` | class | scheme + 脱敏凭据值 | [`Credential.md`](Credential.md) |
| `Principal` | class | 身份、角色、权限、claims | [`Principal.md`](Principal.md) |
| `Authenticator` | protocol | 单 scheme 认证 | [`Authenticator.md`](Authenticator.md) |
| `AuthService` | class | scheme 选择/组合 | [`AuthService.md`](AuthService.md) |

## 4. 场景

```x
List<Authenticator> values = []
values.push(jwtAuthenticator)
AuthService service = AuthService.create(values)
Result<Principal, Error> principal = service.authenticate(context, Credential.jwt(token))
```

Principal 只能由 `Authenticator`/工厂构造；注解层只消费 `Principal`，不直接依赖 JWT。

## 5. 缺口

| 项 | 决策 |
| --- | --- |
| JWT authenticator | 在 `xdk.jwt` 实现，本包不依赖 |
| 角色继承/DB 权限 | 应用或 X |
| 刷新令牌 | X |
| 全局上下文/注册表 | 禁止 |
