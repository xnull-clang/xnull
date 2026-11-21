# `OtlpExporter`

| 项 | 值 |
| --- | --- |
| 类型 | `class OtlpExporter implements Exporter` |
| 包 | `xdk.agent` |
| 稳定性 | `preview` |
| 依赖 | `Exporter`、`TelemetryKind`、`TelemetryBatch`、`HttpClient`、`HttpRequest`、`HttpResponse`、`HttpBody`、`RetryPolicy`、`Timer`、`Context`、`Error` |

---

## 1. 定位

OTLP 导出器：把 Metrics/Traces/Logs 批次编码为 OTLP/HTTP JSON，按端点推送，带队列、超时、重试与 drain。

它对齐 OTel `otlp` exporter 的推送语义；基线只做 OTLP/HTTP JSON，不做 gRPC/protobuf。

不做：OTLP/gRPC、OTLP/protobuf、OTLP/file、TLS 自动化、认证扩展、服务发现、持久化队列、
后端厂商 SDK。

---

## 2. 设计逻辑

- 实现 `Exporter`；`kind()` 由构造器固定，一个实例只导一种信号；
- endpoint 是基础 URL；按 kind 追加 `/v1/metrics`、`/v1/traces`、`/v1/logs`；
- 协议基线只接受 `http_json`；其他值构造时拒绝；
- `export` 将批次放入有界队列并立即返回；工作线程串行发送；
- 队列满：`reject` 返回 `Busy`；`drop_oldest`/`drop_newest` 丢弃并计数；
- 发送失败按 `RetryPolicy` 重试；可重试分类为 `Network`/`Timeout`/`Unavailable`/`Busy`；
  非可重试错误直接失败并计入丢弃；
- 重试耗尽或永久失败：批次丢弃并计数，`isHealthy=false`；连续成功后恢复；
- `drain` 等待队列清空与在途发送完成；取消返回 `Cancelled`；
- `close` 停止工作线程、关闭 HttpClient、丢弃未发送批次并计数；幂等；
- 语义 at-least-once：重试可能重复；OTLP 接收端需容忍重复；
- 不拥有调用方注入的 HttpClient（若提供）；默认自建并关闭。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 非空、单行 |
| `_kind` | `TelemetryKind` | 非 null |
| `_endpoint` | `String` | 非空绝对 URL（不含 `/v1/*`） |
| `_protocol` | `String` | 固定 `http_json` |
| `_headers` | `Map<String,String>` | 构造时复制 |
| `_requestTimeoutMillis` | `Long` | >0 |
| `_compression` | `String` | 基线 `none` |
| `_retryPolicy` | `RetryPolicy` | 非 null |
| `_queueCapacity` | `Int` | >0 |
| `_overflowPolicy` | `String` | `reject`/`drop_oldest`/`drop_newest` |
| `_client` | `HttpClient?` | start 后非 null |
| `_group` | `TaskGroup?` | start 后非 null；工作线程 |
| `_queue` | `List<TelemetryBatch>` | 有界 |
| `_sending` | `Bool` | 是否有在途请求 |
| `_started` | `Bool` | start 后 true |
| `_closed` | `Bool` | 只从 false 变 true |
| `_healthy` | `Bool` | 最近发送是否成功 |
| `_failureCount` | `Int` | 连续失败次数 |
| `_sentBatches` | `Int` | ≥0 |
| `_droppedBatches` | `Int` | ≥0 |
| `_failedRequests` | `Int` | ≥0 |
| `_lastError` | `String` | 可为空；不含 token |
| `_requestTimer` | `Timer` | 请求超时包装；导出器拥有 |
| `_monitor` | `RuntimeMonitor` | 队列/状态保护 |

不变量：队列长度 ≤ queueCapacity；一个工作线程；发送串行；close 后不再入队/发送；
丢弃有计数；健康状态可读；headers 复制；错误描述不包含认证头。

---

## 4. 生命周期

```text
构造 → start（创建 HttpClient/工作线程）→ export（入队）→ 工作线程发送/重试 → drain → close
```

