# `McpRegistry`

| 项 | 值 |
| --- | --- |
| 类型 | `class McpRegistry` |
| 包 | `xdk.mcp` |
| 稳定性 | `preview` |
| 依赖 | `McpTransport`、`McpClient`、`McpClientInfo`、`Context` |

---

## 1. 定位

按名称登记 MCP 服务器端点（transport），按名称创建客户端；每个宿主拥有自己的注册表。

不做：全局注册表、网络目录服务、服务发现、健康检查、自动重连、配置持久化。

---

## 2. 设计逻辑

- 注册项是“名称 → 未使用的 transport”；名称由应用配置，大小写敏感。
- `connect` 把 transport 所有权转给 `McpClient`；同一注册项只能连接一次；释放后可 `unregister` 再注册新 transport。
- 注册表不初始化客户端；调用方拿到 `McpClient` 后调用 `initialize`，便于显式控制 Context/超时。
- 关闭注册表只关闭**未连接**的 transport；已连接由客户端关闭，避免双重关闭。
- 无全局状态；不缓存客户端；不读环境变量/配置文件。
- 名称/transport 非空；重复名称 `AlreadyExists`；已连接再 connect `AlreadyExists`。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_transports` | `Map<String, McpTransport>` | final | 名称 → transport |
| `_connected` | `Set<String>` | final | 已转移所有权的名称 |
| `_open` | `Bool` | 可变 | 是否可用 |

不变量：名称非空；transport 非 null；`_connected` ⊆ `_transports.keys`；已连接项的 transport 不再由注册表关闭。

---

## 4. 生命周期

构造后可用；`register`/`connect`/`unregister`；必须 `close`；close 幂等；关闭后注册/连接 `Unavailable`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `McpRegistry()` | 无 | 空注册表 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `register` | 登记服务器 | `String name, McpTransport transport` | `Result<Unit, Error>` | `InvalidArgument`/`AlreadyExists`/`Unavailable` |
| `unregister` | 注销服务器 | `String name` | `Bool` | 无（已连接返回 false） |
| `contains` | 是否登记 | `String name` | `Bool` | null → panic |
| `names` | 名称快照 | 无 | `List<String>` | 无 |
| `connect` | 创建客户端 | `Context context, String name, McpClientInfo clientInfo` | `Result<McpClient, Error>` | `NotFound`/`AlreadyExists`/`Unavailable` |
| `isConnected` | 是否已连接 | `String name` | `Bool` | null → panic |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |

说明：

- `register`：名称非空、transport 非 null；重复名称拒绝；不连接、不初始化。
- `connect`：名称必须存在且未连接；成功后标记 connected，返回未初始化的 `McpClient`；调用方负责 initialize/close。
- `unregister`：未连接项移除并返回 true；已连接项返回 false，不关闭 transport（客户端拥有）。
- `close`：关闭所有未连接 transport；已连接跳过；清空表；幂等。
- `names`/`isConnected` 只读快照。

---

## 8. 使用的技术

- 名称索引；
- 所有权转移标记；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、String、Bool、List、Map、Set、Result；
- 运行时：无；
- 接口：`McpTransport`、`McpClient`、`McpClientInfo`、`Context`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`McpTransport`、`McpClient`、`McpClientInfo`、`Context`、`List`、`Map`、`Set`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`。

---

## 11. 所有权与并发

- 注册表拥有未连接 transport；`connect` 转移给客户端。
- 非线程安全；注册/连接/关闭需调用方串行化。
- `close` 可重复；已连接 transport 不被注册表关闭。
- 不做全局单例；每个宿主/Agent 自己持有。

---

## 12. 示例与反例

正确：`registry.register("weather", new McpStdioTransport(input, output))` → `McpClient client = registry.connect(context, "weather", clientInfo)` → `client.initialize(context)`。  
反例：全局注册表；同一 transport 连接两次；注册表 close 时关闭已连接客户端；把名称当唯一安全主体；注册空名称。

---

## 13. 测试/场景义务

注册/重复/空名；connect 成功/未知/重复；unregister 未连接/已连接；names/contains/isConnected；close 关闭未连接、跳过已连接；close 幂等；关闭后 register/connect；客户端独立 close。

---

## 14. XNull 伪代码

```xnull
class McpRegistry {
    final Map<String, McpTransport> _transports
    final Set<String> _connected
    Bool _open

    McpRegistry() {
        _transports = new Map<String, McpTransport>()
        _connected = new Set<String>()
        _open = true
    }

    Result<Unit, Error> register(String name, McpTransport transport) {
        if name == null || name == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpRegistry.register: empty name"))
        }
        if transport == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpRegistry.register: null transport"))
        }
        if !_open { return Err(unavailableError("mcp registry")) }
        if _transports.has(name) {
            return Err(new BasicError(ErrorKind.AlreadyExists,
                "McpRegistry: duplicate name"))
        }
        _transports.put(name, transport)
        return Ok(unit)
    }

    Bool unregister(String name) {
        if name == null { throw "McpRegistry.unregister: null" }
        if _connected.has(name) { return false }
        return _transports.remove(name)
    }

    Bool contains(String name) {
        if name == null { throw "McpRegistry.contains: null" }
        return _transports.has(name)
    }

    List<String> names() { return _transports.keys() }

    Result<McpClient, Error> connect(Context context, String name,
        McpClientInfo clientInfo) {
        if context == null || name == null || clientInfo == null {
            throw "McpRegistry.connect: null argument"
        }
        if !_open { return Err(unavailableError("mcp registry")) }
        if !_transports.has(name) {
            return Err(new BasicError(ErrorKind.NotFound,
                "McpRegistry: unknown server " + name))
        }
        if _connected.has(name) {
            return Err(new BasicError(ErrorKind.AlreadyExists,
                "McpRegistry: already connected " + name))
        }
        McpTransport transport = _transports.get(name)
        _connected.add(name)
        return Ok(new McpClient(transport, clientInfo))
    }

    Bool isConnected(String name) {
        if name == null { throw "McpRegistry.isConnected: null" }
        return _connected.has(name)
    }

    Bool isOpen() { return _open }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        List<String> keys = _transports.keys()
        Result<Unit, Error> outcome = Ok(unit)
        Int index = 0
        while index < keys.length() {
            String name = keys.get(index)
            if !_connected.has(name) {
                McpTransport transport = _transports.get(name)
                Result<Unit, Error> closed = transport.close()
                if closed.isErr() && outcome.isOk() { outcome = closed }
            }
            index = index + 1
        }
        _transports.clear()
        _connected.clear()
        return outcome
    }
}
```
