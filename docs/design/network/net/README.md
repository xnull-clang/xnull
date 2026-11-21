# `xdk.net` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.net` |
| 层 | `xdk.net` / L5 |
| 依赖 | `xdk.errors`、`xdk.bytes`、`xdk.execution` |
| 被依赖 | `net.tls`、`net.http`、`net.websocket` |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

`xdk.net` 定义网络传输底座，不定义 HTTP/WebSocket 等应用协议：

- IP：`IpFamily`、`IpAddress`、`IpPrefix`、`SocketAddress`；
- DNS：`Dns`（无缓存静态入口）、`DnsRecord`、`DnsResolver`（显式缓存）、`DnsResolverOptions`、`DnsCacheStats`；
- 流：`ByteStream`、`TcpListener`、`TcpStream`；
- 数据报：`UdpSocket`、`Datagram`；
- 选项/状态：`SocketOptions`、`MulticastOptions`、`SocketState`、`ShutdownMode`；
- 连接池：`PoolKey`、`PooledConnection`、`ConnectionPoolOptions`、`ConnectionPoolStats`、`ConnectionPool`；
- 接口：`NetworkInterface`。

`xdk.net` 的传输面已覆盖 TCP/UDP/IP/DNS/socket 选项/组播/连接池；但完整网络层还需要：

- `net.uri`：URI/Query；
- `net.tls`：TLS；
- L6：`net.http`、`net.websocket`、`net.mime`。

不做：HTTP/WebSocket/MIME、QUIC/HTTP/3、SCTP/DCCP、ICMP/ARP、raw socket、Unix domain socket、TUN/TAP、用户态协议栈。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 分层而非万能 Socket | TCP/UDP 分开；TLS/HTTP/WS 分属独立包 |
| ByteStream 统一 | TCP/TLS/HTTP/WS 只依赖字节流协议 |
| 0 = EOF | `read` 返回 0 是流结束，不是“无数据” |
| 短写正常 | `write` 可短写；`writeAll` 写全 |
| Context 可取消 | 所有阻塞操作首参 `Context` |
| 资源幂等 | `close()` 幂等；关闭后操作 `Unavailable` |
| 无全局状态 | 无全局 DNS 缓存/连接池/信任库 |
| 显式缓存/池 | 由调用方持有 `DnsResolver`/`ConnectionPool` |
| 数据报不丢截断 | 缓冲不足 → `isTruncated=true`，不静默截断 |
| 无裸句柄 | 不暴露 fd/socket handle |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `IpFamily` | enum | IPv4/IPv6/未指定 | [`IpFamily.md`](IpFamily.md) |
| `IpAddress` | class | IP 解析/格式化/分类 | [`IpAddress.md`](IpAddress.md) |
| `IpPrefix` | class | CIDR 前缀/包含 | [`IpPrefix.md`](IpPrefix.md) |
| `SocketAddress` | class | IP + 端口 | [`SocketAddress.md`](SocketAddress.md) |
| `DnsRecord` | class | DNS 记录/TTL | [`DnsRecord.md`](DnsRecord.md) |
| `DnsResolverOptions` | class | resolver 配置 | [`DnsResolverOptions.md`](DnsResolverOptions.md) |
| `DnsResolver` | class | 显式 DNS/缓存 | [`DnsResolver.md`](DnsResolver.md) |
| `DnsCacheStats` | class | DNS 缓存统计 | [`DnsCacheStats.md`](DnsCacheStats.md) |
| `Dns` | class | 无缓存静态解析 | [`Dns.md`](Dns.md) |
| `SocketOptions` | class | socket 选项 | [`SocketOptions.md`](SocketOptions.md) |
| `MulticastOptions` | class | 组播选项 | [`MulticastOptions.md`](MulticastOptions.md) |
| `SocketState` | enum | socket 状态 | [`SocketState.md`](SocketState.md) |
| `ByteStream` | protocol | 统一字节流 | [`ByteStream.md`](ByteStream.md) |
| `TcpListener` | class | TCP 监听/接受 | [`TcpListener.md`](TcpListener.md) |
| `TcpHandler` | protocol | 服务端连接处理 | [`TcpHandler.md`](TcpHandler.md) |
| `TcpServer` | class | TCP 服务端角色 | [`TcpServer.md`](TcpServer.md) |
| `TcpClient` | class | TCP 客户端角色 | [`TcpClient.md`](TcpClient.md) |
| `TcpServerOptions` | class | TCP 服务端配置 | [`TcpServerOptions.md`](TcpServerOptions.md) |
| `TcpStream` | class | TCP 连接读写 | [`TcpStream.md`](TcpStream.md) |
| `UdpSocket` | class | UDP 收发/connected/组播 | [`UdpSocket.md`](UdpSocket.md) |
| `Datagram` | class | UDP 数据报 | [`Datagram.md`](Datagram.md) |
| `ShutdownMode` | enum | TCP 半关闭 | [`ShutdownMode.md`](ShutdownMode.md) |
| `NetworkInterface` | class | 网卡快照 | [`NetworkInterface.md`](NetworkInterface.md) |
| `PoolKey` | class | 连接池键 | [`PoolKey.md`](PoolKey.md) |
| `PooledConnection` | class | 池借出连接 | [`PooledConnection.md`](PooledConnection.md) |
| `ConnectionPoolOptions` | class | 池配置 | [`ConnectionPoolOptions.md`](ConnectionPoolOptions.md) |
| `ConnectionPoolStats` | class | 池统计 | [`ConnectionPoolStats.md`](ConnectionPoolStats.md) |
| `ConnectionPool` | class | 显式连接池 | [`ConnectionPool.md`](ConnectionPool.md) |

