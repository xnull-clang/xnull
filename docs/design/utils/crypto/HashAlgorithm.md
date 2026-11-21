# `HashAlgorithm`

| 项 | 值 |
| --- | --- |
| 类型 | `enum HashAlgorithm` |
| 包 | `xdk.crypto` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

摘要算法：SHA-1/2/3、BLAKE2/3、SM3；MD5 仅兼容。

不做：密码、HMAC、签名。

---

## 2. 设计逻辑

- 固定枚举；算法能力由运行时提供。
- MD5/SHA-1 标记 legacy，不用于新安全设计。
- 值语义；无 close。

---

## 3. 表示与不变量

| 成员 | 说明 |
| --- | --- |
| `Md5` | legacy |
| `Sha1` | legacy |
| `Sha224`/`Sha256`/`Sha384`/`Sha512` | SHA-2 |
| `Sha3_256`/`Sha3_384`/`Sha3_512` | SHA-3 |
| `Blake2b`/`Blake3` | BLAKE |
| `Sm3` | GB/T 32905 |

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

无实例方法；`Hash` 使用。

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

正确：`Hash.digest(HashAlgorithm.Sm3, data)`。  
反例：新系统用 MD5；把枚举名当算法实现。

---

## 13. 测试/场景义务

每个枚举成员；legacy 标识；算法可用性。

---

## 14. XNull 伪代码

```xnull
enum HashAlgorithm {
    Md5,
    Sha1,
    Sha224,
    Sha256,
    Sha384,
    Sha512,
    Sha3_256,
    Sha3_384,
    Sha3_512,
    Blake2b,
    Blake3,
    Sm3,
}
```
