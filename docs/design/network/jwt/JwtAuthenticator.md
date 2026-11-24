# `JwtAuthenticator`

| 项 | 值 |
| --- | --- |
| 类型 | `class JwtAuthenticator implements Authenticator` |
| 包 | `xdk.jwt` |
| 稳定性 | `preview` |
| 依赖 | `Jwt`、`JwtClaims`、`JwtOptions`、`Principal`、`AuthScheme`、`Authenticator`、`Credential` |

## 定位

把 HS256 JWT 验证接到 `xdk.auth`：验证 token，把 claims 映射为 `Principal`；不缓存 token/secret。

## 构造

| 构造 | 参数 | 失败 |
| --- | --- | --- |
| `JwtAuthenticator` | `Bytes secret, JwtOptions options` | null/空 secret → panic |
| `forSecret` | `Bytes secret` | 同上；默认 options |

`scheme()` 固定返回 `AuthScheme.Jwt`。

## 认证映射

1. Context 预取消 → `Cancelled`；
2. credential scheme 非 Jwt → `InvalidArgument: credential scheme mismatch`；
3. `Jwt.verify` 失败错误原样；
4. `sub` 缺失/空 → `PermissionDenied: missing sub`；
5. `roles`：数组逐项；字符串含逗号按逗号，否则按空格；去重保序；
6. `permissions` 同上，再合并 `scope`（空格分隔）；
7. claims 快照：String 原样、number 文本、bool true/false、null/object 跳过、数组逗号连接；`sub/roles/permissions/scope` 保留；
8. 构造 `Principal.authenticated(subject, Jwt)` + roles/permissions/claims。

Context 验证后再次取消 → `Cancelled`。

## 安全边界

- 不解析 JWKS、不刷新、不缓存、不保存 secret 到 Principal；
- `describe()` 只输出 scheme；
- 只有 HS256 生效，其他 alg 由 `Jwt.verify` 返回 Unsupported。
