# `McpStdioTransport`

| 项 | 值 |
| --- | --- |
| 类型 | `class McpStdioTransport implements McpTransport` |
| 包 | `xdk.mcp` |
| 稳定性 | `preview` |
| 依赖 | `Reader`、`Writer`、`Context`、`Mutex`、`JsonRpcRequest`、`JsonRpcResponse`、`McpProtocolVersion` |

---

## 1. 定位

stdio 传输：换行分隔的 UTF-8 JSON-RPC 消息，客户端读写子进程 stdin/stdout，服务端读写自己的 stdin/stdout。

不做：启动/终止子进程、stderr 日志、shell 解析、重连、并发多路复用、TLS。

---

## 2. 设计逻辑

- 一消息一行；消息内不得有未转义换行；`Json.stringify` 生成紧凑 JSON，换行只作分隔。
- 读取有 `Long maximumMessageBytes` 上限；超限返回 `DataCorrupted`，不继续分配。
- 写入串行化：`Mutex<Bool>` 保护 `Writer`，避免多任务交错半行。
- 读取单消费者：`request`/`receive` 不得并发；并发请求是调用方合同错误（X 可加多路复用）。
- `request` 等待响应时，可接收通知并回调；遇到服务器主动请求 → `Unsupported`（legacy 回调 X）。
- `cancel` 写 `notifications/cancelled`；写入与读取可并发。
- stdout 只能写 JSON-RPC；日志必须走 stderr，由调用方/CLI 处理。
- 不拥有进程；只拥有传入的流（可选）。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_input` | `Reader` | final | 消息来源 |
| `_output` | `Writer` | final | 消息去向 |
| `_maximumMessageBytes` | `Long` | final | >0 |
| `_ownsStreams` | `Bool` | final | close 是否关闭流 |
| `_open` | `Bool` | 可变 | 是否可用 |
| `_writeMutex` | `Mutex<Bool>` | final | 写串行化 |
| `_notificationFailures` | `Int` | 可变 | 回调失败计数 |

不变量：input/output 非 null；max >0；同一时刻最多一个读操作；写操作由 mutex 串行化；关闭后 open=false。

---

## 4. 生命周期

构造后可用；必须 close；close 幂等；关闭后所有方法 `Unavailable`；若 `_ownsStreams` 为 true，close 关闭输入/输出；否则只停止使用。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `McpStdioTransport(Reader input, Writer output)` | input/output | 非 null | null → panic |
| `McpStdioTransport(Reader input, Writer output, Long maximumMessageBytes, Bool ownsStreams, Int maximumConcurrentRequests)` | 五参数 | input/output 非 null；max >0；并发 ≥1 | 非法 → panic |

`maximumConcurrentRequests` 当前必须为 1（读取单消费者）；大于 1 抛 `Unsupported`/panic，保留未来多路复用。默认 max 8 MiB，ownsStreams false。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `request` | 发请求/等响应 | `Context context, JsonRpcRequest request, Result<Unit, Error>(Context, JsonRpcRequest) notificationHandler` | `Result<JsonRpcResponse, Error>` | `InvalidArgument`/`Io`/`DataCorrupted`/`Cancelled`/`Unavailable` |
| `selectProtocolVersion` | 版本 no-op | `Context context, McpProtocolVersion version` | `Result<Unit, Error>` | `Unavailable` |
| `notify` | 发通知 | `Context context, JsonRpcRequest notification` | `Result<Unit, Error>` | `InvalidArgument`/`Io`/`Cancelled`/`Unavailable` |
| `receive` | 读请求/通知 | `Context context` | `Result<JsonRpcRequest, Error>` | `Io`/`DataCorrupted`/`Cancelled`/`Unavailable` |
| `respond` | 写响应 | `Context context, JsonRpcResponse response` | `Result<Unit, Error>` | `InvalidArgument`/`Io`/`Cancelled`/`Unavailable` |
| `acknowledge` | 确认通知 | `Context context` | `Result<Unit, Error>` | `Unavailable` |
| `cancel` | 写取消通知 | `Context context, JsonRpcId identifier, String reason` | `Result<Unit, Error>` | `InvalidArgument`/`Io`/`Cancelled`/`Unavailable` |
| `sessionIdentifier` | 无会话 | 无 | `String?` | 无（恒 null） |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |
| `notificationFailureCount` | 回调失败数 | 无 | `Int` | 无 |

说明：

- `request` 只接受带 id 请求；等待中收到响应 id 不匹配 → `DataCorrupted`；收到通知 → 回调并继续；收到服务器请求 → `Unsupported`。
- `selectProtocolVersion` 是 no-op：stdio 没有 HTTP 头；版本由 `McpClient` 在消息体/握手中间接决定。
- `notify`/`respond` 只接受相应方向消息；通知回调异常只计数，不终止读循环。
- `receive` 只返回请求/通知；收到响应 → `DataCorrupted`。
- `cancel` 对未知 id 幂等成功；不等待服务器确认。
- `close` 先置 open=false，再关闭流（如拥有）；读阻塞由关闭流唤醒。
- `notificationFailureCount` 只用于诊断；不包含异常详情。

---

## 8. 使用的技术

- 换行分隔 JSON；
- UTF-8；
- Mutex 写串行；
- 有界行读；
- Result/Context。

---

## 9. 需要的支撑

- 语言：class、String、Long、Int、Bool、Result；
- 运行时：`stdioReadLineRaw(Reader, Long, Context)`（有界行读；EOF null；超限 `DataCorrupted`）、`stdioWriteLineRaw(Writer, String, Long, Context)`（追加换行、writeAll、flush）；`Mutex<Bool>`；
- 接口：`Reader`、`Writer`、`Context`、`Mutex`、`Json`、`JsonRpcRequest`、`JsonRpcResponse`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Reader`、`Writer`、`Context`、`Mutex`、`Json`、`JsonRpcRequest`、`JsonRpcResponse`、`JsonRpcId`、`McpProtocolVersion`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`。

---

## 11. 所有权与并发

- 流：构造借用；`_ownsStreams` 为 true 时 close 拥有并关闭；false 时调用方关闭。
- `request`/`receive` 单消费者；不得并发。
- `notify`/`respond`/`cancel` 可并发，写由 `_writeMutex` 串行化。
- `close` 可与其他调用并发；关闭后调用 `Unavailable`。
- 不可重入：通知回调内不得再次调用 `request`/`receive`。

---

## 12. 示例与反例

正确：CLI 启动子进程 → `new McpStdioTransport(child.stdin, child.stdout)` → `client.initialize(context)`。  
反例：把日志写 stdout；消息里插入字面换行；两个任务同时 `request`；close 后继续写；把 stderr 当 JSON-RPC。

---

## 13. 测试/场景义务

单行请求/响应；通知；取消；大消息超限；缺换行 EOF；非法 JSON；id 不匹配；服务器主动请求；写并发交错；close 幂等；关闭后调用；回调失败计数；CRLF；空行。

---

## 14. XNull 伪代码

```xnull
class McpStdioTransport implements McpTransport {
    final Reader _input
    final Writer _output
    final Long _maximumMessageBytes
    final Bool _ownsStreams
    Bool _open
    final Mutex<Bool> _writeMutex
    Int _notificationFailures

