# `xdk.net.websocket` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.net.websocket` |
| 层 | `xdk.net` / L5 |
| 依赖 | `xdk.errors`、`xdk.bytes`、`xdk.text`、`xdk.execution`、`net`、`net.uri`、`net.tls`、`net.http` |
| 被依赖 | 应用 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

`xdk.net.websocket` 提供 WebSocket 客户端/服务端：

- 状态/消息类型/关闭码；
- 连接选项、消息；
- `WebSocket` 收发/控制帧/关闭；
- `WebSocketHandler` 服务端入口；
- `WebSocketClient` + 重连策略 + 统计。

不做：HTTP/2 WebSocket、压缩扩展、消息重放、连接迁移、TUI。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 消息级 API | 分片/掩码/控制帧细节内部化 |
| 正常关闭不是 Err | Close 消息/关闭码表达 |
| 状态明确 | Connecting/Open/Closing/Closed |
| 背压 | 发送队列上限；满时 `Busy`/`Timeout` |
| Context 可取消 | 收发/关闭首参 `Context` |
| 资源幂等 | `WebSocket.close` 幂等 |
| 无全局 | 无全局连接/客户端 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `WebSocketState` | enum | 连接状态 | [`WebSocketState.md`](WebSocketState.md) |
| `WebSocketMessageKind` | enum | Text/Binary/Ping/Pong/Close | [`WebSocketMessageKind.md`](WebSocketMessageKind.md) |
| `WebSocketCloseCode` | enum | 标准关闭码 | [`WebSocketCloseCode.md`](WebSocketCloseCode.md) |
| `WebSocketOptions` | class | 连接/帧/心跳/队列选项 | [`WebSocketOptions.md`](WebSocketOptions.md) |
| `WebSocketMessage` | class | 消息快照 | [`WebSocketMessage.md`](WebSocketMessage.md) |
| `WebSocket` | class | 连接/收发/关闭 | [`WebSocket.md`](WebSocket.md) |
| `WebSocketHandler` | protocol | 服务端处理入口 | [`WebSocketHandler.md`](WebSocketHandler.md) |
| `WebSocketClientState` | enum | 客户端状态 | [`WebSocketClientState.md`](WebSocketClientState.md) |
| `ReconnectPolicy` | class | 重连退避 | [`ReconnectPolicy.md`](ReconnectPolicy.md) |
| `WebSocketStats` | class | 收发统计 | [`WebSocketStats.md`](WebSocketStats.md) |
| `WebSocketClient` | class | 自动重连客户端 | [`WebSocketClient.md`](WebSocketClient.md) |
| `WebSocketServer` | class | 服务端角色 | [`WebSocketServer.md`](WebSocketServer.md) |

X：压缩扩展、HTTP/2 WebSocket、消息重放、连接迁移、多路复用。

---

## 4. 顶层函数

无；关闭码映射为 `WebSocketCloseCode` 顶层函数（见类型文件）。

---

## 5. 技术/支撑/依赖

- 技术：HTTP upgrade、帧编解码、掩码、分片、ping/pong、关闭握手、背压。
- 支撑：`WebSocketHandle`、`websocket*Raw` 运行时原语、`ByteStream`、`Context`。
- 依赖：`errors`、`bytes`、`text`、`execution`、`net`、`net.uri`、`net.tls`、`net.http`。

---

## 6. 场景

### W1：客户端推送

`WebSocket.connect` → `sendText`/`sendBinary` → `receive` → `close`。

### W2：服务端升级

`HttpExchange.upgrade("websocket")` → `WebSocket.accept` → handler。

### W3：心跳/背压

`WebSocketOptions.pingInterval`；发送队列上限；`trySendText`。

### W4：自动重连

`WebSocketClient` + `ReconnectPolicy`；状态/统计。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 压缩 | X |
| HTTP/2 WebSocket | X |
| 正常关闭 | Close 消息，不是 Err |
| 关闭后 | `Unavailable` |
| 发送并发 | 内部串行化 |
| 接收 | 单消费者 |
| 心跳 | 可选；自动 Pong 默认 |
| 重连 | 仅 `WebSocketClient` |

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | `@WsHandler` |
| 本包消费 | `@Value`、`@Builder`、`@Override` |
| 处理器 | WebSocketAnnotationProcessor（Validate/Generate） |
| 生成物 | handler 注册、消息类型映射 |
| 状态 | 领域注解 planned；A8 派生 planned；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| handler 类 | `@WsHandler` | handler 表 |
| `WebSocketMessage`/`WebSocketOptions`/`WebSocketStats` | `@Value`/`@Builder` | 值语义/选项 |
| `WebSocketHandler` 实现 | `@Override` | 签名校验 |

### 声明

```x
@Target(Type)
@Retention(Source)
@annotation WsHandler {
}
```

声明文件：每个注解单独一个 PascalCase 文件；处理器为构建期类型；生成代码在 `<package>/generated/`。

### 使用

```x
@WsHandler
class ChatHandler {
    Result<Unit, Error> onMessage(WebSocketMessage message) {
        // ...
    }
}
```

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../../ANNOTATION-CATALOG.md)。