明确不做/不承诺：QUIC/HTTP3、SCTP/DCCP、ICMP/ARP、raw socket、Unix domain、TUN/TAP、零拷贝、io_uring、select 事件循环、平台特有 socket 选项。

---

## 4. 顶层函数

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `copyStream` | 单方向复制 | `Context, ByteStream source, ByteStream target, Int bufferSize` | `Result<Long, Error>` | `InvalidArgument`/`Io`/`Cancelled` |
| `readExactly` | 精确读 N 字节 | `Context, ByteStream source, Int count` | `Result<Bytes, Error>` | `Unavailable`/`Io`/`Cancelled` |
| `readAllStream` | 读到 EOF | `Context, ByteStream source` | `Result<Bytes, Error>` | `Io`/`Cancelled` |

```xnull
Result<Long, Error> copyStream(Context context, ByteStream source,
        ByteStream target, Int bufferSize) {
    if context == null || source == null || target == null {
        throw "copyStream: null argument"
    }
    if bufferSize <= 0 { throw "copyStream: bufferSize <= 0" }
    Bytes buffer = Bytes.alloc(bufferSize)
    Long total = 0
    while true {
        Result<Int, Error> read = source.read(context, buffer)
        if read.isErr() { return Err(read.error()) }
        if read.value() == 0 { break }
        Bytes part = slice(buffer, 0, read.value())
        Result<Unit, Error> written = target.writeAll(context, part)
        if written.isErr() { return Err(written.error()) }
        total = total + toLong(read.value())
    }
    return Ok(total)
}

Result<Bytes, Error> readExactly(Context context, ByteStream source, Int count) {
    if context == null || source == null { throw "readExactly: null argument" }
    if count < 0 { throw "readExactly: negative count" }
    Bytes result = Bytes.alloc(count)
    Int total = 0
    while total < count {
        Bytes buffer = Bytes.alloc(count - total)
        Result<Int, Error> read = source.read(context, buffer)
        if read.isErr() { return Err(read.error()) }
        Int readCount = read.value()
        if readCount == 0 {
            return Err(new BasicError(ErrorKind.Unavailable, "unexpected EOF"))
        }
        Int index = 0
        while index < readCount {
            result.set(total + index, buffer.get(index))
            index = index + 1
        }
        total = total + readCount
    }
    return Ok(result)
}

Result<Bytes, Error> readAllStream(Context context, ByteStream source) {
    if context == null || source == null { throw "readAllStream: null argument" }
    Bytes result = Bytes.empty()
    Bytes buffer = Bytes.alloc(32768)
    while true {
        Result<Int, Error> read = source.read(context, buffer)
        if read.isErr() { return Err(read.error()) }
        if read.value() == 0 { break }
        Int index = 0
        while index < read.value() {
            result.push(buffer.get(index))
            index = index + 1
        }
    }
    return Ok(result)
}
```

---

## 5. 技术/支撑/依赖

- 技术：IP/CIDR、DNS+TTL 缓存、OS socket、TCP/UDP、socket 选项、组播、连接池、截止时间、取消。
- 支撑：`TcpHandle`/`UdpHandle`/`DnsResolverHandle`/`ConnectionPoolHandle`、`tcp*/udp*/dns*/connectionPool*Raw` 原语、`toLong`、`Context`、`Bytes`。
- 依赖：`xdk.errors`、`xdk.bytes`、`xdk.execution`。

---

## 6. 场景

### N1：TCP 服务

`TcpListener.bind(ctx, local, options)` → `accept`/`acceptDeadline` → `read`/`writeAll` → `shutdown` → `close`。

### N2：UDP 采集/回执

`UdpSocket.bind` → `receiveFrom` → `Datagram.data` → `sendTo`；截断包用 `isTruncated` 丢弃/告警。

### N3：DNS 缓存

`DnsResolver(options)` → `resolve` → `DnsRecord.ttlSeconds`/`expiresAtMillis` → `cacheStats`。

### N4：connected UDP / 组播

`UdpSocket.connect` + `send`/`receive`；`joinMulticast`/`leaveMulticast`；`setBroadcast`。

### N5：连接池

`ConnectionPool(options, connector)` → `acquire` → 使用 → `release`；`stats`/`close`。

### N6：接口与前缀

`NetworkInterface.list`/`byName`；`IpPrefix.parse("10.0.0.0/8")`；`contains`。

### N7：代理/隧道

`copyStream` 单方向复制；双向代理用两个任务 + 两个方向；`readExactly` 处理定长帧。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| TCP/UDP | 不共用 `Socket` 基类；流/数据报语义不同 |
| `read` 0 | EOF；调用方不得当“暂时无数据” |
| `write` 短写 | 正常；`writeAll` 负责循环 |
| close 后 | 所有 I/O `Unavailable` |
| TCP 并发 | 一个 reader + 一个 writer；close 可并发 |
| UDP 并发 | sendTo 可并发；receiveFrom 单消费者 |
| UDP 截断 | 返回 truncated Datagram，不丢包 |
| DNS 缓存 | 显式 `DnsResolver`；`Dns` 无缓存 |
| SocketOptions | 显式 builder；bind/connect 读取快照 |
| 连接池 | 显式 `ConnectionPool`；connector 由调用方提供 |
| 组播/广播 | 显式 options / setBroadcast |
| 网卡信息 | 快照；不修改系统 |
| 应用协议 | L6：HTTP/WebSocket/MIME |
| QUIC/raw/Unix/TUN | 不做；不属于  传输面 |
