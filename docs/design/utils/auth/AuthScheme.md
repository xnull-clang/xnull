# `AuthScheme`

| 项 | 值 |
| --- | --- |
| 类型 | `enum AuthScheme` |
| 包 | `xdk.auth` |
| 稳定性 | `preview` |
| 依赖 | `xdk.errors` |

## 定位

认证 scheme 分类：Jwt/Bearer/ApiKey/Basic/Anonymous；不携带密钥或策略。

## 表示

| 成员 | 名称 |
| --- | --- |
| `Jwt` | `jwt` |
| `Bearer` | `bearer` |
| `ApiKey` | `api_key` |
| `Basic` | `basic` |
| `Anonymous` | `anonymous` |

内部 `Unknown` 占 0 号，业务不使用。

## 方法

| 方法 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- |
| `authSchemeName` | `AuthScheme` | 小写稳定名 | 无 |
| `parseAuthScheme` | `String` | `Result<AuthScheme, Error>` | 未知 `InvalidArgument` |

`parseAuthScheme` 大小写不敏感；`api_key`/`api-key`/`apikey` 等价；不接受 `none`。

## 场景

`parseAuthScheme("BEARER") == Bearer`；`parseAuthScheme("none")` 返回 Err。
