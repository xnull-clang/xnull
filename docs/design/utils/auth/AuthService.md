# `AuthService`

| 项 | 值 |
| --- | --- |
| 类型 | `class AuthService` |
| 包 | `xdk.auth` |
| 稳定性 | `preview` |
| 依赖 | `Authenticator`、`Credential`、`Principal`、`Context`、`Error` |

## 定位

显式组合多个 `Authenticator`，按 scheme 选择；无全局注册表。

## 构造与选择

| 方法 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- |
| `create` | `List<Authenticator>` | `AuthService` | null/重复 scheme → panic |
| `authenticate` | `Context, Credential` | `Result<Principal, Error>` | 取消 Cancelled；无匹配 Unsupported；其余原样 |
| `authenticators` | 无 | 列表副本 | 无 |

构造时复制列表；重复 scheme panic（AlreadyExists 语义）。`authenticate` 先检查 Context 取消，再按 scheme 线性选择。

## 场景

无 Jwt authenticator 时 `Credential.jwt` → `Unsupported`；认证器错误不包装。
