# `TlsConfig`

| 项 | 值 |
| --- | --- |
| 类型 | `class TlsConfig` |
| 包 | `xdk.net.tls` |
| 稳定性 | `preview` |
| 依赖 | `TlsVersion`、`Certificate`、`PrivateKey`、`TrustStore` |

---

## 1. 定位

不可变 TLS 配置：SNI、信任库、服务端/客户端证书、版本范围、ALPN、对端校验开关。

不做：会话缓存、cipher suite/curve 列表、CRL/OCSP、客户端认证策略、裸 TLS 上下文。

---

## 2. 设计逻辑

- 字段全部不可变；`with*` 返回新配置。
- 默认 `verifyPeer=true`；未设置 trustStore 时使用系统信任库快照。
- 客户端必须设置 `serverName` 才会做 SNI/主机名校验（由 `TlsStream.connect` 检查）。
- 服务端必须设置 `serverCertificate` + `serverKey`（由 `TlsStream.accept` 检查）。
- 客户端证书用于 mTLS；服务端是否要求由 X 策略控制。
- ALPN 列表复制；空列表表示不提供 ALPN。
- 无 close；可跨任务共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_serverName` | `String?` | SNI/主机名 |
| `_trustStore` | `TrustStore?` | null → 系统库 |
| `_serverCertificate` | `Certificate?` | 服务端证书 |
| `_serverKey` | `PrivateKey?` | 服务端私钥 |
| `_clientCertificate` | `Certificate?` | 客户端证书 |
| `_clientKey` | `PrivateKey?` | 客户端私钥 |
| `_minVersion` | `TlsVersion?` | 最低版本 |
| `_maxVersion` | `TlsVersion?` | 最高版本 |
| `_alpn` | `List<String>` | ALPN 协议 |
| `_verifyPeer` | `Bool` | 是否验证对端 |

不变量：服务端证书/私钥成对设置；客户端证书/私钥成对；ALPN 无空串；不可变。

---

## 4. 生命周期

构造/派生后不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TlsConfig()` | 无 | 默认验证、系统信任 | 无 |

派生方法对 null/空关键参数 panic；握手时再校验组合。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `serverName` | SNI | 无 | `String?` | 无 |
| `trustStore` | 信任库 | 无 | `TrustStore?` | 无 |
| `serverCertificate` | 服务端证书 | 无 | `Certificate?` | 无 |
| `serverKey` | 服务端私钥 | 无 | `PrivateKey?` | 无 |
| `clientCertificate` | 客户端证书 | 无 | `Certificate?` | 无 |
| `clientKey` | 客户端私钥 | 无 | `PrivateKey?` | 无 |
| `minVersion` | 最低版本 | 无 | `TlsVersion?` | 无 |
| `maxVersion` | 最高版本 | 无 | `TlsVersion?` | 无 |
| `alpn` | ALPN 快照 | 无 | `List<String>` | 无 |
| `verifyPeer` | 是否验证 | 无 | `Bool` | 无 |
| `withServerName` | 派生 SNI | `String value` | `TlsConfig` | 空/null → panic |
| `withTrustStore` | 派生信任库 | `TrustStore value` | `TlsConfig` | null → panic |
| `withServerCertificate` | 派生服务端证书 | `Certificate certificate, PrivateKey key` | `TlsConfig` | null → panic |
| `withClientCertificate` | 派生客户端证书 | `Certificate certificate, PrivateKey key` | `TlsConfig` | null → panic |
| `withMinVersion` | 派生最低版本 | `TlsVersion value` | `TlsConfig` | 无 |
| `withMaxVersion` | 派生最高版本 | `TlsVersion value` | `TlsConfig` | 无 |
| `withAlpn` | 派生 ALPN | `List<String> protocols` | `TlsConfig` | null/空串 → panic |
| `withoutAlpn` | 清空 ALPN | 无 | `TlsConfig` | 无 |
| `withVerifyPeer` | 派生验证开关 | `Bool value` | `TlsConfig` | 无 |
| `toString` | 安全摘要 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 不可变配置；
- 证书/私钥组合；
- ALPN；
- 安全摘要。

---

## 9. 需要的支撑

- 语言：class、List、String、Bool、Result；
- 运行时：无（握手时由 TLS 原语读取）；
- 接口：`TlsVersion`、`Certificate`、`PrivateKey`、`TrustStore`。

---

## 10. 依赖的特性/接口/类

`TlsVersion`、`Certificate`、`PrivateKey`、`TrustStore`。

---

## 11. 所有权与并发

不可变；证书/私钥/信任库引用；ALPN 副本；可共享。

---

## 12. 示例与反例

正确：`new TlsConfig().withServerName("example.com")`。  
反例：客户端不设 serverName；服务端缺私钥；`withVerifyPeer(false)` 用于生产；把私钥写进 toString。

---

## 13. 测试/场景义务

默认值；with* 独立性；ALPN 副本；证书/私钥成对；版本范围；verifyPeer；安全 toString。