- `start`：创建 HttpClient、TaskGroup，启动 worker；重复 start 返回 `Ok(unit)`；
- `export`：入队；满时按策略；工作线程异步发送；
- `drain`：等待队列空与在途完成；可重复；取消返回 `Cancelled`；
- `close`：置关闭、唤醒 worker、取消 TaskGroup、关闭 HttpClient、丢弃队列并计数；幂等；
- 关闭后 `start`/`export`/`drain` 返回 `Unavailable`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `OtlpExporter` | `String name, TelemetryKind kind, String endpoint, String protocol, Map<String,String> headers, Long requestTimeoutMillis, String compression, RetryPolicy retryPolicy, Int queueCapacity, String overflowPolicy` | name/endpoint 非空；kind 非 null；protocol=`http_json`；timeout >0；compression=`none`；retry 非 null；queue >0；policy 合法 | 非法 → panic |

说明：

- endpoint 必须是 `http://` 或 `https://` 的绝对 URL；不自动拼接路径；
- 基线不支持 `gzip`；压缩留 X；`Content-Encoding` 不由本包设置；
- 固定请求头 `Content-Type: application/json`；用户 headers 追加/覆盖；
- `RetryPolicy` 复用 `xdk.errors`，不复制退避算法；
- `name` 同一 Agent 内唯一，通常为 `"otlp"`；
- `queueCapacity` 是批次数，不是记录数；记录数由批次大小与上游批处理器控制。

---

## 6. 字段表

见 §3；配置字段为 `final`；运行状态由监视器保护。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `kind` | 遥测种类 | 无 | `TelemetryKind` | 无 |
| `name` | 导出器名 | 无 | `String` | 无 |
| `start` | 启动发送 | `Context context` | `Result<Unit, Error>` | `Network`/`Timeout`/`Cancelled`/`Unavailable` |
| `export` | 入队 | `Context context, TelemetryBatch batch` | `Result<Unit, Error>` | `Busy`/`Cancelled`/`Unavailable` |
| `drain` | 等待队列清空 | `Context context` | `Result<Unit, Error>` | `Timeout`/`Cancelled`/`Unavailable` |
| `close` | 停止/关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isHealthy` | 是否健康 | 无 | `Bool` | 无 |
| `queueLength` | 当前队列长度 | 无 | `Int` | 无 |
| `sentBatches` | 已发送批次数 | 无 | `Int` | 无 |
| `droppedBatches` | 丢弃批次数 | 无 | `Int` | 无 |
| `failedRequests` | 失败请求数 | 无 | `Int` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |

说明：

- `start` 对 null context → panic；已关闭 → `Unavailable`；重复 start → `Ok(unit)`；
- `export` 对 null context/batch → panic；kind 不匹配 → panic；未启动/关闭 → `Unavailable`；
- 入队满：`reject` 返回 `Busy`；`drop_oldest` 移除队首并丢弃计数；`drop_newest` 丢弃新批次；
- worker 串行发送；失败按 `RetryPolicy`；每次尝试使用 `requestTimeoutMillis` 的子上下文；
- 2xx 成功；4xx 非可重试失败；5xx/网络/超时按策略重试；
- `drain` 对 null context → panic；未启动/关闭 → `Unavailable`；等待队列空且 `_sending=false`；
- `close` 幂等；已关闭返回 `Ok(unit)`；丢弃队列中未发送批次并计数；
- `isHealthy` 未启动/关闭为 false；连续失败 ≥3 为 false；成功一次恢复 true；
- `queueLength`/计数可并发读取。

### 7.1 OTLP 线格式映射

| kind | OTLP/HTTP 路径 | 顶层字段 | 记录映射 |
| --- | --- | --- | --- |
| Metrics | `/v1/metrics` | `resourceMetrics` | `MetricFamily` → `scopeMetrics.metrics`；Gauge/Counter/Histogram 按 `MetricKind` |
| Traces | `/v1/traces` | `resourceSpans` | `TelemetryRecord` span 字段 → `scopeSpans.spans` |
| Logs | `/v1/logs` | `resourceLogs` | `LogRecord` → `scopeLogs.logRecords` |

字段约定：

- 资源属性来自 `TelemetryBatch.resource()`；span/log 属性来自记录字段；
- Metrics 的 `MetricSample.labels()` 变为 data point attributes；`value` 为数值；
  Histogram/Timer 的桶/总和/计数由 `MetricFamily` 样本名约定导出；
- Traces 的 trace/span/parent-span 标识来自 `SpanContext`；时间由 `timestampMono` 与
  `spanDurationMillis` 推导；状态来自 `SpanStatus`；事件来自 `SpanEvent`；
- Logs 的 body 为 `LogRecord.message()`；severity 为 `Level`；时间戳为双时间戳；
- 基线不支持 exemplars、tracestate、span links；
- 编码由内部 `otlpEncodeRaw(batch)` 完成，不暴露编码器类型。

---

## 8. 使用的技术

- 有界发送队列；
- 工作线程；
- OTLP/HTTP JSON；
- RetryPolicy 退避；
- 超时子上下文；
- at-least-once；
- 幂等关闭；
- 健康/丢弃计数。

---

## 9. 需要的支撑

- 语言：class、String、Int、Long、Bool、List、Map、Result；
- 运行时：`TaskGroup.create/spawn/close`、`RuntimeMonitor`、`Context.withCancel`、
  `Timer.after/cancel/shutdown`、`nowMono`；
- 接口：`HttpClient`、`HttpRequest`、`HttpResponse`、`HttpBody`、`HttpStatus`、`Uri`、`RetryPolicy`、
  `TelemetryKind`、`TelemetryBatch`、`Error`、`BasicError`、`ErrorKind`、`sleepMs`；
- 内部原语：`otlpEncodeRaw(TelemetryBatch)` → `Result<Bytes, Error>`。

---

## 10. 依赖的特性/接口/类

`Exporter`、`TelemetryKind`、`TelemetryBatch`、`HttpClient`、`HttpRequest`、`HttpResponse`、
`HttpBody`、`HttpStatus`、`HttpMethod`、`Uri`、`Bytes`、`RetryPolicy`、`TaskGroup`、`Task`、
`Timer`、`Duration`、`Context`、`RuntimeMonitor`、`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

