# `PrivateKey`

| 项 | 值 |
| --- | --- |
| 类型 | `class PrivateKey` |
| 包 | `xdk.crypto` |
| 稳定性 | `preview` |
| 依赖 | `AsymmetricAlgorithm`、`Error` |

---

## 1. 定位

非对称私钥句柄：PEM 解析、算法；不导出私钥材料。

不做：公钥编码、签名执行、密钥库。

---

## 2. 设计逻辑

- 字段 `_algorithm`、`_handle: CryptoKeyHandle`。
- `parsePem` 调用运行时私钥解析；不提供 `bytes/der/pem`。
- `toString` 只显示算法。
- 不可变；无 close；运行时管理。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_algorithm` | `AsymmetricAlgorithm` | 算法 |
| `_handle` | `CryptoKeyHandle` | 私钥句柄 |

---

## 4. 生命周期

不可变；无 close；可共享给签名/解密。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `PrivateKey.parsePem(String)` | pem | 非 null | `DataCorrupted` |

构造器私有。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `parsePem` | 解析 | `String` | `Result<PrivateKey, Error>` | `DataCorrupted` |
| `algorithm` | 算法 | 无 | `AsymmetricAlgorithm` | 无 |
| `toString` | 安全摘要 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 私钥句柄；
- 安全摘要。

---

## 9. 需要的支撑

- 语言：class、String、Result；
- 运行时：`parsePrivateKeyRaw`、`CryptoKeyHandle`、`PrivateKeyRaw`；
- 接口：`AsymmetricAlgorithm`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`AsymmetricAlgorithm`、`Error`、私钥运行时原语。

---

## 11. 所有权与并发

不可变；不导出；可共享；无公开 close。

---

## 12. 示例与反例

正确：`PrivateKey.parsePem(pem)`。  
反例：打印私钥；提供 bytes；写入日志。

---

## 13. 测试/场景义务

PEM 成功/失败；算法；toString 不含密钥；RSA/ECC/SM2。

---

## 14. XNull 伪代码

```xnull
class PrivateKey {
    final AsymmetricAlgorithm _algorithm
    final CryptoKeyHandle _handle

    private PrivateKey(AsymmetricAlgorithm algorithm, CryptoKeyHandle handle) {
        _algorithm = algorithm
        _handle = handle
    }

    static Result<PrivateKey, Error> parsePem(String pem) {
        if pem == null { throw "PrivateKey.parsePem: null" }
        Result<PrivateKeyRaw, Error> raw = parsePrivateKeyRaw(pem)
        if raw.isErr() { return Err(raw.error()) }
        return Ok(new PrivateKey(raw.value().algorithm(), raw.value().handle()))
    }

    AsymmetricAlgorithm algorithm() { return _algorithm }
    String toString() { return "private-key(" + str(_algorithm) + ")" }
}
```

> `PrivateKeyRaw`、`CryptoKeyHandle` 是运行时私钥原语；不是 XDK 公共类型。