    McpStdioTransport(Reader input, Writer output) {
        if input == null || output == null {
            throw "McpStdioTransport: null stream"
        }
        _input = input
        _output = output
        _maximumMessageBytes = 8388608L
        _ownsStreams = false
        _open = true
        _writeMutex = new Mutex<Bool>(false)
        _notificationFailures = 0
    }

    McpStdioTransport(Reader input, Writer output, Long maximumMessageBytes,
                      Bool ownsStreams, Int maximumConcurrentRequests) {
        if input == null || output == null {
            throw "McpStdioTransport: null stream"
        }
        if maximumMessageBytes <= 0 {
            throw "McpStdioTransport: non-positive maximum"
        }
        if maximumConcurrentRequests != 1 {
            throw "McpStdioTransport: concurrent requests unsupported"
        }
        _input = input
        _output = output
        _maximumMessageBytes = maximumMessageBytes
        _ownsStreams = ownsStreams
        _open = true
        _writeMutex = new Mutex<Bool>(false)
        _notificationFailures = 0
    }

    Result<Unit, Error> writeMessage(Context context, JsonValue message) {
        if context == null { throw "McpStdioTransport.writeMessage: null context" }
        String text = Json.stringify(message)
        String line = text + "\n"
        Long byteLength = toLong(fromUtf8(line).length())
        if byteLength > _maximumMessageBytes {
            return Err(new BasicError(ErrorKind.DataCorrupted,
                "McpStdioTransport: message too large"))
        }
        Result<Unit, Error> outcome = Ok(unit)
        Result<Unit, Error> locked = _writeMutex.withLock(context, void(Bool value) {
            Result<Unit, Error> written = stdioWriteLineRaw(_output, text,
                _maximumMessageBytes, context)
            if written.isErr() {
                outcome = written
                return
            }
            outcome = Ok(unit)
        })
        if locked.isErr() { return Err(locked.error()) }
        return outcome
    }

    Result<Unit, Error> selectProtocolVersion(Context context, McpProtocolVersion version) {
        if context == null || version == null {
            throw "McpStdioTransport.selectProtocolVersion: null argument"
        }
        if !_open { return Err(unavailableError("stdio transport")) }
        return Ok(unit)
    }

