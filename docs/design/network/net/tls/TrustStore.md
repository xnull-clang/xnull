# `TrustStore`

| 项 | 值 |
| --- | --- |
| 类型 | `class TrustStore` |
| 包 | `xdk.net.tls` |
| 稳定性 | `preview` |
| 依赖 | `Certificate`、`Error` |

---

## 1. 定位

不可变信任证书集合：空库、系统快照、添加证书、PEM 添加、包含判断、长度。

不做：证书链验证、CRL/OCSP、可变全局信任库、私钥。

---

## 2. 设计逻辑

- 字段 `_certificates: List<Certificate>`；构造/派生复制。
- `system()` 返回运行时系统信任库快照；之后不受系统变化影响。
- `withCertificate`/`withPem` 返回新实例，不修改原库。
- `contains` 按 DER 字节比较。
- 不可变；无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_certificates` | `List<Certificate>` | 证书列表 |

不变量：列表非 null；元素非 null；不可变。

---

## 4. 生命周期

构造/派生后不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TrustStore()` | 无 | 空库 | 无 |
| `TrustStore.system()` | 无 | 系统库可用 | `Unavailable`（实现/平台） |
| `TrustStore.withPem(String pem)` | pem | 非 null | `DataCorrupted` |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `system` | 系统信任快照 | 无 | `Result<TrustStore, Error>` | `Unavailable` |
| `withCertificate` | 派生添加 | `Certificate certificate` | `TrustStore` | null → panic |
| `withPem` | 解析并添加 | `String pem` | `Result<TrustStore, Error>` | `DataCorrupted` |
| `contains` | 是否包含 | `Certificate certificate` | `Bool` | 无 |
| `length` | 证书数 | 无 | `Int` | 无 |
| `certificates` | 快照 | 无 | `List<Certificate>` | 无 |

---

## 8. 使用的技术

- 不可变集合；
- DER 相等；
- 系统信任库快照。

---

## 9. 需要的支撑

- 语言：class、List、Bool、Int、Result；
- 运行时：`systemTrustStoreRaw`；
- 接口：`Certificate`、`Error`、`equals`。

---

## 10. 依赖的特性/接口/类

`Certificate`、`Error`、`systemTrustStoreRaw`、`equals`。

---

## 11. 所有权与并发

不可变；`certificates()` 返回副本；无资源；可共享。

---

## 12. 示例与反例

正确：`TrustStore.system()`；`store.withPem(caPem)`。  
反例：修改原库期望新配置变化；把系统库当实时视图；用 subject 字符串判等。

---

## 13. 测试/场景义务

空库；系统库；添加；PEM；重复证书；contains；长度；快照独立；非法 PEM。

---

## 14. XNull 伪代码

```xnull
class TrustStore {
    final List<Certificate> _certificates

    TrustStore() {
        _certificates = []
    }

    private TrustStore(List<Certificate> certificates) {
        _certificates = certificates.copy()
    }

    static Result<TrustStore, Error> system() {
        Result<List<Certificate>, Error> certificates = systemTrustStoreRaw()
        if certificates.isErr() { return Err(certificates.error()) }
        return Ok(new TrustStore(certificates.value()))
    }

    TrustStore withCertificate(Certificate certificate) {
        if certificate == null { throw "TrustStore.withCertificate: null" }
        List<Certificate> next = _certificates.copy()
        next.push(certificate)
        return new TrustStore(next)
    }

    Result<TrustStore, Error> withPem(String pem) {
        Result<Certificate, Error> certificate = Certificate.parsePem(pem)
        if certificate.isErr() { return Err(certificate.error()) }
        return Ok(self.withCertificate(certificate.value()))
    }

    Bool contains(Certificate certificate) {
        if certificate == null { return false }
        Bytes target = certificate.der()
        Int index = 0
        while index < _certificates.length() {
            if equals(_certificates.get(index).der(), target) {
                return true
            }
            index = index + 1
        }
        return false
    }

    Int length() { return _certificates.length() }
    List<Certificate> certificates() { return _certificates.copy() }
}
```

> `systemTrustStoreRaw` 是运行时信任库原语；不是 XDK 公共类型。
