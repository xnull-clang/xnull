# `xdk.net.tls` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.net.tls` |
| 层 | `xdk.net` / L5 |
| 依赖 | `xdk.errors`、`xdk.bytes`、`xdk.execution`、`xdk.net` |
| 被依赖 | `net.http`、`net.websocket` |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

`xdk.net.tls` 提供 TLS 配置、证书、私钥、信任库、TLS 流和协商信息：

- `TlsVersion`：TLS 1.2/1.3；
- `Certificate` / `PrivateKey`：证书/私钥解析与只读属性；
- `TrustStore`：不可变信任库；
- `TlsConfig`：客户端/服务端配置；
- `TlsStream`：在 `ByteStream` 上做 TLS；
- `TlsServer`/`TlsClient` + `TlsHandler`：TLS 服务端/客户端角色；
- `TlsSessionInfo`：协商结果。

不做：密码学原语、密钥生成、CA 服务、OCSP/CRL、HTTP、WebSocket、TLS 1.0/1.1、裸 TLS 上下文。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 不导出私钥 | `PrivateKey` 不提供 `bytes/der`；不得进入日志/错误 |
| 默认验证对端 | `TlsConfig` 默认 `verifyPeer=true` |
| 流所有权明确 | 成功握手后 `TlsStream` 拥有底层流；失败时调用方关闭 |
| Context 可取消 | 握手/读写/截止均接受 `Context` |
| 关闭幂等 | `TlsStream.close` 幂等并关闭底层流 |
| 无全局状态 | 无全局信任库修改、无全局会话缓存 |
| 显式配置 | 证书/私钥/ALPN/版本全部显式设置 |
| 安全失败 | 验签失败 `PermissionDenied`；握手数据损坏 `DataCorrupted` |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `TlsVersion` | enum | TLS 1.2/1.3 | [`TlsVersion.md`](TlsVersion.md) |
| `Certificate` | class | X.509 只读证书 | [`Certificate.md`](Certificate.md) |
| `PrivateKey` | class | 私钥句柄/属性 | [`PrivateKey.md`](PrivateKey.md) |
| `TrustStore` | class | 不可变信任库 | [`TrustStore.md`](TrustStore.md) |
| `TlsConfig` | class | 不可变 TLS 配置 | [`TlsConfig.md`](TlsConfig.md) |
| `TlsStream` | class | TLS 字节流 | [`TlsStream.md`](TlsStream.md) |
| `TlsHandler` | protocol | 服务端连接处理 | [`TlsHandler.md`](TlsHandler.md) |
| `TlsServer` | class | TLS 服务端角色 | [`TlsServer.md`](TlsServer.md) |
| `TlsClient` | class | TLS 客户端角色 | [`TlsClient.md`](TlsClient.md) |
| `TlsSessionInfo` | class | 协商信息 | [`TlsSessionInfo.md`](TlsSessionInfo.md) |

X 未纳入本批：`CertificateChain`、`ClientAuthMode`、自定义校验策略、CRL/OCSP、会话缓存、cipher suite/curve 配置、TLS 1.0/1.1、QUIC。

---

## 4. 顶层函数

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `tlsVersionName` | 稳定版本名 | `TlsVersion version` | `String` | 无 |

```xnull
String tlsVersionName(TlsVersion version) {
    if version == TlsVersion.Tls12 { return "tls1.2" }
    return "tls1.3"
}
```

---

## 5. 技术/支撑/依赖

- 技术：X.509/PEM/DER、TLS 1.2/1.3 握手、SNI、ALPN、mTLS、证书校验、流封装。
- 支撑：`TlsHandle`、`tls*Raw` 运行时原语、证书/私钥解析原语、系统信任库原语。
- 依赖：`xdk.errors`、`xdk.bytes`、`xdk.execution`、`xdk.net`。

---

## 6. 场景

### S2：TLS 客户端

`TcpStream.connect` → `TlsConfig().withServerName("example.com")` → `TlsStream.connect(ctx, tcp, config)` → 读写 → close。

### S3：TLS 服务端

`TcpListener` → `TlsConfig().withServerCertificate(cert,key)` → `TlsStream.accept(ctx,tcp,config)`。

### S4：mTLS

客户端 `withClientCertificate`；服务端要求客户端证书（X 策略），K 只提供证书配置。

### S5：ALPN

`withAlpn(["h2","http/1.1"])`；`sessionInfo().alpnProtocol()` 读取协商结果。

### S5：证书检查

`Certificate.parsePem`；读取 subject/issuer/有效期/指纹；不导出私钥。

### S6：验签失败

错误证书 → `PermissionDenied`；握手数据损坏 → `DataCorrupted`；底层流由调用方关闭。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 私钥导出 | 禁止 |
| 默认信任库 | `TlsConfig` 未设置时使用运行时系统信任库快照 |
| 信任库可变性 | `TrustStore` 不可变；`with*` 派生 |
| 握手失败 | `TlsStream` 不创建；调用方关闭 transport |
| 关闭顺序 | `TlsStream.close` 关闭 TLS 句柄 + 底层流 |
| 证书校验 | 默认开启；可显式关闭（危险） |
| SNI | 客户端必须设置 `serverName` |
| 服务端证书 | `accept` 必须配置证书/私钥 |
| 会话缓存 | X |
| 证书链/CRL/OCSP | X |
| HTTP/WebSocket | L6 |
