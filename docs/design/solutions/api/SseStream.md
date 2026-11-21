# `SseStream`

| 项 | 值 |
| --- | --- |
| 类型 | `class SseStream implements ByteStream` |
| 包 | `xdk.api` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`HttpExchange`、`HttpResponse`、`HttpHeaders`、`HttpBody`、`HttpMethod`、`Bytes`、`JsonValue`、`TaskGroup`、`Task`、`RuntimeMonitor`、`Error` |

---

## 1. 定位

Server-Sent Events 流：打开 `text/event-stream` 响应，按 WHATWG 格式发送 `data`/`event`/`id`/`retry` 与注释，提供有界缓冲、反压、关闭与写任务等待。

不做：事件总线、历史重放、订阅 Hub、WebSocket、HTTP/2 Push、压缩、身份认证。

---

## 2. 设计逻辑

- `SseStream` 实现 `ByteStream`：HTTP 写任务从 `read` 端消费字节；应用通过 `send*` 写入同一对象。
- `open` 构造响应（200、`text/event-stream`、`no-cache`、禁用压缩/固定长度），启动独立写任务调用 `HttpExchange.respond`。
- 写任务读取 `SseStream` 直到 `close` 后缓冲排空，然后关闭交换。
- 应用发送事件时若缓冲满则阻塞；`Context` 取消/写截止时间返回 `Cancelled`/`Timeout`。
- 缓冲上限按字节计；单个事件大于上限直接 `InvalidArgument`，避免永久等待。
- `close` 只发结束信号，不等待；`await` 等待写任务并返回其失败。
- `close` 幂等；关闭后 `send*`/`write` 返回 `Unavailable`；`read` 先排空再 EOF。
- SSE 编码：UTF-8；`data` 多行拆分；`event`/`id` 禁止 CR/LF/NUL；`retry` 非负整数毫秒；注释以 `: ` 开头；空行分发。
- `Last-Event-ID` 由应用从 `ApiContext.header("Last-Event-ID")` 读取；流本身不保存历史。
- 写任务失败（客户端断开/IO）会设置 `_writerFailure`、关闭流并唤醒等待者。
- 无全局 Hub；每个请求一个流；无模板/JSON 对象映射。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_exchange` | `HttpExchange` | 底层交换 |
| `_maximumBufferedBytes` | `Long` | 缓冲上限，>0 |
| `_chunks` | `List<Bytes>` | 待读字节块 |
| `_chunkOffset` | `Int` | 首块已读偏移 |
| `_bufferedBytes` | `Long` | 待读总字节 |
| `_closed` | `Bool` | 是否停止写入 |
| `_writerFailure` | `Error?` | 写任务失败 |
| `_monitor` | `RuntimeMonitor` | 等待/通知 |
| `_readDeadlineMonoMillis` | `Long?` | 读截止 |
| `_writeDeadlineMonoMillis` | `Long?` | 写截止 |
| `_taskGroup` | `TaskGroup` | 写任务组 |
| `_writerTask` | `Task<Unit>?` | 写任务句柄 |

不变量：`_bufferedBytes` 等于所有块剩余字节和；`_closed` 后不再追加；`_writerFailure` 只在写任务结束后非 null；一个读者（写任务）与多个发送者通过 monitor 串行化。

---

## 4. 生命周期

`open` 创建并启动写任务；`send*`/`comment`/`setRetry` 写入；`close` 结束；`await` 等待写任务；close 幂等；写任务失败后不可恢复。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `open(Context context, HttpExchange exchange, Int status, HttpHeaders headers, Long maximumBufferedBytes)` | 全部非 null；status=200；max>0 | 非 HEAD、未响应 | `InvalidArgument`/`Unavailable`/`Io` |

构造器私有；业务代码通过 `ApiContext.openSse` 或 `SseStream.open` 创建。

---

## 6. 字段表

见 §3；字段私有。`_writerTask` 在 `open` 成功后设置一次；`_closed` 与 `_writerFailure` 由 monitor 保护。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `open` | 打开 SSE | `Context context, HttpExchange exchange, Int status, HttpHeaders headers, Long maximumBufferedBytes` | `Result<SseStream, Error>` | `InvalidArgument`/`Unavailable`/`Io` |
| `send` | 默认事件 | `Context context, String data` | `Result<Unit, Error>` | `Unavailable`/`Cancelled`/`Timeout`/`InvalidArgument` |
| `sendEvent` | 命名事件 | `Context context, String eventName, String data` | `Result<Unit, Error>` | 同上 |
| `sendEventWithId` | 命名+ID 事件 | `Context context, String eventName, String data, String eventId` | `Result<Unit, Error>` | 同上 |
| `sendJson` | JSON 默认事件 | `Context context, JsonValue value` | `Result<Unit, Error>` | 同上 |
| `sendJsonEvent` | JSON 命名事件 | `Context context, String eventName, JsonValue value` | `Result<Unit, Error>` | 同上 |
| `comment` | 注释/心跳 | `Context context, String text` | `Result<Unit, Error>` | 同上 |
| `setRetry` | 重连毫秒 | `Context context, Long retryMillis` | `Result<Unit, Error>` | 同上 |
| `bufferedBytes` | 当前缓冲 | 无 | `Long` | 无 |
| `maximumBufferedBytes` | 缓冲上限 | 无 | `Long` | 无 |
| `isOpen` | 是否可写 | 无 | `Bool` | 无 |
| `close` | 结束写入 | 无 | `Result<Unit, Error>` | 无 |
| `await` | 等待写任务 | `Context context` | `Result<Unit, Error>` | 写任务错误 |
| `read` | 读字节（ByteStream） | `Context context, Bytes buffer` | `Result<Int, Error>` | `InvalidArgument`/`Unavailable`/`Timeout`/`Cancelled` |
| `write` | 写字节（ByteStream） | `Context context, Bytes data` | `Result<Int, Error>` | 同上 |
| `writeAll` | 写全（ByteStream） | `Context context, Bytes data` | `Result<Unit, Error>` | 同上 |
| `setReadDeadline` | 读截止 | `Long deadlineMonoMillis` | `Result<Unit, Error>` | `InvalidArgument` |
| `setWriteDeadline` | 写截止 | `Long deadlineMonoMillis` | `Result<Unit, Error>` | `InvalidArgument` |

说明：

- `send`/`sendEvent`/`sendEventWithId` 的 data 多行会被拆成多行 `data:`。
- `sendEventWithId` 的 `eventId` 允许空串；空 `id:` 按 SSE 语义重置客户端 `Last-Event-ID`。
- `sendJson` 使用 `Json.stringify`；JSON 内的换行是转义序列，不拆行。
- `comment` 的每行加 `: ` 前缀；用于心跳时发送 `comment(context, "")`。
- `setRetry` 写 `retry: <ms>` 并空行；`retryMillis` ≥0。
- `write` 成功返回写入字节数；本实现总是全写或错误。空 data 返回 0。
- `read` 只有在关闭且缓冲排空后返回 0；`buffer` 不能为空。
- `await` 可多次调用；等待写任务完成后读取失败。
- `await` 以传输收尾为先：先 `close` 再等待写任务，不用 `Context` 中断等待，避免遗留写任务；`Context` 用于入口校验。
- `close` 不等待写任务；`await` 才等待。
- 写任务失败后 `send*` 返回失败或 `Unavailable`；不能恢复。

---

## 8. 使用的技术

- SSE 事件格式；
- 有界字节队列；
- 反压与 monitor；
- 单调截止；
- 独立写任务；
- 幂等关闭；
- ByteStream 协议。

---

## 9. 需要的支撑

- 语言：class、protocol 实现、List、String、Int、Long、Bool、Result；
- 运行时：`RuntimeMonitor` 的 `enter/exit/notifyAll`；`sseWaitRaw(RuntimeMonitor, Context, Long?)` 截止感知等待（内部运行原语，返回 `Timeout`/`Cancelled`）；`TaskGroup.spawn`、`Task.awaitDone`、`Task.failure`；
- 接口：`Context`、`HttpExchange`、`HttpResponse`、`HttpHeaders`、`HttpBody`、`HttpMethod`、`Bytes`、`JsonValue`、`Json`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`、`cancelledError`、`copy`、`toLong`、`str`。

