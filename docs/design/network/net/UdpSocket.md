# `UdpSocket`

| 项 | 值 |
| --- | --- |
| 类型 | `class UdpSocket` |
| 包 | `xdk.net` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`SocketAddress`、`Datagram`、`Error` |

---

## 1. 定位

UDP 数据报套接字：绑定、发送、接收、查询本地地址、关闭。

不做：可靠传输、拥塞控制、TLS、QUIC、raw socket、分片重组。

---

## 2. 设计逻辑

- 字段 `_handle`、`_local`、`_open`。
- `bind` 调用运行时 UDP 原语；端口 0 由内核分配。
- `sendTo` 使用 `Datagram.remote`；可并发。
- connected UDP 用 `connect`/`send`/`receive`；`disconnect` 取消。
- 组播/广播用 `joinMulticast`/`leaveMulticast`/`setBroadcast`。
- `receiveFrom` 单消费者；缓冲不足返回 `truncated=true` 的 Datagram，不静默丢包。
- 阻塞收发首参 `Context`；关闭后 `Unavailable`。
- `close` 幂等。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_handle` | `UdpHandle` | 运行时句柄 |
| `_local` | `SocketAddress` | 本地地址 |
| `_open` | `Bool` | 是否打开 |

不变量：handle/local 非 null；close 后 open=false。

---

## 4. 生命周期

`bind` 创建；必须 close；close 幂等；关闭后收发 `Unavailable`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `UdpSocket.bind(Context context, SocketAddress local)` | context/local | 非 null | `InvalidArgument`/`PermissionDenied`/`Network` |

构造器私有。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `bind` | 绑定本地 | `Context, SocketAddress` | `Result<UdpSocket, Error>` | 绑定失败 |
| `bind` | 带选项绑定 | `Context, SocketAddress, SocketOptions` | `Result<UdpSocket, Error>` | 绑定失败 |
| `sendTo` | 发送数据报 | `Context, Datagram` | `Result<Unit, Error>` | `Network`/`Timeout`/`Cancelled`/`Unavailable` |
| `receiveFrom` | 接收数据报 | `Context, Int maximumBytes` | `Result<Datagram, Error>` | 同上 |
| `connect` | connected UDP | `Context, SocketAddress` | `Result<Unit, Error>` | `Network`/`Unavailable` |
| `disconnect` | 取消 connected | 无 | `void` | 无 |
| `send` | 向 connected 发送 | `Context, Bytes data` | `Result<Unit, Error>` | 同上 |
| `receive` | 从 connected 接收 | `Context, Int maximumBytes` | `Result<Datagram, Error>` | 同上 |
| `joinMulticast` | 加入组播 | `Context, IpAddress group, MulticastOptions options` | `Result<Unit, Error>` | `Unsupported`/`Network` |
| `leaveMulticast` | 离开组播 | `Context, IpAddress group, MulticastOptions options` | `Result<Unit, Error>` | 同上 |
| `setBroadcast` | 广播开关 | `Bool enabled` | `Result<Unit, Error>` | `Unsupported`/`Unavailable` |
| `state` | 状态 | 无 | `SocketState` | 无 |
| `isConnected` | 是否 connected | 无 | `Bool` | 无 |
| `localAddress` | 本地地址 | 无 | `SocketAddress` | 无 |
| `isOpen` | 是否打开 | 无 | `Bool` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

---

## 8. 使用的技术

- OS UDP；
- 数据报缓冲；
- 截断标记；
- Context 取消；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、Int、Bool、Result；
- 运行时：`udpBindRaw`、`udpSendRaw`、`udpReceiveRaw`、`udpConnectRaw`、`udpDisconnectRaw`、`udpSendConnectedRaw`、`udpReceiveConnectedRaw`、`udpJoinMulticastRaw`、`udpLeaveMulticastRaw`、`udpSetBroadcastRaw`、`udpIsConnectedRaw`、`udpCloseRaw`、`UdpHandle`、`UdpSocketRaw`、`UdpReceiveRaw`；
- 接口：`Context`、`SocketAddress`、`SocketOptions`、`Datagram`、`IpAddress`、`MulticastOptions`、`SocketState`、`Error`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`SocketAddress`、`SocketOptions`、`Datagram`、`IpAddress`、`MulticastOptions`、`SocketState`、`Error`、`UdpHandle`、UDP 运行时原语、`unavailableError`。

---

## 11. 所有权与并发

拥有 UDP 句柄；必须 close；sendTo 可并发；receiveFrom 单消费者；close 可并发。

---

## 12. 示例与反例

正确：`UdpSocket.bind(ctx, local)` → `receiveFrom(ctx, 65535)` → `sendTo(ctx, datagram)`。  
反例：把截断包当完整；多任务并发 receiveFrom；close 后发送；把 UDP 当可靠流。

---

## 13. 测试/场景义务

绑定/选项；本地地址；发送/接收；connected UDP；组播/广播；截断；空数据报；取消；关闭后；close 幂等；并发发送；单接收者。

---

## 14. XNull 伪代码

```xnull
class UdpSocket {
    final UdpHandle _handle
    final SocketAddress _local
    Bool _open

