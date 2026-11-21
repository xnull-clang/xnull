# `KeyPair`

| 项 | 值 |
| --- | --- |
| 类型 | `class KeyPair` |
| 包 | `xdk.crypto` |
| 稳定性 | `preview` |
| 依赖 | `PublicKey`、`PrivateKey`、`AsymmetricAlgorithm` |

---

## 1. 定位

非对称公私钥对：公钥、私钥、算法。

不做：证书、密钥库、序列化私钥。

---

## 2. 设计逻辑

- 字段 `_publicKey`、`_privateKey`；非 null。
- 算法从公钥/私钥一致性保证。
- 不可变；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_publicKey` | `PublicKey` | 公钥 |
| `_privateKey` | `PrivateKey` | 私钥 |

---

## 4. 生命周期

不可变；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `KeyPair(PublicKey publicKey, PrivateKey privateKey)` | 非 null；算法一致 | 非 null | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `publicKey` | 公钥 | 无 | `PublicKey` | 无 |
| `privateKey` | 私钥 | 无 | `PrivateKey` | 无 |
| `algorithm` | 算法 | 无 | `AsymmetricAlgorithm` | 无 |

---

## 8. 使用的技术

- 公私钥对。

---

## 9. 需要的支撑

- 语言：class；
- 运行时：无；
- 接口：`PublicKey`、`PrivateKey`、`AsymmetricAlgorithm`。

---

## 10. 依赖的特性/接口/类

`PublicKey`、`PrivateKey`、`AsymmetricAlgorithm`。

---

## 11. 所有权与并发

不可变；私钥不导出；可共享。

---

## 12. 示例与反例

正确：`KeyPair pair = Asymmetric.generate(Sm2).value()`。  
反例：公钥/私钥算法不一致；日志打印私钥。

---

## 13. 测试/场景义务

算法一致；getters；生成；不可变。

---

## 14. XNull 伪代码

```xnull
class KeyPair {
    final PublicKey _publicKey
    final PrivateKey _privateKey

    KeyPair(PublicKey publicKey, PrivateKey privateKey) {
        if publicKey == null || privateKey == null {
            throw "KeyPair: null argument"
        }
        if publicKey.algorithm() != privateKey.algorithm() {
            throw "KeyPair: algorithm mismatch"
        }
        _publicKey = publicKey
        _privateKey = privateKey
    }

    PublicKey publicKey() { return _publicKey }
    PrivateKey privateKey() { return _privateKey }
    AsymmetricAlgorithm algorithm() { return _publicKey.algorithm() }
}
```
