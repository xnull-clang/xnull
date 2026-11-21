# `ServiceOptions`

| 项 | 值 |
| --- | --- |
| 类型 | `class ServiceOptions` |
| 包 | `xdk.net.service` |
| 稳定性 | `preview` |
| 依赖 | `SocketOptions`、`TcpServerOptions`、`TlsConfig`、`BackpressurePolicy`、`HeartbeatPolicy`、`ReconnectPolicy` |

---

## 1. 定位

网络服务配置：连接上限、接受队列、accept 退避、读缓冲、空闲/读/写超时、优雅停机预算、socket 选项、TLS、背压/心跳/重连策略。

不做：地址绑定、DNS、连接池、HTTP/WS 配置、证书管理、线程池调优、平台特有 socket 选项。

---

## 2. 设计逻辑

- 可变 builder；`Server.bind`、`Client` 构造、`NetworkService` 构造时复制。
- 默认 `maxConnections=128`、`acceptQueueCapacity=256`、`acceptBackoffMillis=100`、`readBufferBytes=32768`。
- 超时默认 0（禁用）；生产服务应显式设置空闲/读/写超时或启用心跳。
- `gracefulShutdownTimeoutMillis=0` 表示不等待，立即强制关闭；默认 30s。
- `acceptQueueCapacity=0` 表示同步交接，不缓存已接受连接。
- `readBufferBytes` 限定 1KiB..1MiB，避免每连接过大缓冲。
- `tlsConfig` 为空表示明文；非空时服务端必须含证书/私钥，客户端必须含 `serverName`。
- 策略字段在 setter 中复制，构造/复制后互不影响。
- 无 close；非线程安全（builder 阶段）。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_maxConnections` | `Int` | 最大活动连接，>0 |
| `_acceptQueueCapacity` | `Int` | 待接受队列容量，≥0 |
| `_acceptBackoffMillis` | `Long` | accept 失败退避，≥0 |
| `_readBufferBytes` | `Int` | 单次读缓冲，1KiB..1MiB |
| `_idleTimeoutMillis` | `Long` | 传输空闲超时，≥0；0=禁用 |
| `_readTimeoutMillis` | `Long` | 单次读超时，≥0；0=禁用 |
| `_writeTimeoutMillis` | `Long` | 单次写超时，≥0；0=禁用 |
| `_gracefulShutdownTimeoutMillis` | `Long` | 优雅停机预算，≥0 |
| `_socketOptions` | `SocketOptions` | 连接选项副本 |
| `_tlsConfig` | `TlsConfig?` | 为空表示明文 |
| `_backpressurePolicy` | `BackpressurePolicy` | 背压策略副本 |
| `_heartbeatPolicy` | `HeartbeatPolicy` | 心跳策略副本 |
| `_reconnectPolicy` | `ReconnectPolicy` | 客户端重连策略副本 |

不变量：计数/容量/超时非负；`maxConnections>0`；`readBufferBytes` 在范围内；策略/socket 选项非 null；TLS 组合在 bind/connect 时校验。

---

## 4. 生命周期

构造后可变；服务创建时复制；无 close；运行中的服务不受后续修改影响。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ServiceOptions()` | 无 | 默认值 | 无 |
| `ServiceOptions(ServiceOptions other)` | 非 null | 非 null | null → panic |

setter 的合法域见 §7；非法值是合同错误（panic）。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `maxConnections` | 最大连接 | `Int value` | `ServiceOptions` | ≤0 → panic |
| `acceptQueueCapacity` | 待接受队列 | `Int value` | `ServiceOptions` | <0 → panic |
| `acceptBackoffMillis` | accept 退避 | `Long value` | `ServiceOptions` | <0 → panic |
| `readBufferBytes` | 读缓冲 | `Int value` | `ServiceOptions` | 越界 → panic |
| `idleTimeoutMillis` | 空闲超时 | `Long value` | `ServiceOptions` | <0 → panic |
| `readTimeoutMillis` | 读超时 | `Long value` | `ServiceOptions` | <0 → panic |
| `writeTimeoutMillis` | 写超时 | `Long value` | `ServiceOptions` | <0 → panic |
| `gracefulShutdownTimeoutMillis` | 停机预算 | `Long value` | `ServiceOptions` | <0 → panic |
| `socketOptions` | socket 选项 | `SocketOptions value` | `ServiceOptions` | null → panic |
| `tlsConfig` | TLS 配置 | `TlsConfig value` | `ServiceOptions` | null → panic |
| `withoutTls` | 清除 TLS | 无 | `ServiceOptions` | 无 |
| `backpressurePolicy` | 背压策略 | `BackpressurePolicy value` | `ServiceOptions` | null → panic |
| `heartbeatPolicy` | 心跳策略 | `HeartbeatPolicy value` | `ServiceOptions` | null → panic |
| `reconnectPolicy` | 重连策略 | `ReconnectPolicy value` | `ServiceOptions` | null → panic |
| `getMaxConnections` | 读最大连接 | 无 | `Int` | 无 |
| `getAcceptQueueCapacity` | 读队列容量 | 无 | `Int` | 无 |
| `getAcceptBackoffMillis` | 读退避 | 无 | `Long` | 无 |
| `getReadBufferBytes` | 读缓冲 | 无 | `Int` | 无 |
| `getIdleTimeoutMillis` | 读空闲超时 | 无 | `Long` | 无 |
| `getReadTimeoutMillis` | 读超时 | 无 | `Long` | 无 |
| `getWriteTimeoutMillis` | 写超时 | 无 | `Long` | 无 |
| `getGracefulShutdownTimeoutMillis` | 停机预算 | 无 | `Long` | 无 |
| `getSocketOptions` | socket 选项副本 | 无 | `SocketOptions` | 无 |
| `getTlsConfig` | TLS 配置/无 | 无 | `TlsConfig?` | 无 |
| `getBackpressurePolicy` | 背压策略副本 | 无 | `BackpressurePolicy` | 无 |
| `getHeartbeatPolicy` | 心跳策略副本 | 无 | `HeartbeatPolicy` | 无 |
| `getReconnectPolicy` | 重连策略副本 | 无 | `ReconnectPolicy` | 无 |
| `tcpServerOptions` | 转为  选项 | 无 | `TcpServerOptions` | 无 |
| `copy` | 独立快照 | 无 | `ServiceOptions` | 无 |

