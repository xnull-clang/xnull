# `KdfAlgorithm`

| 项 | 值 |
| --- | --- |
| 类型 | `enum KdfAlgorithm` |
| 包 | `xdk.crypto` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

密钥派生：PBKDF2、scrypt、Argon2id、HKDF、SM3-KDF。

不做：口令哈希格式、盐管理、密钥存储。

---

## 2. 设计逻辑

- 固定枚举；参数由 `Kdf` 方法显式传入。
- Argon2id/SM3-KDF 为 K；企业 KDF X。
- 值语义；无 close。

---

## 3. 表示与不变量

| 成员 | 说明 |
| --- | --- |
| `Pbkdf2` | PBKDF2 |
| `Scrypt` | scrypt |
| `Argon2id` | Argon2id |
| `Hkdf` | HKDF |
| `Sm3Kdf` | SM3 KDF |

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

无实例方法；`Kdf` 使用。

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

正确：`Kdf.derive(KdfAlgorithm.Argon2id,...)`。  
反例：把密码当密钥；固定盐；忽略参数。

---

## 13. 测试/场景义务

每个算法；已知向量；盐/参数；长度；失败。

---

## 14. XNull 伪代码

```xnull
enum KdfAlgorithm {
    Pbkdf2,
    Scrypt,
    Argon2id,
    Hkdf,
    Sm3Kdf,
}
```