---

## 10. 依赖的特性/接口/类

`Context`、`HttpExchange`、`HttpResponse`、`HttpHeaders`、`HttpBody`、`HttpMethod`、`Bytes`、`Json`、`JsonValue`、`TaskGroup`、`Task`、`RuntimeMonitor`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`、`cancelledError`。

---

## 11. 所有权与并发

引用语义；拥有写任务与缓冲；HTTP 写任务单读者；`send*` 多写者由 monitor 串行化；`close`/`await` 可与发送并发；无全局状态；关闭幂等；写任务失败不可恢复。

---

## 12. 示例与反例

正确：

```text
Result<SseStream, Error> opened = exchange.openSse(context)
if opened.isErr() { return Err(opened.error()) }
SseStream stream = opened.value()
stream.sendEvent(context, "tick", "1")
stream.sendJson(context, JsonValue.string("done"))
stream.close()
return Ok(unit)
```

反例：

- 在 `open` 前发送事件；
- 发送超过缓冲上限的单个事件；
- 不 `close` 直接返回（服务器会兜底，但语义不清）；
- 在 `close` 后继续发送；
- 把密码/令牌放进事件 id；
- 依赖流内建历史重放；
- 设置 `Content-Encoding` 压缩事件流；
- 省略空行导致客户端不分发。

---

## 13. 测试/场景义务

打开/响应头/状态；默认/命名/带 ID 事件；多行 data；空 data；注释/心跳；retry；JSON；关闭排空/EOF；close 幂等；await 失败；缓冲上限/并发发送/反压；取消/读超时/写超时；客户端断开；HEAD 拒绝；已响应拒绝。

---

## 14. XNull 伪代码

> 非可执行设计伪代码。

```xnull
class SseStream implements ByteStream {
    final HttpExchange _exchange
    final Long _maximumBufferedBytes
    List<Bytes> _chunks = []
    Int _chunkOffset = 0
    Long _bufferedBytes = 0
    Bool _closed = false
    Error? _writerFailure = null
    final RuntimeMonitor _monitor
    Long? _readDeadlineMonoMillis = null
    Long? _writeDeadlineMonoMillis = null
    final TaskGroup _taskGroup
    Task<Unit>? _writerTask = null

