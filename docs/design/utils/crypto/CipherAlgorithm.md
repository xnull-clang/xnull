# `CipherAlgorithm`

| 项 | 值 |
| --- | --- |
| 类型 | `enum CipherAlgorithm` |
| 包 | `xdk.crypto` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

对称加密算法/模式：AES、ChaCha20、SM4、ZUC，含 CBC/CTR/GCM/AEAD。

不做：RSA/ECC、TLS、密钥交换。

---

## 2. 设计逻辑

- 固定枚举；密钥长度由算法决定。
- CBC/CTR 需要 nonce/IV；GCM/AEAD 需要 nonce + tag；ZUC 流密码。
- 值语义；无 close。

---

## 3. 表示与不变量

| 成员 | 说明 |
| --- | --- |
| `Aes128Cbc`/`Aes192Cbc`/`Aes256Cbc` | AES-CBC |
| `Aes128Ctr`/`Aes256Ctr` | AES-CTR |
| `Aes128Gcm`/`Aes256Gcm` | AES-GCM |
| `ChaCha20` | ChaCha20 流 |
| `ChaCha20Poly1305` | AEAD |
| `Sm4Cbc`/`Sm4Ctr`/`Sm4Gcm` | SM4 |
| `Zuc128`/`Zuc256` | ZUC 流 |

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

无实例方法；`Cipher` 使用。

---

## 8. 使用的技术

- 简单枚举；
- 算法/模式标识。

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

正确：`new Cipher(CipherAlgorithm.Sm4Gcm,key)`。  
反例：CBC 用 12 字节 nonce；GCM 不校验 tag；ZUC 当块密码。

---

## 13. 测试/场景义务

每个算法；key/nonce/tag 长度；AEAD 篡改；padding。

---

## 14. XNull 伪代码

```xnull
enum CipherAlgorithm {
    Aes128Cbc,
    Aes192Cbc,
    Aes256Cbc,
    Aes128Ctr,
    Aes256Ctr,
    Aes128Gcm,
    Aes256Gcm,
    ChaCha20,
    ChaCha20Poly1305,
    Sm4Cbc,
    Sm4Ctr,
    Sm4Gcm,
    Zuc128,
    Zuc256,
}
```
