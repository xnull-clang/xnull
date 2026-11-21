# `Jwt`

| 项 | 值 |
| --- | --- |
| 类型 | `class Jwt` |
| 包 | `xdk.jwt` |
| 稳定性 | `preview` |
| 依赖 | `JwtHeader`、`JwtClaims`、`JwtToken`、`JwtOptions`、`JwtAlgorithm`、`Bytes`、`PrivateKey`、`PublicKey`、`Error` |

---

## 1. 定位

JWT 静态入口：HMAC/非对称签名、解析、验证（签名+claims）。

不做：JWE、JWKS 拉取、OAuth、密钥管理。

---

## 2. 设计逻辑

- 无状态；构造器私有。
- `encode` 按 header.alg 选择 HMAC/非对称；算法与 key 不匹配 → `InvalidArgument`。
- `decode` 只解析，不验证；调用方必须 `verify`。
- `verify` 校验签名、exp/nbf、iss/aud、required；失败 `PermissionDenied`/`InvalidArgument`。
- 拒绝 `none`；无全局。

---

## 3. 表示与不变量

无实例字段。

---

## 4. 生命周期

静态命名空间；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Jwt()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `encode` | HMAC 签名 | `JwtHeader, JwtClaims, Bytes secret` | `Result<String, Error>` | 参数/算法 |
| `encode` | 非对称签名 | `JwtHeader, JwtClaims, PrivateKey key` | `Result<String, Error>` | 参数/算法 |
| `decode` | 解析不验证 | `String token` | `Result<JwtToken, Error>` | `DataCorrupted` |
| `verify` | HMAC 验证 | `String token, Bytes secret, JwtOptions options` | `Result<JwtClaims, Error>` | 签名/claims |
| `verify` | 非对称验证 | `String token, PublicKey key, JwtOptions options` | `Result<JwtClaims, Error>` | 同上 |

---

## 8. 使用的技术

- Base64URL + JSON；
- HMAC/RSA/ECDSA/Ed25519/SM2；
- claims 校验。

---

## 9. 需要的支撑

- 语言：class、String、Bytes、Result；
- 运行时：`jwtEncodeRaw`、`jwtDecodeRaw`、`jwtVerifyRaw`、`jwtValidateClaimsRaw`；
- 接口：`JwtHeader`、`JwtClaims`、`JwtToken`、`JwtOptions`、`JwtAlgorithm`、`PrivateKey`、`PublicKey`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`JwtHeader`、`JwtClaims`、`JwtToken`、`JwtOptions`、`JwtAlgorithm`、`PrivateKey`、`PublicKey`、`Error`、JWT 运行时原语。

---

## 11. 所有权与并发

无状态；无资源；可并发。

---

## 12. 示例与反例

正确：`Jwt.verify(token, publicKey, options)`。  
反例：只 decode 不 verify；alg 与 key 不匹配；接受 none；关闭 exp 验证。

---

## 13. 测试/场景义务

HS/RS/PS/ES/EdDSA/SM2；alg/key 不匹配；篡改；exp/nbf/leeway；iss/aud/required；decode 不验证；none。

---

## 14. XNull 伪代码

```xnull
class Jwt {
    private Jwt() {
    }

    static Result<String, Error> encode(JwtHeader header, JwtClaims claims, Bytes secret) {
        if header == null || claims == null || secret == null {
            throw "Jwt.encode: null argument"
        }
        return jwtEncodeRaw(header, claims, secret, null)
    }

    static Result<String, Error> encode(JwtHeader header, JwtClaims claims, PrivateKey key) {
        if header == null || claims == null || key == null {
            throw "Jwt.encode: null argument"
        }
        return jwtEncodeRaw(header, claims, null, key)
    }

    static Result<JwtToken, Error> decode(String token) {
        if token == null { throw "Jwt.decode: null" }
        return jwtDecodeRaw(token)
    }

    static Result<JwtClaims, Error> verify(String token, Bytes secret, JwtOptions options) {
        if token == null || secret == null || options == null {
            throw "Jwt.verify: null argument"
        }
        Result<JwtToken, Error> parsed = Jwt.decode(token)
        if parsed.isErr() { return Err(parsed.error()) }
        Result<Unit, Error> signature = jwtVerifyRaw(parsed.value(), secret, null)
        if signature.isErr() { return Err(signature.error()) }
        Result<Unit, Error> claims = jwtValidateClaimsRaw(parsed.value().claims(), options.copy())
        if claims.isErr() { return Err(claims.error()) }
        return Ok(parsed.value().claims())
    }

    static Result<JwtClaims, Error> verify(String token, PublicKey key, JwtOptions options) {
        if token == null || key == null || options == null {
            throw "Jwt.verify: null argument"
        }
        Result<JwtToken, Error> parsed = Jwt.decode(token)
        if parsed.isErr() { return Err(parsed.error()) }
        Result<Unit, Error> signature = jwtVerifyRaw(parsed.value(), null, key)
        if signature.isErr() { return Err(signature.error()) }
        Result<Unit, Error> claims = jwtValidateClaimsRaw(parsed.value().claims(), options.copy())
        if claims.isErr() { return Err(claims.error()) }
        return Ok(parsed.value().claims())
    }
}
```

> `jwt*Raw` 是运行时 JWT 原语；不是 XDK 公共类型。
