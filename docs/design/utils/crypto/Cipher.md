# `Cipher`

| 项 | 值 |
| --- | --- |
| 类型 | `class Cipher` |
| 包 | `xdk.crypto` |
| 稳定性 | `preview` |
| 依赖 | `CipherAlgorithm`、`CipherPadding`、`Bytes`、`Error` |

---

## 1. 定位

对称加解密：AES/SM4 块模式、AES-GCM/SM4-GCM/ChaCha20-Poly1305、ChaCha20/ZUC 流。

不做：密钥生成、KDF、非对称、TLS。

---

## 2. 设计逻辑

- 字段 `_algorithm`、`_key`、`_padding`；构造复制 key。
- nonce/IV 由调用方提供；AEAD 额外 aad。
- `encrypt` 返回密文；AEAD 的 tag 追加在末尾。
- `decrypt` 校验 tag/填充；失败 `DataCorrupted`。
- 无 close；非线程安全（同一实例不并发）。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_algorithm` | `CipherAlgorithm` | 算法/模式 |
| `_key` | `Bytes` | 密钥副本 |
| `_padding` | `CipherPadding` | 块填充 |

---

## 4. 生命周期

构造；无 close；密钥不打印。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Cipher(CipherAlgorithm algorithm, Bytes key, CipherPadding padding)` | key 长度匹配 | 非 null | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `encrypt` | 加密 | `Bytes plaintext, Bytes nonce, Bytes aad` | `Result<Bytes, Error>` | 参数/算法 |
| `decrypt` | 解密 | `Bytes ciphertext, Bytes nonce, Bytes aad` | `Result<Bytes, Error>` | 校验失败/参数 |
| `isAead` | 是否 AEAD | 无 | `Bool` | 无 |
| `keySize` | 密钥字节 | 无 | `Int` | 无 |
| `nonceSize` | nonce 字节 | 无 | `Int` | 无 |
| `tagSize` | tag 字节 | 无 | `Int` | 无 |
| `algorithm` | 算法 | 无 | `CipherAlgorithm` | 无 |

---

## 8. 使用的技术

- 块/流/AEAD；
- 填充；
- tag 校验。

---

## 9. 需要的支撑

- 语言：class、Bytes、Bool、Int、Result；
- 运行时：`cipherEncryptRaw`、`cipherDecryptRaw`、`cipherKeySizeRaw`、`cipherNonceSizeRaw`、`cipherTagSizeRaw`；
- 接口：`CipherAlgorithm`、`CipherPadding`、`Bytes`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`CipherAlgorithm`、`CipherPadding`、`Bytes`、`Error`、cipher 运行时原语。

---

## 11. 所有权与并发

持有密钥副本；非线程安全；无 close；不导出密钥。

---

## 12. 示例与反例

正确：`new Cipher(Aes256Gcm,key,Pkcs7).encrypt(plain,nonce,aad)`。  
反例：GCM 用 PKCS7；重复 nonce；忽略 tag 失败。

---

## 13. 测试/场景义务

各算法；key/nonce 长度；AEAD 篡改；CBC 填充；流模式；空明文；参数错误。

---

## 14. XNull 伪代码

```xnull
class Cipher {
    final CipherAlgorithm _algorithm
    final Bytes _key
    final CipherPadding _padding

    Cipher(CipherAlgorithm algorithm, Bytes key, CipherPadding padding) {
        if algorithm == null || key == null || padding == null {
            throw "Cipher: null argument"
        }
        _algorithm = algorithm
        _key = key.copy()
        _padding = padding
    }

    Result<Bytes, Error> encrypt(Bytes plaintext, Bytes nonce, Bytes aad) {
        if plaintext == null || nonce == null || aad == null {
            throw "Cipher.encrypt: null argument"
        }
        return cipherEncryptRaw(_algorithm, _key, _padding, plaintext, nonce, aad)
    }

    Result<Bytes, Error> decrypt(Bytes ciphertext, Bytes nonce, Bytes aad) {
        if ciphertext == null || nonce == null || aad == null {
            throw "Cipher.decrypt: null argument"
        }
        return cipherDecryptRaw(_algorithm, _key, _padding, ciphertext, nonce, aad)
    }

    Bool isAead() {
        return _algorithm == CipherAlgorithm.Aes128Gcm
            || _algorithm == CipherAlgorithm.Aes256Gcm
            || _algorithm == CipherAlgorithm.ChaCha20Poly1305
            || _algorithm == CipherAlgorithm.Sm4Gcm
    }

    Int keySize() { return cipherKeySizeRaw(_algorithm) }
    Int nonceSize() { return cipherNonceSizeRaw(_algorithm) }
    Int tagSize() { return cipherTagSizeRaw(_algorithm) }
    CipherAlgorithm algorithm() { return _algorithm }
}
```

> `cipher*Raw` 是运行时对称加密原语；不是 XDK 公共类型。
