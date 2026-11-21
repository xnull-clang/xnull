# `NetworkService`

| 项 | 值 |
| --- | --- |
| 类型 | `class NetworkService` |
| 包 | `xdk.net.service` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`SocketAddress`、`ServiceOptions`、`ServiceState`、`ServiceStats`、`Server`、`Client`、`SessionHandler`、`TaskGroup`、`TaskHandle`、`Error` |

---

## 1. 定位

网络服务宿主：在后台启动一个服务端或一个客户端角色，持有任务组与生命周期，提供状态、统计、优雅停机、立即关闭。

不做：多角色混合、多监听器、服务发现、自动重连循环、HTTP/WS、连接池、协议编解码、全局注册表。

`NetworkService` 是可选门面；需要完全控制时可直接使用 `Server`/`Client`。一个实例只承载一个角色，启动一次。

---

## 2. 设计逻辑

- 字段：配置快照、启动时间、状态、关闭标志、服务端/客户端引用、任务组、主任务句柄。
- `startServer`：绑定 `Server`，创建 `TaskGroup`，后台任务执行 `server.serve`；返回 `Server` 借用。
- `startClient`：创建 `Client`，连接，创建唯一 `Session`，后台任务执行 `session.run`；返回 `Client` 借用。
- 角色只能选择一次；`startServer` 与 `startClient` 互斥；重复/混合启动返回 `AlreadyExists`。
- `startServer` 的 bind 失败、`startClient` 的 connect/session 失败发生在任务启动前：状态保持 `Created`，允许重试。
- 任务创建失败（`TaskGroup.spawn`）发生在资源已创建后：关闭角色，状态 `Failed`。
- `state` 在任务已结束时读取 `TaskHandle.failure`：取消映射 `Stopped`，其他错误映射 `Failed`，成功映射 `Stopped`；`shutdown` 已置 `Stopped` 时不回看任务错误。
- `shutdown`：服务端走 `Server.shutdown` 排空；客户端先 `TaskGroup.cancel` 再 `Client.close` 立即关闭，避免“先关连接”被任务记成非取消错误；然后 `TaskGroup.close` 取消/等待后台任务。
- `close`：立即关闭角色与任务组；幂等；终态 `Closed`。
- 无全局；`NetworkService` 不自动重连，重连由 `Client`/调用方驱动。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_options` | `ServiceOptions` | final | 配置快照 |
| `_startedAtMonoMillis` | `Long` | final | 构造时间，≥0 |
| `_state` | `ServiceState` | 可变 | 生命周期 |
| `_closed` | `Bool` | 可变 | 是否已 close |
| `_server` | `Server?` | 可变 | 服务端角色；与客户端互斥 |
| `_client` | `Client?` | 可变 | 客户端角色；与服务端互斥 |
| `_group` | `TaskGroup?` | 可变 | 后台任务组；启动后非 null |
| `_task` | `TaskHandle?` | 可变 | 主任务；启动后非 null |

不变量：`_server` 与 `_client` 至多一个非 null；`_group` 非 null 时 `_task` 非 null；`close` 后 `_closed=true` 且状态 `Closed`；启动只能从 `Created` 进入；`Stopped`/`Failed` 不可重新启动。

---

## 4. 生命周期

构造（`Created`）→ `startServer` 或 `startClient`（`Running`）→ `shutdown`（`Stopped`）或 `close`（`Closed`）。启动失败且未留下资源时回到 `Created`；任务创建失败进入 `Failed`。`close` 幂等；关闭后不能重新启动。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `NetworkService(ServiceOptions options)` | 非 null | 非 null | null → panic |

构造时复制 options；不启动任何任务。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `startServer` | 后台启动服务端 | `Context context, SocketAddress local, SessionHandler handler` | `Result<Server, Error>` | `AlreadyExists`/绑定/任务创建失败 |
| `startClient` | 后台启动客户端 | `Context context, SocketAddress remote, SessionHandler handler` | `Result<Client, Error>` | `AlreadyExists`/连接/会话/任务创建失败 |
| `shutdown` | 优雅/立即停止 | `Context context` | `Result<Unit, Error>` | `Timeout`/`Cancelled`/`Io` |
| `close` | 立即关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `state` | 生命周期快照 | 无 | `ServiceState` | 无 |
| `stats` | 聚合统计 | 无 | `ServiceStats` | 无 |
| `localAddress` | 本地地址/无 | 无 | `SocketAddress?` | 无 |
| `server` | 服务端借用/无 | 无 | `Server?` | 无 |
| `client` | 客户端借用/无 | 无 | `Client?` | 无 |
| `options` | 配置副本 | 无 | `ServiceOptions` | 无 |
| `isOpen` | 是否仍在服务 | 无 | `Bool` | 无 |

说明：

- `startServer`/`startClient` 成功返回后后台任务已创建；返回的 `Server`/`Client` 为借用引用，调用方不得在 `NetworkService` 之外 `close` 角色（否则生命周期不一致）。
- `startServer` 的 handler 会在整个服务生命周期内使用；handler 可被多连接共享。
- `startClient` 只启动一个会话；连接结束后任务结束，`state` 变为 `Stopped` 或 `Failed`。需要断线重连循环时使用 `Client.reconnect` 或上层循环。
- `shutdown` 对客户端不是优雅排空：`Client.close` 立即关闭连接；需要协议级半关闭时直接使用 `Connection`/底层流。
- `shutdown` 可重复调用；`Created` 直接转 `Stopped`，`Failed` 是 no-op（必须 `close`），`Closed` 返回 `Ok(unit)`。
- `close` 后 `shutdown` 返回 `Ok(unit)`；`close` 不等待排空。
- `state` 是快照；任务刚结束时可能与瞬时状态不同。
- `stats` 委托当前角色；未启动时返回全零统计与 uptime。
- `localAddress` 服务端返回监听地址；客户端返回当前连接本地地址；无连接返回 null。
- `isOpen` 在 `Created`/`Stopped`/`Failed`/`Closed` 为 false；`Starting`/`Running`/`Draining` 为 true。

---

## 8. 使用的技术

- 后台任务组；
- 角色门面；
- 状态机；
- 任务失败映射；
- 聚合统计；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、泛型任务引用、Long、Bool、Result；
- 运行时：`TaskGroup.create`、`TaskGroup.spawn`、`TaskGroup.cancel`、`TaskGroup.close`、`TaskHandle.isDone`、`TaskHandle.failure`、`monotonicMillis`；
- 接口：`Context`、`SocketAddress`、`ServiceOptions`、`Server`、`Client`、`SessionHandler`、`ServiceState`、`ServiceStats`、`Error`、`ErrorKind`、`unavailableError`、`BasicError`。

---

## 10. 依赖的特性/接口/类

`Context`、`SocketAddress`、`ServiceOptions`、`ServiceState`、`ServiceStats`、`Server`、`Client`、`Session`、`Connection`、`SessionHandler`、`TaskGroup`、`TaskHandle`、`Task`、`Error`、`ErrorKind`、`unavailableError`、`BasicError`、`monotonicMillis`。

---

## 11. 所有权与并发

引用语义；拥有角色与任务组；`server`/`client` 返回借用；`start`/`shutdown`/`close` 必须由调用方串行化，重复 `close` 幂等；`state`/`stats`/`localAddress` 可并发读取（快照可能不原子）。
相等：引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：`NetworkService service = new NetworkService(options)`；`service.startServer(context, local, handler)`；运行期查询 `service.state()`/`service.stats()`；收到信号后 `service.shutdown(shutdownContext)`；最后 `service.close()`。  
反例：同一实例先 `startServer` 再 `startClient`；`shutdown` 后重新启动；在 `NetworkService` 外关闭角色；把 `startClient` 当自动重连循环；并发调用 `startServer`；忽略 `shutdown` 的 `Timeout`。

---

## 13. 测试/场景义务

构造/options 复制；服务端启动/绑定失败重试/任务失败；客户端连接失败重试/会话失败/任务失败；角色互斥；重复启动；`state` 迁移（Created/Starting/Running/Draining/Stopped/Failed/Closed）；`shutdown` 排空/超时/取消/重复；`close` 幂等/关闭后启动；`stats` 零值/委托；`localAddress` 服务端/客户端/无连接；`server`/`client` 借用；`isOpen` 全状态。

---

## 14. XNull 伪代码

```xnull
class NetworkService {
    final ServiceOptions _options
    final Long _startedAtMonoMillis
    ServiceState _state
    Bool _closed
    Server? _server
    Client? _client
    TaskGroup? _group
    TaskHandle? _task