说明：

- `idleTimeoutMillis` 是传输空闲硬上限（无成功读写）；`HeartbeatPolicy` 是会话空闲检测；两者同时启用时先到者生效。
- `readTimeoutMillis`/`writeTimeoutMillis` 是单次操作截止；0 表示不额外限制，但仍受 `Context` 约束。服务端由运行时逐次应用；`Client` 返回的 `Connection` 由调用方设置截止，客户端空闲检测用 `HeartbeatPolicy`。
- `tcpServerOptions` 只映射  已有的三个字段，不复制本包策略。
- `getTlsConfig` 返回不可变配置引用；调用方不得假设可修改。
- `copy` 深复制 socket 选项与三个策略；TLS 配置按不可变引用共享。

---

## 8. 使用的技术

- builder；
- 上限/超时；
- 策略组合；
- 快照复制；
-  选项桥接。

---

## 9. 需要的支撑

- 语言：class、Int、Long、Bool、可空引用；
- 运行时：无；
- 接口：`SocketOptions`、`TcpServerOptions`、`TlsConfig`、`BackpressurePolicy`、`HeartbeatPolicy`、`ReconnectPolicy`。

---

## 10. 依赖的特性/接口/类

`SocketOptions`、`TcpServerOptions`、`TlsConfig`、`BackpressurePolicy`、`HeartbeatPolicy`、`ReconnectPolicy`、`Server`、`Client`、`NetworkService`。

---

## 11. 所有权与并发

可变；非线程安全；服务创建时复制；无资源；副本独立。
相等：引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：`new ServiceOptions().maxConnections(512).acceptQueueCapacity(64).idleTimeoutMillis(60000).readTimeoutMillis(30000).writeTimeoutMillis(30000)`。  
反例：0 最大连接；负超时；`readBufferBytes` 超出 1MiB；运行中修改 options 期望已启动服务变化；把 `tlsConfig` 当可变证书库；忽略 `gracefulShutdownTimeoutMillis=0` 的立即强制关闭语义。

---

## 13. 测试/场景义务

默认值；每个 setter；非法/边界；读缓冲上下界；队列 0；超时 0/正数；停机预算 0；socket 选项复制；TLS 设置/清除；策略复制；`tcpServerOptions` 映射；`copy` 独立；服务快照。

---

## 14. XNull 伪代码

