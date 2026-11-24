# `Credential`

| 项 | 值 |
| --- | --- |
| 类型 | `class Credential` |
| 包 | `xdk.auth` |
| 稳定性 | `preview` |
| 依赖 | `AuthScheme` |

## 定位

待验证凭据：scheme + 原始值；不验证、不缓存。

## 构造

`Credential(AuthScheme scheme, String value)`：scheme 非 null/Unknown，value 非空；否则 panic。

工厂：`jwt(token)`、`bearer(token)`、`apiKey(value)`。

## 方法

| 方法 | 返回 |
| --- | --- |
| `scheme` | `AuthScheme` |
| `value` | `String` |
| `describe` | 脱敏文本 |

`describe` 只输出 scheme、长度和最多前 4 字符，不输出完整凭据。

## 场景

`Credential.jwt("abcdefgh").describe()` 不包含完整 `abcdefgh`。
