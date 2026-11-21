# `Certificate`

| 项 | 值 |
| --- | --- |
| 类型 | `class Certificate` |
| 包 | `xdk.net.tls` |
| 稳定性 | `preview` |
| 依赖 | `Bytes`、`Error` |

---

## 1. 定位

不可变 X.509 证书：PEM/DER 解析、主题/颁发者、有效期、DER/指纹只读访问。

不做：私钥、签名验证、证书链构建、CRL/OCSP、生成/签发证书。

---

## 2. 设计逻辑

- 字段 `_der`、`_subject`、`_issuer`、`_notBeforeMillis`、`_notAfterMillis`、`_fingerprintSha256`。
- `parsePem`/`parseDer` 调用运行时证书解析；失败 `DataCorrupted`。
- `der()` 返回副本；证书可公开。
- 不可变；无 close；可共享。
- 时间字段为 epoch 毫秒。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_der` | `Bytes` | DER 副本 |
| `_subject` | `String` | 主题 |
| `_issuer` | `String` | 颁发者 |
| `_notBeforeMillis` | `Long` | 生效 |
| `_notAfterMillis` | `Long` | 过期 |
| `_fingerprintSha256` | `String` | SHA-256 指纹 |

不变量：DER 非空；subject/issuer 单行；notBefore ≤ notAfter；不可变。

---

## 4. 生命周期

解析后不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Certificate.parsePem(String pem)` | pem | 非 null | `DataCorrupted` |
| `Certificate.parseDer(Bytes der)` | der | 非 null | `DataCorrupted` |

构造器私有。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `parsePem` | 解析 PEM | `String pem` | `Result<Certificate, Error>` | `DataCorrupted` |
| `parseDer` | 解析 DER | `Bytes der` | `Result<Certificate, Error>` | `DataCorrupted` |
| `subject` | 主题 | 无 | `String` | 无 |
| `issuer` | 颁发者 | 无 | `String` | 无 |
| `notBeforeMillis` | 生效时间 | 无 | `Long` | 无 |
| `notAfterMillis` | 过期时间 | 无 | `Long` | 无 |
| `der` | DER 副本 | 无 | `Bytes` | 无 |
| `fingerprintSha256` | 指纹 | 无 | `String` | 无 |
| `toString` | 主题文本 | 无 | `String` | 无 |

---

## 8. 使用的技术

- X.509/PEM/DER；
- 证书属性解析；
- 指纹；
- 不可变值对象。

---

## 9. 需要的支撑

- 语言：class、String、Long、Bytes、Result；
- 运行时：`parseCertificatePemRaw`、`parseCertificateDerRaw`、`CertificateRaw`、指纹原语；
- 接口：`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Bytes`、`Error`、`BasicError`、`ErrorKind`、证书解析原语。

---

## 11. 所有权与并发

不可变；`der()` 返回副本；无资源；可共享。

---

## 12. 示例与反例

正确：`Certificate.parsePem(pem)`；`cert.subject()`。  
反例：从 Certificate 取私钥；修改 `der()` 期望证书变化；把过期时间当毫秒/秒混用。

---

## 13. 测试/场景义务

PEM/DER；非法数据；subject/issuer；时间；DER 往返；指纹格式；不可变性。

---

## 14. XNull 伪代码

```xnull
class Certificate {
    final Bytes _der
    final String _subject
    final String _issuer
    final Long _notBeforeMillis
    final Long _notAfterMillis
    final String _fingerprintSha256

    private Certificate(Bytes der, String subject, String issuer,
                        Long notBeforeMillis, Long notAfterMillis, String fingerprintSha256) {
        _der = der.copy()
        _subject = subject
        _issuer = issuer
        _notBeforeMillis = notBeforeMillis
        _notAfterMillis = notAfterMillis
        _fingerprintSha256 = fingerprintSha256
    }

    static Result<Certificate, Error> parsePem(String pem) {
        if pem == null { throw "Certificate.parsePem: null pem" }
        Result<CertificateRaw, Error> raw = parseCertificatePemRaw(pem)
        if raw.isErr() { return Err(raw.error()) }
        CertificateRaw value = raw.value()
        return Ok(new Certificate(
            value.der(), value.subject(), value.issuer(),
            value.notBeforeMillis(), value.notAfterMillis(), value.fingerprintSha256()))
    }

    static Result<Certificate, Error> parseDer(Bytes der) {
        if der == null { throw "Certificate.parseDer: null der" }
        Result<CertificateRaw, Error> raw = parseCertificateDerRaw(der)
        if raw.isErr() { return Err(raw.error()) }
        CertificateRaw value = raw.value()
        return Ok(new Certificate(
            value.der(), value.subject(), value.issuer(),
            value.notBeforeMillis(), value.notAfterMillis(), value.fingerprintSha256()))
    }

    String subject() { return _subject }
    String issuer() { return _issuer }
    Long notBeforeMillis() { return _notBeforeMillis }
    Long notAfterMillis() { return _notAfterMillis }
    Bytes der() { return _der.copy() }
    String fingerprintSha256() { return _fingerprintSha256 }

    String toString() { return _subject }
}
```

> `CertificateRaw`、`parseCertificatePemRaw`、`parseCertificateDerRaw` 是运行时证书原语；不是 XDK 公共类型。
