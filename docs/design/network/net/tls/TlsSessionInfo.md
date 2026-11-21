# `TlsSessionInfo`

| 项 | 值 |
| --- | --- |
| 类型 | `class TlsSessionInfo` |
| 包 | `xdk.net.tls` |
| 稳定性 | `preview` |
| 依赖 | `TlsVersion`、`Certificate` |

---

## 1. 定位

TLS 握手协商结果：版本、密码套件、SNI、对端证书、是否恢复。

不做：会话缓存管理、证书链、ALPN 协商（X）、密钥材料。

---

## 2. 设计逻辑

- 字段不可变：version/cipherSuite/serverName/peerCertificate/isResumed。
- 由 `TlsStream` 握手成功后提供；业务代码不直接构造。
- `peerCertificate` 可空（某些服务端/匿名模式）；不提供私钥。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_version` | `TlsVersion` | 协商版本 |
| `_cipherSuite` | `String` | 套件名 |
| `_serverName` | `String` | SNI |
| `_alpnProtocol` | `String?` | 协商 ALPN；未协商 → null |
| `_peerCertificate` | `Certificate?` | 对端证书 |
| `_isResumed` | `Bool` | 是否恢复 |

不变量：version/cipherSuite/serverName 非 null；不可变。

---

## 4. 生命周期

握手后创建；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TlsSessionInfo(...)` | 见 §6 | 非 null | null → panic |

主要供 TLS 运行时/`TlsStream` 使用。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `version` | 版本 | 无 | `TlsVersion` | 无 |
| `cipherSuite` | 套件 | 无 | `String` | 无 |
| `serverName` | SNI | 无 | `String` | 无 |
| `alpnProtocol` | 协商 ALPN/无 | 无 | `String?` | 无 |
| `peerCertificate` | 对端证书/无 | 无 | `Certificate?` | 无 |
| `isResumed` | 是否恢复 | 无 | `Bool` | 无 |
| `toString` | 摘要 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 不可变快照；
- 协商信息。

---

## 9. 需要的支撑

- 语言：class、String、Bool；
- 运行时：握手结果；
- 接口：`TlsVersion`、`Certificate`、`tlsVersionName`。

---

## 10. 依赖的特性/接口/类

`TlsVersion`、`Certificate`、`tlsVersionName`。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`stream.sessionInfo().version()`；`alpnProtocol()`。  
反例：从 session 取私钥；修改 session 期望连接变化；把 resumed 当安全保证。

---

## 13. 测试/场景义务

版本；套件；SNI；ALPN 可空；对端证书可空；resumed；toString 不含秘密。

---

## 14. XNull 伪代码

```xnull
class TlsSessionInfo {
    final TlsVersion _version
    final String _cipherSuite
    final String _serverName
    final String? _alpnProtocol
    final Certificate? _peerCertificate
    final Bool _isResumed

    TlsSessionInfo(TlsVersion version, String cipherSuite, String serverName,
                   String? alpnProtocol, Certificate? peerCertificate, Bool isResumed) {
        if cipherSuite == null || serverName == null {
            throw "TlsSessionInfo: null argument"
        }
        _version = version
        _cipherSuite = cipherSuite
        _serverName = serverName
        _alpnProtocol = alpnProtocol
        _peerCertificate = peerCertificate
        _isResumed = isResumed
    }

    TlsVersion version() { return _version }
    String cipherSuite() { return _cipherSuite }
    String serverName() { return _serverName }
    String? alpnProtocol() { return _alpnProtocol }
    Certificate? peerCertificate() { return _peerCertificate }
    Bool isResumed() { return _isResumed }

    String toString() {
        return "tls-session(" + tlsVersionName(_version) + "," + _cipherSuite + ")"
    }
}
```