    private SseStream(Context context, HttpExchange exchange,
                      Long maximumBufferedBytes) {
        _exchange = exchange
        _maximumBufferedBytes = maximumBufferedBytes
        _monitor = new RuntimeMonitor()
        _taskGroup = TaskGroup.create(context)
    }

    static Result<SseStream, Error> open(Context context, HttpExchange exchange,
                                         Int status, HttpHeaders headers,
                                         Long maximumBufferedBytes) {
        if context == null || exchange == null || headers == null {
            throw "SseStream.open: null argument"
        }
        if maximumBufferedBytes <= 0 {
            throw "SseStream.open: invalid buffer size"
        }
        if status != 200 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SSE requires status 200"))
        }
        if exchange.request().method() == HttpMethod.Head {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SSE is not available for HEAD"))
        }
        if exchange.isResponded() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "exchange already responded"))
        }
        SseStream stream = new SseStream(context, exchange, maximumBufferedBytes)
        Result<Unit, Error> started = stream.startWriter(context, status, headers)
        if started.isErr() {
            stream.close()
            return Err(started.error())
        }
        return Ok(stream)
    }

    private Result<Unit, Error> startWriter(Context context, Int status,
                                            HttpHeaders headers) {
        HttpHeaders responseHeaders = headers.copy()
        responseHeaders.set("Content-Type", "text/event-stream; charset=utf-8")
        responseHeaders.set("Cache-Control", "no-cache")
        responseHeaders.set("X-Accel-Buffering", "no")
        responseHeaders.remove("Content-Encoding")
        responseHeaders.remove("Content-Length")
        HttpBody body = HttpBody.fromStream(self, null)
        HttpResponse response = HttpResponse.of(status)
            .withHeaders(responseHeaders)
            .withBody(body)
        Result<Task<Unit>, Error> spawned = _taskGroup.spawn(context,
            (Context taskContext) -> {
                Result<Unit, Error> written = _exchange.respond(response)
                if written.isErr() {
                    _writerFailure = written.error()
                    self.close()
                    _exchange.close()
                    return Err(written.error())
                }
                self.close()
                _exchange.close()
                return Ok(unit)
            })
        if spawned.isErr() { return Err(spawned.error()) }
        _writerTask = spawned.value()
        return Ok(unit)
    }

    Result<Unit, Error> send(Context context, String data) {
        return self.sendFrame(context, null, data, null)
    }

    Result<Unit, Error> sendEvent(Context context, String eventName, String data) {
        if eventName == null || eventName == "" {
            throw "SseStream.sendEvent: empty event name"
        }
        return self.sendFrame(context, eventName, data, null)
    }

    Result<Unit, Error> sendEventWithId(Context context, String eventName,
                                        String data, String eventId) {
        if eventName == null || eventName == "" {
            throw "SseStream.sendEventWithId: empty event name"
        }
        if eventId == null {
            throw "SseStream.sendEventWithId: null event id"
        }
        return self.sendFrame(context, eventName, data, eventId)
    }

    Result<Unit, Error> sendJson(Context context, JsonValue value) {
        if context == null || value == null {
            throw "SseStream.sendJson: null argument"
        }
        return self.send(context, Json.stringify(value))
    }

    Result<Unit, Error> sendJsonEvent(Context context, String eventName,
                                      JsonValue value) {
        if context == null || eventName == null || eventName == ""
            || value == null {
            throw "SseStream.sendJsonEvent: invalid argument"
        }
        return self.sendEvent(context, eventName, Json.stringify(value))
    }

    private Result<Unit, Error> sendFrame(Context context, String? eventName,
                                          String data, String? eventId) {
        if context == null || data == null {
            throw "SseStream.sendFrame: null argument"
        }
        String payload = ""
        if eventName != null {
            String eventValue = eventName as String
            self.validateField(eventValue, "event")
            payload = payload + "event: " + eventValue + "\n"
        }
        if eventId != null {
            String idValue = eventId as String
            self.validateField(idValue, "id")
            payload = payload + "id: " + idValue + "\n"
        }
        String normalized = data.replace("\r\n", "\n").replace("\r", "\n")
        List<String> lines = normalized.split("\n")
        Int index = 0
        while index < lines.length() {
            payload = payload + "data: " + lines.get(index) + "\n"
            index = index + 1
        }
        payload = payload + "\n"
        return self.writeAll(context, Bytes.fromUtf8(payload))
    }

    private void validateField(String value, String fieldName) {
        if value.indexOf("\n") >= 0 || value.indexOf("\r") >= 0
            || value.indexOf("\u0000") >= 0 {
            throw "SseStream: invalid " + fieldName + " field"
        }
    }

    Result<Unit, Error> comment(Context context, String text) {
        if context == null || text == null {
            throw "SseStream.comment: null argument"
        }
        String normalized = text.replace("\r\n", "\n").replace("\r", "\n")
        List<String> lines = normalized.split("\n")
        String payload = ""
        Int index = 0
        while index < lines.length() {
            payload = payload + ": " + lines.get(index) + "\n"
            index = index + 1
        }
        payload = payload + "\n"
        return self.writeAll(context, Bytes.fromUtf8(payload))
    }

    Result<Unit, Error> setRetry(Context context, Long retryMillis) {
        if context == null { throw "SseStream.setRetry: null context" }
        if retryMillis < 0 {
            throw "SseStream.setRetry: negative retry"
        }
        String payload = "retry: " + str(retryMillis) + "\n\n"
        return self.writeAll(context, Bytes.fromUtf8(payload))
    }

    Long bufferedBytes() {
        _monitor.enter()
        Long value = _bufferedBytes
        _monitor.exit()
        return value
    }

    Long maximumBufferedBytes() { return _maximumBufferedBytes }

    Bool isOpen() {
        _monitor.enter()
        Bool value = !_closed
        _monitor.exit()
        return value
    }

    Result<Unit, Error> close() {
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return Ok(unit)
        }
        _closed = true
        _monitor.notifyAll()
        _monitor.exit()
        return Ok(unit)
    }

    Result<Unit, Error> await(Context context) {
        if context == null { throw "SseStream.await: null context" }
        self.close()
        Task<Unit>? task = _writerTask
        if task == null { return Ok(unit) }
        task.awaitDone()
        Result<Unit, Error> group = _taskGroup.close()
        Error? failure = task.failure()
        if failure != null { return Err(failure as Error) }
        if group.isErr() { return Err(group.error()) }
        return Ok(unit)
    }

    Result<Int, Error> read(Context context, Bytes buffer) {
        if context == null || buffer == null {
            throw "SseStream.read: null argument"
        }
        if context.isCancelled() {
            return Err(cancelledError("sse stream read"))
        }
        if buffer.length() == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "empty read buffer"))
        }
        _monitor.enter()
        while true {
            if _writerFailure != null {
                Error failure = _writerFailure as Error
                _monitor.exit()
                return Err(failure)
            }
            if !_chunks.isEmpty() {
                Bytes head = _chunks.get(0)
                Int available = head.length() - _chunkOffset
                Int count = available
                if count > buffer.length() { count = buffer.length() }
                Int index = 0
                while index < count {
                    buffer.set(index, head.get(_chunkOffset + index))
                    index = index + 1
                }
                _chunkOffset = _chunkOffset + count
                if _chunkOffset >= head.length() {
                    _chunks.remove(0)
                    _chunkOffset = 0
                }
                _bufferedBytes = _bufferedBytes - toLong(count)
                _monitor.notifyAll()
                _monitor.exit()
                return Ok(count)
            }
            if _closed {
                _monitor.exit()
                return Ok(0)
            }
            Result<Unit, Error> waited = sseWaitRaw(_monitor, context,
                _readDeadlineMonoMillis)
            if waited.isErr() {
                _monitor.exit()
                return Err(waited.error())
            }
        }
    }

    Result<Int, Error> write(Context context, Bytes data) {
        if context == null || data == null {
            throw "SseStream.write: null argument"
        }
        if context.isCancelled() {
            return Err(cancelledError("sse stream write"))
        }
        if data.length() == 0 { return Ok(0) }
        Long size = toLong(data.length())
        if size > _maximumBufferedBytes {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "SSE event exceeds buffer limit"))
        }
        _monitor.enter()
        if _writerFailure != null {
            Error failure = _writerFailure as Error
            _monitor.exit()
            return Err(failure)
        }
        while _bufferedBytes + size > _maximumBufferedBytes {
            if _writerFailure != null {
                Error failure = _writerFailure as Error
                _monitor.exit()
                return Err(failure)
            }
            if _closed {
                _monitor.exit()
                return Err(unavailableError("sse stream"))
            }
            Result<Unit, Error> waited = sseWaitRaw(_monitor, context,
                _writeDeadlineMonoMillis)
            if waited.isErr() {
                _monitor.exit()
                return Err(waited.error())
            }
        }
        if _closed {
            _monitor.exit()
            return Err(unavailableError("sse stream"))
        }
        _chunks.push(copy(data))
        _bufferedBytes = _bufferedBytes + size
        _monitor.notifyAll()
        _monitor.exit()
        return Ok(data.length())
    }

    Result<Unit, Error> writeAll(Context context, Bytes data) {
        Result<Int, Error> written = self.write(context, data)
        if written.isErr() { return Err(written.error()) }
        if written.value() != data.length() {
            return Err(new BasicError(ErrorKind.Io, "SSE short write"))
        }
        return Ok(unit)
    }

    Result<Unit, Error> setReadDeadline(Long deadlineMonoMillis) {
        if deadlineMonoMillis < 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "negative read deadline"))
        }
        _monitor.enter()
        _readDeadlineMonoMillis = deadlineMonoMillis
        _monitor.notifyAll()
        _monitor.exit()
        return Ok(unit)
    }

    Result<Unit, Error> setWriteDeadline(Long deadlineMonoMillis) {
        if deadlineMonoMillis < 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "negative write deadline"))
        }
        _monitor.enter()
        _writeDeadlineMonoMillis = deadlineMonoMillis
        _monitor.notifyAll()
        _monitor.exit()
        return Ok(unit)
    }
}
```

> `TaskGroup.create` 使用 `open` 的 `context` 作为父上下文。`sseWaitRaw` 是内部截止等待原语，不是公开类型。
