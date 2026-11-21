# `PublicKey`

| 项 | 值 |
| --- | --- |
| 类型 | `class PublicKey` |
| 包 | `xdk.crypto` |
| 稳定性 | `preview` |
| 依赖 | `AsymmetricAlgorithm`、`Bytes`、`Error` |

---

## 1. 定位

非对称公钥：PEM/DER 解析、算法、编码导出。

不做：私钥、签名、证书链。

---

## 2. 设计逻辑

- 字段 `_algorithm`、`_encoded: Bytes`；构造复制。
- 公钥可导出 PEM/DER；私钥不可。
- 不可变；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_algorithm` | `AsymmetricAlgorithm` | 算法 |
| `_encoded` | `Bytes` | DER/PEM 编码 |

---

## 4. 生命周期

不可变；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `PublicKey.parsePem(String)` | pem | 非 null | `DataCorrupted` |
| `PublicKey.parseDer(Bytes)` | der | 非 null | `DataCorrupted` |

构造器私有。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `parsePem` | 解析 PEM | `String` | `Result<PublicKey, Error>` | `DataCorrupted` |
| `parseDer` | 解析 DER | `Bytes` | `Result<PublicKey, Error>` | `DataCorrupted` |
| `algorithm` | 算法 | 无 | `AsymmetricAlgorithm` | 无 |
| `der` | DER 副本 | 无 | `Bytes` | 无 |
| `pem` | PEM 文本 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 公钥解析/编码。

---

## 9. 需要的支撑

- 语言：class、String、Bytes、Result；
- 运行时：`parsePublicKeyRaw`、`parsePublicKeyDerRaw`、`formatPublicKeyPemRaw`、`PublicKeyRaw`；
- 接口：`AsymmetricAlgorithm`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`AsymmetricAlgorithm`、`Bytes`、`Error`、公钥运行时原语。

---

## 11. 所有权与并发

不可变；无资源；可共享。

---

## 12. 示例与反例

正确：`PublicKey.parsePem(pem)`。  
反例：把私钥当公钥解析；修改 der 期望 key 变化。

---

## 13. 测试/场景义务

PEM/DER；算法；往返；非法；RSA/ECC/SM2。

---

## 14. XNull 伪代码

```xnull
class PublicKey {
    final AsymmetricAlgorithm _algorithm
    final Bytes _encoded

    private PublicKey(AsymmetricAlgorithm algorithm, Bytes encoded) {
        _algorithm = algorithm
        _encoded = encoded.copy()
    }

    static Result<PublicKey, Error> parsePem(String pem) {
        if pem == null { throw "PublicKey.parsePem: null" }
        Result<PublicKeyRaw, Error> raw = parsePublicKeyRaw(pem, true)
        if raw.isErr() { return Err(raw.error()) }
        return Ok(new PublicKey(raw.value().algorithm(), raw.value().der()))
    }

    static Result<PublicKey, Error> parseDer(Bytes der) {
        if der == null { throw "PublicKey.parseDer: null" }
        Result<PublicKeyRaw, Error> raw = parsePublicKeyDerRaw(der)
        if raw.isErr() { return Err(raw.error()) }
        return Ok(new PublicKey(raw.value().algorithm(), raw.value().der()))
    }

    AsymmetricAlgorithm algorithm() { return _algorithm }
    Bytes der() { return _encoded.copy() }
    String pem() { return formatPublicKeyPemRaw(_algorithm, _encoded) }
}
```

> `PublicKeyRaw`、公钥运行时原语不是 XDK 公共类型。