    NetworkService(ServiceOptions options) {
        if options == null { throw "NetworkService: null options" }
        _options = options.copy()
        _startedAtMonoMillis = monotonicMillis()
        _state = ServiceState.Created
        _closed = false
        _server = null
        _client = null
        _group = null
        _task = null
    }

    Result<Server, Error> startServer(Context context, SocketAddress local,
                                      SessionHandler handler) {
        if context == null || local == null || handler == null {
            throw "NetworkService.startServer: null argument"
        }
        if _closed { return Err(unavailableError("network service")) }
        if _state != ServiceState.Created || _server != null || _client != null {
            return Err(new BasicError(ErrorKind.AlreadyExists,
                "network service already started"))
        }
        Result<Server, Error> bound = Server.bind(context, local, _options)
        if bound.isErr() { return Err(bound.error()) }
        Server server = bound.value()
        TaskGroup group = TaskGroup.create(context)
        Result<Task<Unit>, Error> spawned = group.spawn(
            (Context taskContext) -> {
                return server.serve(taskContext, handler)
            })
        if spawned.isErr() {
            group.close()
            server.close()
            _state = ServiceState.Failed
            return Err(spawned.error())
        }
        _server = server
        _group = group
        _task = spawned.value()
        _state = ServiceState.Running
        return Ok(server)
    }