```xnull
class ServiceOptions {
    Int _maxConnections = 128
    Int _acceptQueueCapacity = 256
    Long _acceptBackoffMillis = 100
    Int _readBufferBytes = 32768
    Long _idleTimeoutMillis = 0
    Long _readTimeoutMillis = 0
    Long _writeTimeoutMillis = 0
    Long _gracefulShutdownTimeoutMillis = 30000
    SocketOptions _socketOptions = new SocketOptions()
    TlsConfig? _tlsConfig = null
    BackpressurePolicy _backpressurePolicy = new BackpressurePolicy()
    HeartbeatPolicy _heartbeatPolicy = new HeartbeatPolicy()
    ReconnectPolicy _reconnectPolicy = new ReconnectPolicy()

    ServiceOptions() {
    }

    ServiceOptions(ServiceOptions other) {
        if other == null { throw "ServiceOptions: null other" }
        _maxConnections = other.getMaxConnections()
        _acceptQueueCapacity = other.getAcceptQueueCapacity()
        _acceptBackoffMillis = other.getAcceptBackoffMillis()
        _readBufferBytes = other.getReadBufferBytes()
        _idleTimeoutMillis = other.getIdleTimeoutMillis()
        _readTimeoutMillis = other.getReadTimeoutMillis()
        _writeTimeoutMillis = other.getWriteTimeoutMillis()
        _gracefulShutdownTimeoutMillis = other.getGracefulShutdownTimeoutMillis()
        _socketOptions = other.getSocketOptions()
        _tlsConfig = other.getTlsConfig()
        _backpressurePolicy = other.getBackpressurePolicy()
        _heartbeatPolicy = other.getHeartbeatPolicy()
        _reconnectPolicy = other.getReconnectPolicy()
    }

    ServiceOptions maxConnections(Int value) {
        if value <= 0 { throw "ServiceOptions.maxConnections: invalid" }
        _maxConnections = value
        return self
    }

    ServiceOptions acceptQueueCapacity(Int value) {
        if value < 0 { throw "ServiceOptions.acceptQueueCapacity: negative" }
        _acceptQueueCapacity = value
        return self
    }

    ServiceOptions acceptBackoffMillis(Long value) {
        if value < 0 { throw "ServiceOptions.acceptBackoffMillis: negative" }
        _acceptBackoffMillis = value
        return self
    }

    ServiceOptions readBufferBytes(Int value) {
        if value < 1024 { throw "ServiceOptions.readBufferBytes: too small" }
        if value > 1048576 { throw "ServiceOptions.readBufferBytes: too large" }
        _readBufferBytes = value
        return self
    }

    ServiceOptions idleTimeoutMillis(Long value) {
        if value < 0 { throw "ServiceOptions.idleTimeoutMillis: negative" }
        _idleTimeoutMillis = value
        return self
    }

    ServiceOptions readTimeoutMillis(Long value) {
        if value < 0 { throw "ServiceOptions.readTimeoutMillis: negative" }
        _readTimeoutMillis = value
        return self
    }

    ServiceOptions writeTimeoutMillis(Long value) {
        if value < 0 { throw "ServiceOptions.writeTimeoutMillis: negative" }
        _writeTimeoutMillis = value
        return self
    }

    ServiceOptions gracefulShutdownTimeoutMillis(Long value) {
        if value < 0 {
            throw "ServiceOptions.gracefulShutdownTimeoutMillis: negative"
        }
        _gracefulShutdownTimeoutMillis = value
        return self
    }

    ServiceOptions socketOptions(SocketOptions value) {
        if value == null { throw "ServiceOptions.socketOptions: null" }
        _socketOptions = value.copy()
        return self
    }

    ServiceOptions tlsConfig(TlsConfig value) {
        if value == null { throw "ServiceOptions.tlsConfig: null" }
        _tlsConfig = value
        return self
    }

    ServiceOptions withoutTls() {
        _tlsConfig = null
        return self
    }

    ServiceOptions backpressurePolicy(BackpressurePolicy value) {
        if value == null { throw "ServiceOptions.backpressurePolicy: null" }
        _backpressurePolicy = value.copy()
        return self
    }

    ServiceOptions heartbeatPolicy(HeartbeatPolicy value) {
        if value == null { throw "ServiceOptions.heartbeatPolicy: null" }
        _heartbeatPolicy = value.copy()
        return self
    }

    ServiceOptions reconnectPolicy(ReconnectPolicy value) {
        if value == null { throw "ServiceOptions.reconnectPolicy: null" }
        _reconnectPolicy = value.copy()
        return self
    }

    Int getMaxConnections() { return _maxConnections }
    Int getAcceptQueueCapacity() { return _acceptQueueCapacity }
    Long getAcceptBackoffMillis() { return _acceptBackoffMillis }
    Int getReadBufferBytes() { return _readBufferBytes }
    Long getIdleTimeoutMillis() { return _idleTimeoutMillis }
    Long getReadTimeoutMillis() { return _readTimeoutMillis }
    Long getWriteTimeoutMillis() { return _writeTimeoutMillis }
    Long getGracefulShutdownTimeoutMillis() {
        return _gracefulShutdownTimeoutMillis
    }

    SocketOptions getSocketOptions() { return _socketOptions.copy() }
    TlsConfig? getTlsConfig() { return _tlsConfig }
    BackpressurePolicy getBackpressurePolicy() { return _backpressurePolicy.copy() }
    HeartbeatPolicy getHeartbeatPolicy() { return _heartbeatPolicy.copy() }
    ReconnectPolicy getReconnectPolicy() { return _reconnectPolicy.copy() }

    TcpServerOptions tcpServerOptions() {
        TcpServerOptions result = new TcpServerOptions()
        result.maxConnections(_maxConnections)
        result.acceptBackoffMillis(_acceptBackoffMillis)
        result.connectionOptions(_socketOptions)
        return result
    }

    ServiceOptions copy() {
        return new ServiceOptions(self)
    }
}
```
