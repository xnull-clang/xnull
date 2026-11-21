# `Asymmetric`

| 项 | 值 |
| --- | --- |
| 类型 | `class Asymmetric` |
| 包 | `xdk.crypto` |
| 稳定性 | `preview` |
| 依赖 | `AsymmetricAlgorithm`、`SignatureScheme`、`PublicKey`、`PrivateKey`、`KeyPair`、`Bytes`、`Error` |

---

## 1. 定位

非对称静态入口：keypair 生成、加密/解密、签名/验证。

不做：证书、密钥库、JWT、密钥交换（X）。

---

## 2. 设计逻辑

- 无状态；构造器私有。
- `encrypt/decrypt` 用于 RSA-OAEP/SM2；其他算法 `Unsupported`。
- `sign/verify` 使用显式 `SignatureScheme`。
- 私钥不导出；失败 `InvalidArgument`/`Unsupported`/`DataCorrupted`。
- 无 close。

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
| `Asymmetric()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `generate` | 生成 keypair | `AsymmetricAlgorithm` | `Result<KeyPair, Error>` | 算法失败 |
| `encrypt` | 公钥加密 | `PublicKey, Bytes` | `Result<Bytes, Error>` | `Unsupported`/参数 |
| `decrypt` | 私钥解密 | `PrivateKey, Bytes` | `Result<Bytes, Error>` | `DataCorrupted`/参数 |
| `sign` | 签名 | `PrivateKey, Bytes data, SignatureScheme` | `Result<Bytes, Error>` | `Unsupported`/参数 |
| `verify` | 验证 | `PublicKey, Bytes data, Bytes signature, SignatureScheme` | `Bool` | 无 |

---

## 8. 使用的技术

- RSA-OAEP/PKCS1/PSS；
- ECDSA/Ed25519/SM2；
- 密钥句柄。

---

## 9. 需要的支撑

- 语言：class、Bytes、Bool、Result；
- 运行时：`generateKeyPairRaw`、`asymmetricEncryptRaw`、`asymmetricDecryptRaw`、`asymmetricSignRaw`、`asymmetricVerifyRaw`、`CryptoKeyHandle`；
- 接口：`AsymmetricAlgorithm`、`SignatureScheme`、`PublicKey`、`PrivateKey`、`KeyPair`、`Bytes`、`Error`。

---

## 10. 依赖的特性/接口/类

`AsymmetricAlgorithm`、`SignatureScheme`、`PublicKey`、`PrivateKey`、`KeyPair`、`Error`、非对称运行时原语。

---

## 11. 所有权与并发

无状态；无资源；可并发。

---

## 12. 示例与反例

正确：`Asymmetric.generate(Sm2)`；`sign(key,data,Sm2Sm3)`。  
反例：ECDSA 用 RSA scheme；RSA 用 Ed25519 key；日志私钥。

---

## 13. 测试/场景义务

key 生成；RSA 加解密；签名/验证；SM2/SM3；错误 scheme；篡改；私钥不导出。

---

## 14. XNull 伪代码

```xnull
class Asymmetric {
    private Asymmetric() {
    }

    static Result<KeyPair, Error> generate(AsymmetricAlgorithm algorithm) {
        return generateKeyPairRaw(algorithm)
    }

    static Result<Bytes, Error> encrypt(PublicKey key, Bytes plaintext) {
        if key == null || plaintext == null {
            throw "Asymmetric.encrypt: null argument"
        }
        return asymmetricEncryptRaw(key, plaintext)
    }

    static Result<Bytes, Error> decrypt(PrivateKey key, Bytes ciphertext) {
        if key == null || ciphertext == null {
            throw "Asymmetric.decrypt: null argument"
        }
        return asymmetricDecryptRaw(key, ciphertext)
    }

    static Result<Bytes, Error> sign(PrivateKey key, Bytes data, SignatureScheme scheme) {
        if key == null || data == null || scheme == null {
            throw "Asymmetric.sign: null argument"
        }
        return asymmetricSignRaw(key, data, scheme)
    }

    static Bool verify(PublicKey key, Bytes data, Bytes signature, SignatureScheme scheme) {
        if key == null || data == null || signature == null || scheme == null {
            return false
        }
        return asymmetricVerifyRaw(key, data, signature, scheme)
    }
}
```

> `generateKeyPairRaw`、`asymmetric*Raw` 是运行时非对称原语；不是 XDK 公共类型。
