# `Principal`

| 项 | 值 |
| --- | --- |
| 类型 | `class Principal` |
| 包 | `xdk.auth` |
| 稳定性 | `preview` |
| 依赖 | `AuthScheme` |

## 定位

已验证身份快照：subject、scheme、roles、permissions、claims。只能由 factory/Authenticator 构造。

## 工厂

| 工厂 | 说明 |
| --- | --- |
| `authenticated(subject, scheme)` | 非空 subject、非 Anonymous scheme |
| `anonymous()` | subject 空、Anonymous scheme |

## 方法

`subject/scheme/roles/permissions/claims/isAuthenticated`；`withRole/withPermission/withClaim` 返回新对象；`hasRole/hasPermission/claimOrNull/copy/describe`。

roles/permissions 去重保序；claims 防御性复制；匿名 `isAuthenticated=false`。
