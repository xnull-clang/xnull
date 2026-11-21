# `Capability`

| 项 | 值 |
| --- | --- |
| 类型 | `enum Capability` |
| 包 | `xdk.meta` |
| 稳定性 | `stable` |
| 依赖 | 无 |

---

## 1. 定位

目标平台/构建支持的能力标记，用于条件诊断、功能开关和客户端/服务器画像；不是运行时权限。

---

## 2. 设计逻辑

- 能力集合固定、可追加；不由应用扩展。
- `TargetInfo` 持有能力列表；`meta.hasCapability` 查询。
- 能力表示“构建目标支持”，不等于“当前进程一定可用”；运行时失败仍按 `Unsupported`/`Network` 处理。

---

## 3. 表示与不变量

| 成员 | 含义 |
| --- | --- |
| `Threads` | 支持线程/任务 |
| `Network` | 支持网络 |
| `Tls` | 支持 TLS |
| `Filesystem` | 支持文件系统 |
| `Process` | 支持子进程 |
| `Signals` | 支持信号 |
| `Unicode` | 支持 Unicode 文本 |
| `Regex` | 支持正则 |
| `Compression` | 支持压缩 |
| `Crypto` | 支持加密 |
| `Random` | 支持随机 |
| `DynamicLibrary` | 支持动态库 |
| `NetworkClient` | 支持出站网络 |
| `NetworkServer` | 支持入站监听 |
| `TlsClient` | 支持 TLS 客户端 |
| `TlsServer` | 支持 TLS 服务端 |
| `HttpClient` | 支持 HTTP 客户端 |
| `HttpServer` | 支持 HTTP 服务端 |
| `WebSocketClient` | 支持 WebSocket 客户端 |
| `WebSocketServer` | 支持 WebSocket 服务端 |
| `DnsResolver` | 支持 DNS 解析 |
| `ProxyClient` | 支持出站代理/CONNECT |
| `ProxyServer` | 支持入站代理 |
| `CookieStore` | 支持 Cookie 存储 |
| `Pty` | 支持伪终端 |
| `FileWatch` | 支持文件变更监听 |
| `Locale` | 支持区域/本地化 |
| `TimeZoneDatabase` | 支持 IANA 时区库 |
| `SecureRandom` | 支持安全随机源 |
| `ProcessSupervision` | 支持进程监督/回收 |
| `Stdio` | 支持标准流 |
| `Multicore` | 支持多核并行 |

不变量：成员固定；只允许追加；已有序号不得改变；值语义；可作 Map 键。

---

## 4. 生命周期

值类型；无 close；可共享。

---

## 5. 构造契约

枚举成员直接使用，无构造器。

---

## 6. 字段表

无实例字段。

---

## 7. 方法面

`Capability` 没有实例方法。名称/查询由 `xdk.meta` 顶层函数提供：

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `capabilityName` | 稳定名称 | `Capability capability` | `String` | 无 |
| `capabilityFromName` | 名称解析（大小写不敏感） | `String name` | `Capability?` | 无；未知返回 null |
| `hasCapability` | 目标是否支持 | `Capability capability` | `Bool` | 无 |

---

## 8. 使用的技术

- 枚举；
- 能力列表线性查询；
- 字符串名称映射。

---

## 9. 需要的支撑

- 语言：enum、String、Bool、List；
- 运行时：无；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

值语义；可共享；无资源。

---

## 12. 示例与反例

正确：`hasCapability(Capability.Tls)` 决定是否启用 TLS 路径。  
反例：把目标能力当运行时探测；用能力替代错误处理；应用自定义能力。

---

## 13. 测试/场景义务

每个成员名称；目标能力查询；未知/不支持路径。

---

## 14. XNull 伪代码