    private UdpSocket(UdpHandle handle, SocketAddress local) {
        _handle = handle
        _local = local
        _open = true
    }

    static Result<UdpSocket, Error> bind(Context context, SocketAddress local) {
        return UdpSocket.bind(context, local, new SocketOptions())
    }

    static Result<UdpSocket, Error> bind(Context context, SocketAddress local, SocketOptions options) {
        if context == null || local == null || options == null {
            throw "UdpSocket.bind: null argument"
        }
        Result<UdpSocketRaw, Error> raw = udpBindRaw(context, local, options.copy())
        if raw.isErr() { return Err(raw.error()) }
        return Ok(new UdpSocket(raw.value().handle(), raw.value().local()))
    }

    Result<Unit, Error> sendTo(Context context, Datagram datagram) {
        if context == null || datagram == null {
            throw "UdpSocket.sendTo: null argument"
        }
        if !_open { return Err(unavailableError("udp socket")) }
        return udpSendRaw(_handle, context, datagram)
    }

    Result<Datagram, Error> receiveFrom(Context context, Int maximumBytes) {
        if context == null { throw "UdpSocket.receiveFrom: null context" }
        if maximumBytes <= 0 { throw "UdpSocket.receiveFrom: invalid maximum" }
        if !_open { return Err(unavailableError("udp socket")) }
        Result<UdpReceiveRaw, Error> raw = udpReceiveRaw(_handle, context, maximumBytes)
        if raw.isErr() { return Err(raw.error()) }
        UdpReceiveRaw received = raw.value()
        return Ok(new Datagram(received.data(), received.remote(), received.local(),
            received.truncated(), received.receivedAtMono(), received.interfaceIndex()))
    }

    Result<Unit, Error> connect(Context context, SocketAddress remote) {
        if context == null || remote == null {
            throw "UdpSocket.connect: null argument"
        }
        if !_open { return Err(unavailableError("udp socket")) }
        return udpConnectRaw(_handle, context, remote)
    }

    void disconnect() {
        if _open { udpDisconnectRaw(_handle) }
    }

    Result<Unit, Error> send(Context context, Bytes data) {
        if context == null || data == null {
            throw "UdpSocket.send: null argument"
        }
        if !_open { return Err(unavailableError("udp socket")) }
        return udpSendConnectedRaw(_handle, context, data)
    }

    Result<Datagram, Error> receive(Context context, Int maximumBytes) {
        if context == null { throw "UdpSocket.receive: null context" }
        if maximumBytes <= 0 { throw "UdpSocket.receive: invalid maximum" }
        if !_open { return Err(unavailableError("udp socket")) }
        return udpReceiveConnectedRaw(_handle, context, maximumBytes)
    }

    Result<Unit, Error> joinMulticast(Context context, IpAddress group, MulticastOptions options) {
        if context == null || group == null || options == null {
            throw "UdpSocket.joinMulticast: null argument"
        }
        if !_open { return Err(unavailableError("udp socket")) }
        return udpJoinMulticastRaw(_handle, context, group, options.copy())
    }

    Result<Unit, Error> leaveMulticast(Context context, IpAddress group, MulticastOptions options) {
        if context == null || group == null || options == null {
            throw "UdpSocket.leaveMulticast: null argument"
        }
        if !_open { return Err(unavailableError("udp socket")) }
        return udpLeaveMulticastRaw(_handle, context, group, options.copy())
    }

    Result<Unit, Error> setBroadcast(Bool enabled) {
        if !_open { return Err(unavailableError("udp socket")) }
        return udpSetBroadcastRaw(_handle, enabled)
    }

    SocketState state() {
        if !_open { return SocketState.Closed }
        return SocketState.Open
    }

    Bool isConnected() {
        if !_open { return false }
        return udpIsConnectedRaw(_handle)
    }

    SocketAddress localAddress() { return _local }
    Bool isOpen() { return _open }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return udpCloseRaw(_handle)
    }
}
```

> `UdpHandle`、`UdpSocketRaw`、`UdpReceiveRaw` 和 `udp*Raw` 是运行时 UDP 原语；不是 XDK 公共类型。
