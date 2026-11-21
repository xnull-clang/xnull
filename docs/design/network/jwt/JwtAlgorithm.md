# `JwtAlgorithm`

| 项 | 值 |
| --- | --- |
| 类型 | `enum JwtAlgorithm` |
| 包 | `xdk.jwt` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

JWS 签名算法族：HMAC、RSA、RSA-PSS、ECDSA、EdDSA、SM2-SM3。

不做：JWE 加密、`none`。

---

## 2. 设计逻辑

- 固定枚举；header.alg 必须匹配 key 类型。
- 值语义；无 close。

---

## 3. 表示与不变量

| 成员 | JWS 名 |
| --- | --- |
| `Hs256`/`Hs384`/`Hs512` | HS* |
| `Rs256`/`Rs384`/`Rs512` | RS* |
| `Ps256`/`Ps384`/`Ps512` | PS* |
| `Es256`/`Es384` | ES* |
| `EdDsa` | EdDSA |
| `Sm2Sm3` | SM2-SM3 |

---

## 4. 生命周期

值类型；无 close。

---

## 5. 构造契约

枚举成员直接使用。

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `jwtAlgorithmName` | JWS 名 | `JwtAlgorithm` | `String` | 无 |
| `parseJwtAlgorithm` | 解析 | `String` | `Result<JwtAlgorithm, Error>` | `InvalidArgument` |

---

## 8. 使用的技术

- 简单枚举。

---

## 9. 需要的支撑

- 语言：enum、String、Result。

---

## 10. 依赖的特性/接口/类

`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

值语义；无资源。

---

## 12. 示例与反例

正确：`parseJwtAlgorithm("RS256")`。  
反例：接受 `none`；HS256 配 RSA key。

---

## 13. 测试/场景义务

每个成员；名称/解析；大小写；none 拒绝。

---

## 14. XNull 伪代码

```xnull
enum JwtAlgorithm {
    Hs256,
    Hs384,
    Hs512,
    Rs256,
    Rs384,
    Rs512,
    Ps256,
    Ps384,
    Ps512,
    Es256,
    Es384,
    EdDsa,
    Sm2Sm3,
}

String jwtAlgorithmName(JwtAlgorithm algorithm) {
    if algorithm == JwtAlgorithm.Hs256 { return "HS256" }
    if algorithm == JwtAlgorithm.Hs384 { return "HS384" }
    if algorithm == JwtAlgorithm.Hs512 { return "HS512" }
    if algorithm == JwtAlgorithm.Rs256 { return "RS256" }
    if algorithm == JwtAlgorithm.Rs384 { return "RS384" }
    if algorithm == JwtAlgorithm.Rs512 { return "RS512" }
    if algorithm == JwtAlgorithm.Ps256 { return "PS256" }
    if algorithm == JwtAlgorithm.Ps384 { return "PS384" }
    if algorithm == JwtAlgorithm.Ps512 { return "PS512" }
    if algorithm == JwtAlgorithm.Es256 { return "ES256" }
    if algorithm == JwtAlgorithm.Es384 { return "ES384" }
    if algorithm == JwtAlgorithm.EdDsa { return "EdDSA" }
    return "SM2-SM3"
}

Result<JwtAlgorithm, Error> parseJwtAlgorithm(String text) {
    if text == null { throw "parseJwtAlgorithm: null" }
    String value = text.toUpper()
    if value == "HS256" { return Ok(JwtAlgorithm.Hs256) }
    if value == "HS384" { return Ok(JwtAlgorithm.Hs384) }
    if value == "HS512" { return Ok(JwtAlgorithm.Hs512) }
    if value == "RS256" { return Ok(JwtAlgorithm.Rs256) }
    if value == "RS384" { return Ok(JwtAlgorithm.Rs384) }
    if value == "RS512" { return Ok(JwtAlgorithm.Rs512) }
    if value == "PS256" { return Ok(JwtAlgorithm.Ps256) }
    if value == "PS384" { return Ok(JwtAlgorithm.Ps384) }
    if value == "PS512" { return Ok(JwtAlgorithm.Ps512) }
    if value == "ES256" { return Ok(JwtAlgorithm.Es256) }
    if value == "ES384" { return Ok(JwtAlgorithm.Es384) }
    if value == "EDDSA" { return Ok(JwtAlgorithm.EdDsa) }
    if value == "SM2-SM3" { return Ok(JwtAlgorithm.Sm2Sm3) }
    return Err(new BasicError(ErrorKind.InvalidArgument, "unsupported JWT algorithm: " + text))
}
```