    Result<JsonRpcResponse, Error> request(Context context, JsonRpcRequest request,
        Result<Unit, Error>(Context, JsonRpcRequest) notificationHandler) {
        if context == null { throw "McpStdioTransport.request: null context" }
        if request == null || notificationHandler == null {
            throw "McpStdioTransport.request: null argument"
        }
        if request.isNotification() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpStdioTransport.request: notification"))
        }
        if !_open { return Err(unavailableError("stdio transport")) }
        Result<Unit, Error> sent = self.writeMessage(context, request.toJsonValue())
        if sent.isErr() { return Err(sent.error()) }
        while true {
            Result<String?, Error> line = stdioReadLineRaw(_input,
                _maximumMessageBytes, context)
            if line.isErr() { return Err(line.error()) }
            if line.value() == null {
                return Err(unavailableError("stdio transport closed"))
            }
            Result<JsonValue, Error> parsed = Json.parse(line.value())
            if parsed.isErr() { return Err(parsed.error()) }
            if !parsed.value().isObject() {
                return Err(new BasicError(ErrorKind.DataCorrupted,
                    "McpStdioTransport: non-object message"))
            }
            JsonObject object = parsed.value().asObject()
            if object.has("method") {
                Result<JsonRpcRequest, Error> incoming =
                    JsonRpcRequest.parse(parsed.value())
                if incoming.isErr() { return Err(incoming.error()) }
                if incoming.value().isNotification() {
                    Result<Unit, Error> handled =
                        notificationHandler(context, incoming.value())
                    if handled.isErr() {
                        _notificationFailures = _notificationFailures + 1
                    }
                    continue
                }
                return Err(new BasicError(ErrorKind.Unsupported,
                    "McpStdioTransport: server-initiated request"))
            }
            Result<JsonRpcResponse, Error> response =
                JsonRpcResponse.parse(parsed.value())
            if response.isErr() { return Err(response.error()) }
            if response.value().identifier() == null
                || !response.value().identifier().equals(request.identifier()) {
                return Err(new BasicError(ErrorKind.DataCorrupted,
                    "McpStdioTransport: response id mismatch"))
            }
            return response
        }
    }

    Result<Unit, Error> notify(Context context, JsonRpcRequest notification) {
        if context == null { throw "McpStdioTransport.notify: null context" }
        if notification == null { throw "McpStdioTransport.notify: null" }
        if !notification.isNotification() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "McpStdioTransport.notify: request with id"))
        }
        if !_open { return Err(unavailableError("stdio transport")) }
        return self.writeMessage(context, notification.toJsonValue())
    }

    Result<JsonRpcRequest, Error> receive(Context context) {
        if context == null { throw "McpStdioTransport.receive: null context" }
        if !_open { return Err(unavailableError("stdio transport")) }
        Result<String?, Error> line = stdioReadLineRaw(_input,
            _maximumMessageBytes, context)
        if line.isErr() { return Err(line.error()) }
        if line.value() == null {
            return Err(unavailableError("stdio transport closed"))
        }
        Result<JsonValue, Error> parsed = Json.parse(line.value())
        if parsed.isErr() { return Err(parsed.error()) }
        if !parsed.value().isObject() {
            return Err(new BasicError(ErrorKind.DataCorrupted,
                "McpStdioTransport: non-object message"))
        }
        if !parsed.value().asObject().has("method") {
            return Err(new BasicError(ErrorKind.DataCorrupted,
                "McpStdioTransport: unexpected response"))
        }
        return JsonRpcRequest.parse(parsed.value())
    }

    Result<Unit, Error> respond(Context context, JsonRpcResponse response) {
        if context == null { throw "McpStdioTransport.respond: null context" }
        if response == null { throw "McpStdioTransport.respond: null" }
        if !_open { return Err(unavailableError("stdio transport")) }
        return self.writeMessage(context, response.toJsonValue())
    }

    Result<Unit, Error> acknowledge(Context context) {
        if context == null { throw "McpStdioTransport.acknowledge: null context" }
        if !_open { return Err(unavailableError("stdio transport")) }
        return Ok(unit)
    }

    Result<Unit, Error> cancel(Context context, JsonRpcId identifier, String reason) {
        if context == null { throw "McpStdioTransport.cancel: null context" }
        if identifier == null { throw "McpStdioTransport.cancel: null identifier" }
        JsonObject parameters = new JsonObject()
        parameters.set("requestId", identifier.toJsonValue())
        if reason != "" { parameters.set("reason", JsonValue.string(reason)) }
        JsonRpcRequest notification = new JsonRpcRequest("notifications/cancelled",
            JsonValue.object(parameters))
        return self.notify(context, notification)
    }

    String? sessionIdentifier() { return null }
    Int notificationFailureCount() { return _notificationFailures }
    Bool isOpen() { return _open }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        if !_ownsStreams { return Ok(unit) }
        Result<Unit, Error> inputClosed = _input.close()
        Result<Unit, Error> outputClosed = _output.close()
        if inputClosed.isErr() { return Err(inputClosed.error()) }
        return outputClosed
    }
}
```