- 导出器拥有队列、worker、自建 HttpClient；不拥有调用方注入的 HttpClient；
- `export` 可并发；队列/计数由监视器保护；
- 只有一个 worker；发送串行；`drain` 与 worker 通过监视器等待/通知；
- `close` 可并发；关闭后快速失败；
- `isHealthy`/计数/队列长度可并发读取；
- 同一实例可被多条管线共享（fan-out），但基线建议一条管线一个实例；
- 不记录 headers/token 到错误/描述。

---

## 12. 示例与反例

正确：

```xnull
OtlpExporter exporter = new OtlpExporter(
    "otlp",
    TelemetryKind.Metrics,
    "https://otel.example.com:4318",
    "http_json",
    ["authorization":"Bearer <token>"],
    5000,
    "none",
    new RetryPolicy(),
    1024,
    "reject"
)
Result<Unit, Error> started = exporter.start(context)
if started.isErr() { return started }
Result<Unit, Error> exported = exporter.export(context, batch)
if exported.isErr() { return exported }
Result<Unit, Error> drained = exporter.drain(context)
exporter.close()
```

反例：export 同步阻塞到网络完成；队列满静默丢；4xx 无限重试；把 token 写进错误；
close 不关闭自建 HttpClient；gRPC 端点配 `http_json`；把 OTLP 编码器暴露为公共类型。

---

## 13. 测试/场景义务

构造校验（endpoint/protocol/compression/queue/policy）；start 重复；export 入队/满队列三策略；
worker 发送成功/2xx/4xx/5xx/网络/超时；RetryPolicy 次数/耗尽；request timeout；drain 队列空/在途/
取消；close 幂等/丢弃计数；未启动 export/drain；kind 不匹配；headers/Content-Type；健康恢复；
并发 export；不泄露 token；describe。

---

## 14. XNull 伪代码

