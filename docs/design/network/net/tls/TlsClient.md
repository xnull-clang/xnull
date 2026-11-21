# `TlsClient`

| 项 | 值 |
| --- | --- |
| 类型 | `class TlsClient` |
| 包 | `xdk.net.tls` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`SocketAddress`、`TcpStream`、`TlsStream`、`TlsConfig`、`SocketOptions`、`Error` |

---

## 1. 定位

TLS 客户端角色：TCP 连接 + TLS 握手，返回 `TlsStream`。

不做：自动重连、连接池、HTTP、证书管理。

---

## 2. 设计逻辑

- 字段 `_tlsConfig`、`_socketOptions`。
- `connect(SocketAddress)` 要求 config.serverName 非空。
- `connect(host,port)` 自动补 serverName。
- 握手失败关闭 TCP；成功返回 TlsStream 所有权。
- 无 close；无资源。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_tlsConfig` | `TlsConfig` | TLS 配置 |
| `_socketOptions` | `SocketOptions` | TCP 选项 |

---

## 4. 生命周期

构造后复用；无 close；流由调用方 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TlsClient(TlsConfig config)` | config | 非 null | null → panic |
| `TlsClient(TlsConfig config, SocketOptions options)` | + options | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `connect` | 连接地址 | `Context, SocketAddress` | `Result<TlsStream, Error>` | `InvalidArgument`/`Network`/`PermissionDenied`/`Timeout`/`Cancelled` |
| `connect` | DNS + TLS | `Context, String, Int` | `Result<TlsStream, Error>` | 同上 + `NotFound` |
| `config` | 配置快照 | 无 | `TlsConfig` | 无 |

---

## 8. 使用的技术

- TCP + TLS；
- SNI；
- 失败清理。

---

## 9. 需要的支撑

- 语言：class、String、Int、Result；
- 运行时：无（委托 TcpStream/TlsStream）；
- 接口：`Context`、`SocketAddress`、`TcpStream`、`TlsStream`、`TlsConfig`、`SocketOptions`、`Dns`、`IpAddress`、`IpFamily`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Context`、`SocketAddress`、`TcpStream`、`TlsStream`、`TlsConfig`、`SocketOptions`、`Dns`、`IpAddress`、`IpFamily`、`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

引用语义；无资源；返回流归调用方；可并发。

---

## 12. 示例与反例

正确：`new TlsClient(config.withServerName("example.com")).connect(ctx, address)`。  
反例：无 serverName 直接地址连接；握手失败不关 TCP；共享可变 config。

---

## 13. 测试/场景义务

地址/DNS；SNI；握手失败；取消；多连接；流所有权。

---

## 14. XNull 伪代码

```xnull
class TlsClient {
    final TlsConfig _tlsConfig
    final SocketOptions _socketOptions

    TlsClient(TlsConfig config) {
        if config == null { throw "TlsClient: null config" }
        _tlsConfig = config
        _socketOptions = new SocketOptions()
    }

    TlsClient(TlsConfig config, SocketOptions options) {
        if config == null || options == null {
            throw "TlsClient: null argument"
        }
        _tlsConfig = config
        _socketOptions = options.copy()
    }

    Result<TlsStream, Error> connect(Context context, SocketAddress remote) {
        if context == null || remote == null {
            throw "TlsClient.connect: null argument"
        }
        if _tlsConfig.serverName() == null || _tlsConfig.serverName() == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "missing server name"))
        }
        Result<TcpStream, Error> tcp = TcpStream.connect(context, remote, _socketOptions)
        if tcp.isErr() { return Err(tcp.error()) }
        Result<TlsStream, Error> tls = TlsStream.connect(context, tcp.value(), _tlsConfig)
        if tls.isErr() {
            tcp.value().close()
            return Err(tls.error())
        }
        return tls
    }

    Result<TlsStream, Error> connect(Context context, String host, Int port) {
        if host == null || host == "" { throw "TlsClient.connect: empty host" }
        TlsConfig config = _tlsConfig
        if config.serverName() == null || config.serverName() == "" {
            config = config.withServerName(host)
        }
        TlsClient client = new TlsClient(config, _socketOptions)
        Result<IpAddress, Error> address = Dns.resolveOne(context, host, IpFamily.Unspecified)
        if address.isErr() { return Err(address.error()) }
        return client.connect(context, new SocketAddress(address.value(), port))
    }

    TlsConfig config() { return _tlsConfig }
}
```

> `Dns` 来自 `xdk.net`；`BasicError`/`ErrorKind` 来自 `xdk.errors`。
