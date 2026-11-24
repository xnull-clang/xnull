# `Authenticator`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol Authenticator` |
| 包 | `xdk.auth` |
| 稳定性 | `preview` |
| 依赖 | `AuthScheme`、`Credential`、`Principal`、`Context`、`Error` |

## 定位

单 scheme 认证合同；实现可以验证 JWT、Bearer、API Key、Basic 或匿名。

## 方法

| 方法 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- |
| `scheme` | 无 | `AuthScheme` | 无 |
| `authenticate` | `Context, Credential` | `Result<Principal, Error>` | 实现定义；取消 `Cancelled` |

实现不得缓存凭据；错误原样返回给 `AuthService`。