```xnull
enum Capability {
    Threads,
    Network,
    Tls,
    Filesystem,
    Process,
    Signals,
    Unicode,
    Regex,
    Compression,
    Crypto,
    Random,
    DynamicLibrary,
}

String capabilityName(Capability capability) {
    if capability == Capability.Threads { return "threads" }
    if capability == Capability.Network { return "network" }
    if capability == Capability.Tls { return "tls" }
    if capability == Capability.Filesystem { return "filesystem" }
    if capability == Capability.Process { return "process" }
    if capability == Capability.Signals { return "signals" }
    if capability == Capability.Unicode { return "unicode" }
    if capability == Capability.Regex { return "regex" }
    if capability == Capability.Compression { return "compression" }
    if capability == Capability.Crypto { return "crypto" }
    if capability == Capability.Random { return "random" }
    if capability == Capability.DynamicLibrary { return "dynamic_library" }
    if capability == Capability.NetworkClient { return "network_client" }
    if capability == Capability.NetworkServer { return "network_server" }
    if capability == Capability.TlsClient { return "tls_client" }
    if capability == Capability.TlsServer { return "tls_server" }
    if capability == Capability.HttpClient { return "http_client" }
    if capability == Capability.HttpServer { return "http_server" }
    if capability == Capability.WebSocketClient { return "websocket_client" }
    if capability == Capability.WebSocketServer { return "websocket_server" }
    if capability == Capability.DnsResolver { return "dns_resolver" }
    if capability == Capability.ProxyClient { return "proxy_client" }
    if capability == Capability.ProxyServer { return "proxy_server" }
    if capability == Capability.CookieStore { return "cookie_store" }
    if capability == Capability.Pty { return "pty" }
    if capability == Capability.FileWatch { return "file_watch" }
    if capability == Capability.Locale { return "locale" }
    if capability == Capability.TimeZoneDatabase { return "timezone_database" }
    if capability == Capability.SecureRandom { return "secure_random" }
    if capability == Capability.ProcessSupervision { return "process_supervision" }
    if capability == Capability.Stdio { return "stdio" }
    if capability == Capability.Multicore { return "multicore" }
    return "unknown"
}

Capability? capabilityFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "threads" { return Capability.Threads }
    if normalized == "network" { return Capability.Network }
    if normalized == "tls" { return Capability.Tls }
    if normalized == "filesystem" { return Capability.Filesystem }
    if normalized == "process" { return Capability.Process }
    if normalized == "signals" { return Capability.Signals }
    if normalized == "unicode" { return Capability.Unicode }
    if normalized == "regex" { return Capability.Regex }
    if normalized == "compression" { return Capability.Compression }
    if normalized == "crypto" { return Capability.Crypto }
    if normalized == "random" { return Capability.Random }
    if normalized == "dynamic_library" { return Capability.DynamicLibrary }
    if normalized == "network_client" { return Capability.NetworkClient }
    if normalized == "network_server" { return Capability.NetworkServer }
    if normalized == "tls_client" { return Capability.TlsClient }
    if normalized == "tls_server" { return Capability.TlsServer }
    if normalized == "http_client" { return Capability.HttpClient }
    if normalized == "http_server" { return Capability.HttpServer }
    if normalized == "websocket_client" { return Capability.WebSocketClient }
    if normalized == "websocket_server" { return Capability.WebSocketServer }
    if normalized == "dns_resolver" { return Capability.DnsResolver }
    if normalized == "proxy_client" { return Capability.ProxyClient }
    if normalized == "proxy_server" { return Capability.ProxyServer }
    if normalized == "cookie_store" { return Capability.CookieStore }
    if normalized == "pty" { return Capability.Pty }
    if normalized == "file_watch" { return Capability.FileWatch }
    if normalized == "locale" { return Capability.Locale }
    if normalized == "timezone_database" { return Capability.TimeZoneDatabase }
    if normalized == "secure_random" { return Capability.SecureRandom }
    if normalized == "process_supervision" { return Capability.ProcessSupervision }
    if normalized == "stdio" { return Capability.Stdio }
    if normalized == "multicore" { return Capability.Multicore }
    return null
}
```
