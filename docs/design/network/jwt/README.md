# `xdk.jwt` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.jwt` |
| 层 | L5 网络/数据（协议/安全） |
| 依赖 | `xdk.errors`、`xdk.bytes`、`xdk.text`、`xdk.codec`、`xdk.crypto` |
| 被依赖 | 应用、HTTP 服务/客户端 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

JWT/JWS：签名 token 的 header/claims、编码、解析、验证。

- 算法：HS256/384/512、RS256/384/512、PS256/384/512、ES256/384、EdDSA、SM2-SM3。
- 验证：签名、exp/nbf/iat、iss/aud、required claims、leeway。
- 不做：JWE、JWK 远程发现、OAuth 流程、UI 登录、密钥托管。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 独立包 | JWT 不是 utils/crypto；只依赖它们 |
| 算法显式 | header.alg 必须匹配验证 key/scheme |
| 默认验证 exp/nbf | 可用 options 显式调整 leeway |
| 不隐式信任 | 不自动拉 JWKS；不接受 `none` |
| 无全局 | 无全局密钥/算法注册表 |
| 错误分类 | 签名失败 `PermissionDenied`；格式 `DataCorrupted` |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `JwtAlgorithm` | enum | JWS 算法 | [`JwtAlgorithm.md`](JwtAlgorithm.md) |
| `JwtHeader` | class | alg/typ/kid | [`JwtHeader.md`](JwtHeader.md) |
| `JwtClaims` | class | claims/标准字段/过期 | [`JwtClaims.md`](JwtClaims.md) |
| `JwtToken` | class | header/claims/signature/raw | [`JwtToken.md`](JwtToken.md) |
| `JwtOptions` | class | 验证策略 | [`JwtOptions.md`](JwtOptions.md) |
| `Jwt` | class | 编解码/签名/验证 | [`Jwt.md`](Jwt.md) |

X：JWE、JWK Set 拉取、JWT 压缩、嵌套 JWT、自定义 claims schema。

---

## 4. 顶层函数

无。

---

## 5. 技术/支撑/依赖

- 技术：Base64URL、JSON、HMAC、RSA/ECDSA/Ed25519/SM2。
- 支撑：`Jwt` 运行时签名/验证原语、`Hmac`、`Asymmetric`、`Json`。
- 依赖：`errors`、`bytes`、`text`、`xdk.codec`、`xdk.crypto`。

---

## 6. 场景

### J1：HS256

`Jwt.encode(header, claims, secret)`；`Jwt.verify(token, secret, options)`。

### J2：RS256/ES256/EdDSA

私钥签名；公钥验证；算法必须匹配。

### J3：国密

SM2-SM3；key 来自 `xdk.crypto`。

### J4：过期/受众

`JwtOptions` 设置 leeway/issuer/audience/required claims。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| `none` 算法 | 拒绝 |
| JWE | X |
| JWKS 拉取 | X |
| 全局密钥 | 禁止 |
| 自动刷新 | X |
| JWT 压缩 | X |