```xnull
class OtlpExporter implements Exporter {
    final String _name
    final TelemetryKind _kind
    final String _endpoint
    final String _protocol
    final Map<String, String> _headers
    final Long _requestTimeoutMillis
    final String _compression
    final RetryPolicy _retryPolicy
    final Int _queueCapacity
    final String _overflowPolicy
    HttpClient? _client
    TaskGroup? _group
    List<TelemetryBatch> _queue = []
    Bool _sending = false
    Bool _started = false
    Bool _closed = false
    Bool _healthy = false
    Int _failureCount = 0
    Int _sentBatches = 0
    Int _droppedBatches = 0
    Int _failedRequests = 0
    String _lastError = ""
    final Timer _requestTimer
    final RuntimeMonitor _monitor

    OtlpExporter(String name, TelemetryKind kind, String endpoint,
                 String protocol, Map<String, String> headers,
                 Long requestTimeoutMillis, String compression,
                 RetryPolicy retryPolicy, Int queueCapacity,
                 String overflowPolicy) {
        if name == null || name == "" {
            throw "OtlpExporter: empty name"
        }
        if kind == null { throw "OtlpExporter: null kind" }
        if endpoint == null || endpoint == "" {
            throw "OtlpExporter: empty endpoint"
        }
        if protocol != "http_json" {
            throw "OtlpExporter: unsupported protocol"
        }
        if requestTimeoutMillis <= 0 {
            throw "OtlpExporter: timeout <= 0"
        }
        if compression != "none" {
            throw "OtlpExporter: unsupported compression"
        }
        if retryPolicy == null {
            throw "OtlpExporter: null retry policy"
        }
        if queueCapacity <= 0 {
            throw "OtlpExporter: queue capacity <= 0"
        }
        if overflowPolicy != "reject" && overflowPolicy != "drop_oldest"
            && overflowPolicy != "drop_newest" {
            throw "OtlpExporter: invalid overflow policy"
        }
        _name = name
        _kind = kind
        _endpoint = endpoint
        _protocol = protocol
        _headers = headers.copy()
        _requestTimeoutMillis = requestTimeoutMillis
        _compression = compression
        _retryPolicy = retryPolicy
        _queueCapacity = queueCapacity
        _overflowPolicy = overflowPolicy
        _requestTimer = new Timer()
        _monitor = new RuntimeMonitor()
    }

    TelemetryKind kind() { return _kind }
    String name() { return _name }
    Bool isHealthy() { return _started && !_closed && _healthy }
    Int queueLength() { return _queue.length() }
    Int sentBatches() { return _sentBatches }
    Int droppedBatches() { return _droppedBatches }
    Int failedRequests() { return _failedRequests }

    Result<Unit, Error> start(Context context) {
        if context == null { throw "OtlpExporter.start: null context" }
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "closed"))
        }
        if _started {
            _monitor.exit()
            return Ok(unit)
        }
        _client = new HttpClient()
        _group = TaskGroup.create(context)
        Result<Task<Unit>, Error> spawned = _group.spawn(
            (Context workerContext) -> self.workerLoop(workerContext))
        if spawned.isErr() {
            _group.close()
            _client.close()
            _client = null
            _group = null
            _monitor.exit()
            return Err(spawned.error())
        }
        _started = true
        _healthy = true
        _monitor.exit()
        return Ok(unit)
    }

    Result<Unit, Error> export(Context context, TelemetryBatch batch) {
        if context == null { throw "OtlpExporter.export: null context" }
        if batch == null { throw "OtlpExporter.export: null batch" }
        if batch.kind() != _kind {
            throw "OtlpExporter.export: batch kind mismatch"
        }
        _monitor.enter()
        if !_started || _closed {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "not running"))
        }
        if _queue.length() >= _queueCapacity {
            if _overflowPolicy == "reject" {
                _monitor.exit()
                return Err(new BasicError(ErrorKind.Busy, "export queue full"))
            }
            if _overflowPolicy == "drop_newest" {
                _droppedBatches = _droppedBatches + 1
                _monitor.exit()
                return Ok(unit)
            }
            TelemetryBatch oldest = _queue.get(0)
            _queue.removeAt(0)
            _droppedBatches = _droppedBatches + 1
        }
        _queue.push(batch)
        _monitor.notifyAll()
        _monitor.exit()
        return Ok(unit)
    }

    Result<Unit, Error> drain(Context context) {
        if context == null { throw "OtlpExporter.drain: null context" }
        _monitor.enter()
        if !_started || _closed {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "not running"))
        }
        while _queue.length() > 0 || _sending {
            if context.isCancelled() {
                _monitor.exit()
                return Err(new BasicError(ErrorKind.Cancelled, "cancelled"))
            }
            Bool woke = _monitor.wait(context)
            if !woke {
                _monitor.exit()
                return Err(new BasicError(ErrorKind.Cancelled, "cancelled"))
            }
        }
        _monitor.exit()
        return Ok(unit)
    }

    Result<Unit, Error> close() {
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return Ok(unit)
        }
        _closed = true
        _started = false
        _droppedBatches = _droppedBatches + _queue.length()
        _queue = []
        _monitor.notifyAll()
        _monitor.exit()
        if _group != null { _group.close() }
        if _client != null { _client.close() }
        _requestTimer.shutdown()
        _group = null
        _client = null
        return Ok(unit)
    }

    Result<Unit, Error> workerLoop(Context context) {
        while true {
            _monitor.enter()
            while _queue.length() == 0 && !_closed {
                Bool woke = _monitor.wait(context)
                if !woke {
                    _monitor.exit()
                    return Ok(unit)
                }
            }
            if _closed && _queue.length() == 0 {
                _monitor.exit()
                return Ok(unit)
            }
            TelemetryBatch batch = _queue.get(0)
            _queue.removeAt(0)
            _sending = true
            _monitor.exit()
            Result<Unit, Error> sent = self.sendWithRetry(context, batch)
            _monitor.enter()
            _sending = false
            if sent.isErr() {
                _droppedBatches = _droppedBatches + 1
                _failedRequests = _failedRequests + 1
                _failureCount = _failureCount + 1
                _healthy = _failureCount < 3
                _lastError = sent.error().describe()
            } else {
                _sentBatches = _sentBatches + 1
                _failureCount = 0
                _healthy = true
            }
            _monitor.notifyAll()
            _monitor.exit()
        }
        return Ok(unit)
    }

    Result<Unit, Error> sendWithRetry(Context context, TelemetryBatch batch) {
        if _client == null {
            return Err(new BasicError(ErrorKind.Unavailable, "no client"))
        }
        Result<Bytes, Error> encoded = otlpEncodeRaw(batch)
        if encoded.isErr() { return Err(encoded.error()) }
        String path = self.pathFor(_kind)
        Uri uri = Uri.parse(_endpoint + path)
        HttpRequest request = new HttpRequest(HttpMethod.Post, uri)
            .withHeader("Content-Type", "application/json")
            .withBody(HttpBody.fromBytes(encoded.value()))
        List<String> headerNames = _headers.keys()
        Int headerIndex = 0
        while headerIndex < headerNames.length() {
            String headerName = headerNames.get(headerIndex)
            request = request.withHeader(headerName,
                _headers.getOr(headerName, ""))
            headerIndex = headerIndex + 1
        }
        Int attempt = 1
        Error? lastError = null
        while attempt <= _retryPolicy.maxAttempts() {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled, "cancelled"))
            }
            Context requestContext = Context.withCancel(context)
            Long timeoutHandle = _requestTimer.after(requestContext,
                Duration.ofMillis(_requestTimeoutMillis),
                () -> requestContext.cancel())
            Result<HttpResponse, Error> response =
                _client.request(requestContext, request)
            _requestTimer.cancel(timeoutHandle)
            if response.isErr() {
                if requestContext.isCancelled() && !context.isCancelled() {
                    lastError = new BasicError(ErrorKind.Timeout,
                        "otlp request timeout")
                } else {
                    lastError = response.error()
                }
            } else if response.value().status().isSuccess() {
                return Ok(unit)
            } else if response.value().status().isClientError() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "otlp client error"))
            } else {
                lastError = new BasicError(ErrorKind.Unavailable,
                    "otlp server error")
            }
            if lastError != null && !_retryPolicy.shouldRetry(lastError, attempt) {
                return Err(lastError)
            }
            attempt = attempt + 1
            if attempt <= _retryPolicy.maxAttempts() {
                sleepMs(_retryPolicy.delayFor(attempt))
            }
        }
        if lastError == null {
            return Err(new BasicError(ErrorKind.Internal, "otlp retry exhausted"))
        }
        return Err(lastError)
    }

    String pathFor(TelemetryKind kind) {
        if kind == TelemetryKind.Metrics { return "/v1/metrics" }
        if kind == TelemetryKind.Traces { return "/v1/traces" }
        return "/v1/logs"
    }

    String describe() {
        return "otlp " + _name + " endpoint=" + _endpoint
            + " queue=" + str(_queue.length())
            + " sent=" + str(_sentBatches)
            + " dropped=" + str(_droppedBatches)
    }
}
```

> `_requestTimeoutMillis` 在实现中通过 `Context.withCancel` + `Timer.after` 取消请求上下文；
> 伪代码省略该超时包装以突出重试/队列。`otlpEncodeRaw`、`sleepMillis` 是内部支撑，
> 不属于公开类型。