---

## 14. XNull 伪代码

```xnull
class TlsConfig {
    final String? _serverName
    final TrustStore? _trustStore
    final Certificate? _serverCertificate
    final PrivateKey? _serverKey
    final Certificate? _clientCertificate
    final PrivateKey? _clientKey
    final TlsVersion? _minVersion
    final TlsVersion? _maxVersion
    final List<String> _alpn
    final Bool _verifyPeer

    TlsConfig() {
        _serverName = null
        _trustStore = null
        _serverCertificate = null
        _serverKey = null
        _clientCertificate = null
        _clientKey = null
        _minVersion = null
        _maxVersion = null
        _alpn = []
        _verifyPeer = true
    }

    private TlsConfig(String? serverName, TrustStore? trustStore,
                      Certificate? serverCertificate, PrivateKey? serverKey,
                      Certificate? clientCertificate, PrivateKey? clientKey,
                      TlsVersion? minVersion, TlsVersion? maxVersion,
                      List<String> alpn, Bool verifyPeer) {
        _serverName = serverName
        _trustStore = trustStore
        _serverCertificate = serverCertificate
        _serverKey = serverKey
        _clientCertificate = clientCertificate
        _clientKey = clientKey
        _minVersion = minVersion
        _maxVersion = maxVersion
        _alpn = alpn.copy()
        _verifyPeer = verifyPeer
    }

    String? serverName() { return _serverName }
    TrustStore? trustStore() { return _trustStore }
    Certificate? serverCertificate() { return _serverCertificate }
    PrivateKey? serverKey() { return _serverKey }
    Certificate? clientCertificate() { return _clientCertificate }
    PrivateKey? clientKey() { return _clientKey }
    TlsVersion? minVersion() { return _minVersion }
    TlsVersion? maxVersion() { return _maxVersion }
    List<String> alpn() { return _alpn.copy() }
    Bool verifyPeer() { return _verifyPeer }

    TlsConfig withServerName(String value) {
        if value == null || value == "" {
            throw "TlsConfig.withServerName: empty value"
        }
        return new TlsConfig(value, _trustStore, _serverCertificate, _serverKey,
            _clientCertificate, _clientKey, _minVersion, _maxVersion, _alpn, _verifyPeer)
    }

    TlsConfig withTrustStore(TrustStore value) {
        if value == null { throw "TlsConfig.withTrustStore: null" }
        return new TlsConfig(_serverName, value, _serverCertificate, _serverKey,
            _clientCertificate, _clientKey, _minVersion, _maxVersion, _alpn, _verifyPeer)
    }

    TlsConfig withServerCertificate(Certificate certificate, PrivateKey key) {
        if certificate == null || key == null {
            throw "TlsConfig.withServerCertificate: null"
        }
        return new TlsConfig(_serverName, _trustStore, certificate, key,
            _clientCertificate, _clientKey, _minVersion, _maxVersion, _alpn, _verifyPeer)
    }

    TlsConfig withClientCertificate(Certificate certificate, PrivateKey key) {
        if certificate == null || key == null {
            throw "TlsConfig.withClientCertificate: null"
        }
        return new TlsConfig(_serverName, _trustStore, _serverCertificate, _serverKey,
            certificate, key, _minVersion, _maxVersion, _alpn, _verifyPeer)
    }

    TlsConfig withMinVersion(TlsVersion value) {
        return new TlsConfig(_serverName, _trustStore, _serverCertificate, _serverKey,
            _clientCertificate, _clientKey, value, _maxVersion, _alpn, _verifyPeer)
    }

    TlsConfig withMaxVersion(TlsVersion value) {
        return new TlsConfig(_serverName, _trustStore, _serverCertificate, _serverKey,
            _clientCertificate, _clientKey, _minVersion, value, _alpn, _verifyPeer)
    }

    TlsConfig withAlpn(List<String> protocols) {
        if protocols == null { throw "TlsConfig.withAlpn: null" }
        Int index = 0
        while index < protocols.length() {
            if protocols.get(index) == null || protocols.get(index) == "" {
                throw "TlsConfig.withAlpn: invalid protocol"
            }
            index = index + 1
        }
        return new TlsConfig(_serverName, _trustStore, _serverCertificate, _serverKey,
            _clientCertificate, _clientKey, _minVersion, _maxVersion, protocols, _verifyPeer)
    }

    TlsConfig withoutAlpn() {
        return new TlsConfig(_serverName, _trustStore, _serverCertificate, _serverKey,
            _clientCertificate, _clientKey, _minVersion, _maxVersion, [], _verifyPeer)
    }

    TlsConfig withVerifyPeer(Bool value) {
        return new TlsConfig(_serverName, _trustStore, _serverCertificate, _serverKey,
            _clientCertificate, _clientKey, _minVersion, _maxVersion, _alpn, value)
    }

    String toString() {
        if _serverName == null { return "tls-config" }
        return "tls-config(" + _serverName + ")"
    }
}
```