    Result<Client, Error> startClient(Context context, SocketAddress remote,
                                      SessionHandler handler) {
        if context == null || remote == null || handler == null {
            throw "NetworkService.startClient: null argument"
        }
        if _closed { return Err(unavailableError("network service")) }
        if _state != ServiceState.Created || _server != null || _client != null {
            return Err(new BasicError(ErrorKind.AlreadyExists,
                "network service already started"))
        }
        Client client = new Client(_options)
        Result<Connection, Error> connected = client.connect(context, remote)
        if connected.isErr() {
            client.close()
            return Err(connected.error())
        }
        Result<Session, Error> opened = connected.value().openSession(
            _options.getReadBufferBytes(), _options.getHeartbeatPolicy())
        if opened.isErr() {
            client.close()
            return Err(opened.error())
        }
        Session session = opened.value()
        TaskGroup group = TaskGroup.create(context)
        Result<Task<Unit>, Error> spawned = group.spawn(
            (Context taskContext) -> {
                return session.run(taskContext, handler)
            })
        if spawned.isErr() {
            group.close()
            client.close()
            _state = ServiceState.Failed
            return Err(spawned.error())
        }
        _client = client
        _group = group
        _task = spawned.value()
        _state = ServiceState.Running
        return Ok(client)
    }

    Result<Unit, Error> shutdown(Context context) {
        if context == null { throw "NetworkService.shutdown: null context" }
        ServiceState current = self.state()
        if current == ServiceState.Closed { return Ok(unit) }
        if current == ServiceState.Failed { return Ok(unit) }
        if current == ServiceState.Created {
            _state = ServiceState.Stopped
            return Ok(unit)
        }
        _state = ServiceState.Draining
        Result<Unit, Error> result = Ok(unit)
        if _server != null {
            Result<Unit, Error> serverResult = _server.shutdown(context)
            if serverResult.isErr() { result = serverResult }
        }
        if _client != null {
            if _group != null { _group.cancel() }
            Result<Unit, Error> clientResult = _client.close()
            if clientResult.isErr() && result.isOk() {
                result = clientResult
            }
        }
        if _group != null {
            Result<Unit, Error> groupResult = _group.close()
            if groupResult.isErr() && result.isOk() {
                result = groupResult
            }
        }
        _state = ServiceState.Stopped
        return result
    }

    Result<Unit, Error> close() {
        if _closed { return Ok(unit) }
        _closed = true
        _state = ServiceState.Closed
        Result<Unit, Error> serverResult = Ok(unit)
        Result<Unit, Error> clientResult = Ok(unit)
        Result<Unit, Error> groupResult = Ok(unit)
        if _group != null { _group.cancel() }
        if _server != null { serverResult = _server.close() }
        if _client != null { clientResult = _client.close() }
        if _group != null { groupResult = _group.close() }
        if serverResult.isErr() { return serverResult }
        if clientResult.isErr() { return clientResult }
        return groupResult
    }

    ServiceState state() {
        if _state == ServiceState.Closed { return ServiceState.Closed }
        if _state == ServiceState.Stopped { return ServiceState.Stopped }
        if _state == ServiceState.Failed { return ServiceState.Failed }
        if _task != null && _task.isDone() {
            Error? failure = _task.failure()
            if failure == null { return ServiceState.Stopped }
            if failure.kind() == ErrorKind.Cancelled {
                return ServiceState.Stopped
            }
            return ServiceState.Failed
        }
        return _state
    }

    ServiceStats stats() {
        if _server != null { return _server.stats() }
        if _client != null { return _client.stats() }
        Long uptimeMillis = monotonicMillis() - _startedAtMonoMillis
        return new ServiceStats(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            uptimeMillis)
    }

    SocketAddress? localAddress() {
        if _closed { return null }
        if _server != null { return _server.localAddress() }
        if _client != null {
            Connection? connection = _client.connection()
            if connection != null && connection.isOpen() {
                return connection.localAddress()
            }
        }
        return null
    }

    Server? server() { return _server }
    Client? client() { return _client }
    ServiceOptions options() { return _options.copy() }

    Bool isOpen() {
        ServiceState current = self.state()
        if _closed { return false }
        return current == ServiceState.Starting
            || current == ServiceState.Running
            || current == ServiceState.Draining
    }
}
```
