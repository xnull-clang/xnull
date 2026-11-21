# `SignatureScheme`

| 项 | 值 |
| --- | --- |
| 类型 | `enum SignatureScheme` |
| 包 | `xdk.crypto` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

签名方案：RSA PKCS#1/PSS、ECDSA SHA-256/384、Ed25519、SM2-SM3。

不做：密钥生成、加密、JWT。

---

## 2. 设计逻辑

- 固定枚举；scheme 含哈希/填充语义。
- `Asymmetric.sign/verify` 接受 scheme。
- 值语义；无 close。

---

## 3. 表示与不变量

| 成员 | 说明 |
| --- | --- |
| `RsaPkcs1Sha256` | RSASSA-PKCS1-v1_5 + SHA-256 |
| `RsaPssSha256` | RSASSA-PSS + SHA-256 |
| `EcdsaSha256` | ECDSA P-256/SHA-256 |
| `EcdsaSha384` | ECDSA P-384/SHA-384 |
| `Ed25519` | Ed25519 |
| `Sm2Sm3` | SM2 + SM3 |

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

无实例方法。

---

## 8. 使用的技术

- 简单枚举。

---

## 9. 需要的支撑

- 语言：enum。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

值语义；无资源。

---

## 12. 示例与反例

正确：RSA 2048 + `RsaPssSha256`。  
反例：ECDSA P-256 用 EcdsaSha384；SM2 用 RSA scheme。

---

## 13. 测试/场景义务

每个 scheme；错误 key 类型；签名/验证；篡改。

---

## 14. XNull 伪代码

```xnull
enum SignatureScheme {
    RsaPkcs1Sha256,
    RsaPssSha256,
    EcdsaSha256,
    EcdsaSha384,
    Ed25519,
    Sm2Sm3,
}
```
