# `AsymmetricAlgorithm`

| 项 | 值 |
| --- | --- |
| 类型 | `enum AsymmetricAlgorithm` |
| 包 | `xdk.crypto` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

非对称密钥族：RSA、ECDSA P-256/P-384、Ed25519、SM2；SM9 X。

不做：密钥交换（X25519 X）、证书、签名方案（另 enum）。

---

## 2. 设计逻辑

- 固定枚举；密钥对生成按成员。
- RSA 2048/3072/4096；ECDSA P-256/P-384；Ed25519；SM2。
- 值语义；无 close。

---

## 3. 表示与不变量

| 成员 | 说明 |
| --- | --- |
| `Rsa2048`/`Rsa3072`/`Rsa4096` | RSA |
| `EcdsaP256`/`EcdsaP384` | ECDSA |
| `Ed25519` | Ed25519 |
| `Sm2` | GB/T 32918 |
| `Sm9` | X |

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

无实例方法；`Asymmetric` 使用。

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

正确：`Asymmetric.generate(AsymmetricAlgorithm.Sm2)`。  
反例：RSA 2048 当 Ed25519；SM9 当 K。

---

## 13. 测试/场景义务

每个成员；key 生成；签名/加密支持；SM9 unsupported。

---

## 14. XNull 伪代码

```xnull
enum AsymmetricAlgorithm {
    Rsa2048,
    Rsa3072,
    Rsa4096,
    EcdsaP256,
    EcdsaP384,
    Ed25519,
    Sm2,
    Sm9,
}
```
