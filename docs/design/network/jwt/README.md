# `xdk.jwt` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.jwt` |
| 层 | L5 网络/数据（协议/安全） |
| 依赖 | `xdk.errors`、`xdk.bytes`、`xdk.text`、`xdk.codec`、`xdk.crypto` |
| 被依赖 | 应用、HTTP 服务/客户端 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |
| 实现状态 | M15.2 HS256 子集：`JwtAlgorithm`/`JwtHeader`/`JwtClaims`/`JwtOptions`/`JwtToken`/`Jwt` implemented；HS384/512、RS/PS/ES/EdDSA/SM2 均返回 `Unsupported`；无 JWKS/网络/非对称 |

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

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | `@JwtClaim`、`@JwtHeaderField` |
| 本包消费 | `@Value`、`@Builder`、`@Serializable`、`@JsonName` |
| 处理器 | JwtAnnotationProcessor（Validate/Generate） |
| 生成物 | claims/header 映射、序列化元数据 |
| 状态 | 领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| claims 类 | `@JwtClaim` | claim 字段映射 |
| header 类 | `@JwtHeaderField` | header 字段映射 |
| `JwtClaims`/`JwtHeader`/`JwtToken`/`JwtOptions` | `@Value`/`@Builder` | 值语义/选项 |
| claims/header DTO | `@Serializable`/`@JsonName` | JSON 编解码 |

### 声明

```x
@Target(Field)
@Retention(Source)
@annotation JwtClaim {
    final String value
}

@Target(Field)
@Retention(Source)
@annotation JwtHeaderField {
    final String value
}
```

声明文件：每个注解单独一个 PascalCase 文件；处理器为构建期类型；生成代码在 `<package>/generated/`。

### 使用

```x
@Serializable
class AccessClaims {
    @JwtClaim("sub") String subject
    @JwtClaim("exp") Long expiresAt
}

@Serializable
class JwtHeaderFields {
    @JwtHeaderField("alg") String algorithm
    @JwtHeaderField("kid") String keyId
}
```

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
