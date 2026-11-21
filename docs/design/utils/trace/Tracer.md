# `Tracer`

| 项 | 值 |
| --- | --- |
| 类型 | `class Tracer` |
| 包 | `xdk.trace` |
| 稳定性 | `preview` |
| 依赖 | `TraceOptions`、`Sampler`、`Propagator`、`Span`、`SpanContext`、`SpanKind`、`TraceRuntime`、`TraceHandle`、`RuntimeMonitor`、`Error`、`Map` |

---

## 1. 定位

追踪入口：按 `TraceOptions` 创建 span、维护当前任务的活动 span、注入/提取上下文、幂等关闭。

不做：全局单例、后台导出线程、OTLP 编码、自动 instrumentation、指标/日志写入、跨任务自动上下文继承。

---

## 2. 设计逻辑

- `create` 复制 `TraceOptions` 快照，打开独立的 `TraceRuntime`，默认使用运行时 W3C `Propagator`；可显式传入自定义传播器。
- `startSpan(name)` 以当前任务的活动 span 为父；没有活动 span 时创建根。
- `startSpan(name, parent)` 使用显式父上下文；父无效 panic；父未采样则子未采样。
- `startSpan(name, kind)` 指定 kind，父规则同 `startSpan(name)`。
- 根 span 的采样由 `TraceOptions.sampler` 决定；子 span 继承父的 sampled 标志，不重新采样。
- 未采样或 tracer 已关闭时仍返回合法 `Span`，但 `isRecording()` 为 false，写入/结束不导出。
- 当前 span 由 `TraceRuntime` 按任务维护栈；`Span.end()` 移除自己的绑定，栈顶恢复为最近的未结束 span。
- `inject`/`extract` 直接委托 `Propagator`；关闭后仍可用，传播不依赖 tracer 记录状态。
- `close`/`shutdown` 幂等：第一次刷新运行时 sink 并关闭，后续返回同一结果；活动句柄转为非记录。
- 线程安全；无全局可变状态；每个 Tracer 独立。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_options` | `TraceOptions` | 创建时的快照 |
| `_propagator` | `Propagator` | 默认 W3C 或显式注入 |
| `_runtime` | `TraceRuntime` | 每个 Tracer 独立 |
| `_monitor` | `RuntimeMonitor` | 关闭串行化 |
| `_closed` | `Bool` | 关闭标记 |
| `_closeResult` | `Result<Unit, Error>?` | 幂等关闭结果 |

不变量：options/propagator/runtime 非 null；`_closed` 只从 false 变 true；`_closeResult` 在关闭完成后非 null；关闭后 `currentSpan()` 为 null；`startSpan` 仍返回非记录 span。

---

## 4. 生命周期

`create` 构造；调用方持有；`close`/`shutdown` 关闭；不可重新打开；无 close 的 `Span` 独立结束。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Tracer(TraceOptions, Propagator, TraceRuntime)` | 全部 | 私有；非 null | 外部构造 → 编译错误 |
| `Tracer.create(TraceOptions)` | options | 非 null | null → `InvalidArgument`；运行时打开失败 |
| `Tracer.create(TraceOptions, Propagator)` | options/propagator | 非 null | null → `InvalidArgument`；运行时打开失败 |

---

## 6. 字段表

见 §3；字段私有；`_options`/`_propagator`/`_runtime`/`_monitor` 为 `final`。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `create` | 默认传播器创建 | `TraceOptions` | `Result<Tracer, Error>` | null → `InvalidArgument` |
| `create` | 指定传播器创建 | `TraceOptions, Propagator` | `Result<Tracer, Error>` | null → `InvalidArgument` |
| `startSpan` | 当前父/Internal | `String` | `Span` | null/非法名 → panic |
| `startSpan` | 当前父/指定 kind | `String, SpanKind` | `Span` | null/非法名 → panic |
| `startSpan` | 显式父/Internal | `String, SpanContext` | `Span` | null/非法名/无效父 → panic |
| `startSpan` | 显式父/指定 kind | `String, SpanContext, SpanKind` | `Span` | null/非法名/无效父 → panic |
| `currentSpan` | 当前任务活动 span | 无 | `Span?` | 无 |
| `inject` | 注入上下文 | `SpanContext, Map<String,String>` | `Unit` | null → panic；无效上下文 no-op |
| `extract` | 提取上下文 | `Map<String,String>` | `SpanContext?` | null → panic；损坏 → null |
| `propagator` | 当前传播器 | 无 | `Propagator` | 无 |
| `options` | 选项快照 | 无 | `TraceOptions` | 无 |
| `isClosed` | 是否关闭 | 无 | `Bool` | 无 |
| `close` | 刷新并关闭 | 无 | `Result<Unit, Error>` | 运行时关闭错误；幂等 |
| `shutdown` | `close` 别名 | 无 | `Result<Unit, Error>` | 同 `close` |

说明：

- `startSpan` 的 name 为 1..256 字符；显式 parent 必须 `isValid()`。
- 关闭后 `startSpan` 不抛异常，返回 `isRecording()==false` 的 span；`currentSpan()` 返回 null。
- `inject`/`extract` 在关闭后仍工作；传播器由调用方保证线程安全。
- `options()` 返回副本，修改它不影响 tracer。
- `close` 第二次调用返回第一次的结果，不会重复刷新；关闭失败仍置关闭标记并缓存错误，不回滚。
- 不提供 `spanFromContext(Context)`：`Context` 没有值槽，跨任务请显式传 `SpanContext`。

---

## 8. 使用的技术

- 工厂 + 私有构造；
- 快照配置；
- 任务本地 span 栈；
- 确定性采样；
- 幂等关闭；
- 运行时句柄导出；
- 传播与记录分离。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Int、Result、Unit、Map、可空引用；
- 运行时：`TraceRuntime.open(serviceName)/newTraceId/newSpanId/begin/bind/currentSpan/close`、`TraceHandle`、`RuntimeMonitor`；
- 接口：`TraceOptions`、`Sampler`、`Propagator`、`Span`、`SpanContext`、`SpanKind`、`Error`、`BasicError`、`ErrorKind`。

`TraceRuntime`/`TraceHandle` 是内部原语，不是公开类型：

- `TraceRuntime.open(serviceName)` 打开独立运行时并绑定 `service.name`；`newTraceId()` 返回 32 位十六进制；`newSpanId()` 返回 16 位十六进制。
- `begin(name, context, kind, maxAttributes, maxEvents, recording)` 创建记录句柄；关闭后仍返回惰性句柄，ID 生成仍可用。
- `bind(span)` 把 span 压入当前任务栈；`currentSpan()` 返回栈顶；关闭后不再暴露当前 span。
- `close()` 刷新 sink 并把活动句柄转为非记录；关闭失败返回 `Error`。

---

## 10. 依赖的特性/接口/类

`TraceOptions`、`Sampler`、`Propagator`、`Span`、`SpanContext`、`SpanKind`、`TraceRuntime`、`TraceHandle`、`RuntimeMonitor`、`Error`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

引用语义；线程安全；`startSpan`/`currentSpan`/`inject`/`extract` 可并发；当前 span 按任务隔离，跨任务必须显式传父上下文；`close` 由 `RuntimeMonitor` 串行化，第二个调用等待并返回同一结果；多个 Tracer 互不影响；无全局状态。

---

## 12. 示例与反例

正确：

```xnull
TraceOptions options = new TraceOptions()
    .serviceName("orders")
    .sampler(Sampler.ratio(0.1))
Result<Tracer, Error> created = Tracer.create(options)
if created.isErr() { return }
Tracer tracer = created.value()
Span span = tracer.startSpan("GET /orders", SpanKind.Server)
span.setAttribute("http.method", "GET")
Span database = tracer.startSpan("db.query", SpanKind.Client)
database.end()
Map<String, String> headers = [:]
tracer.inject(span.context(), headers)
span.end()
Result<Unit, Error> closed = tracer.close()
```

反例：用全局 tracer；关闭后 `startSpan` 期望仍导出；并发任务依赖隐式当前 span；用无效 parent 创建子 span；把 `inject`/`extract` 当导出器；`close` 后重复刷新 sink。

---

## 13. 测试/场景义务

create 成功/空参数/运行时失败；默认传播器；自定义传播器；根/子/显式父；kind 重载；采样继承；`currentSpan` 嵌套/结束恢复；跨任务显式父；inject/extract 往返；关闭幂等；关闭后 startSpan/currentSpan；并发 startSpan；多 Tracer 隔离；options 快照；无效 parent；关闭期间活动 span。

---

## 14. XNull 伪代码

```xnull
class Tracer {
    final TraceOptions _options
    final Propagator _propagator
    final TraceRuntime _runtime
    final RuntimeMonitor _monitor
    Bool _closed = false
    Result<Unit, Error>? _closeResult = null

    private Tracer(TraceOptions options, Propagator propagator, TraceRuntime runtime) {
        _options = options
        _propagator = propagator
        _runtime = runtime
        _monitor = new RuntimeMonitor()
    }

    static Result<Tracer, Error> create(TraceOptions options) {
        if options == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "trace option is null"))
        }
        return Tracer.create(options, TraceRuntime.defaultPropagator())
    }

    static Result<Tracer, Error> create(TraceOptions options, Propagator propagator) {
        if options == null || propagator == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "trace option is null"))
        }
        TraceOptions snapshot = options.copy()
        Result<TraceRuntime, Error> opened = TraceRuntime.open(snapshot.getServiceName())
        if opened.isErr() { return Err(opened.error()) }
        return Ok(new Tracer(snapshot, propagator, opened.value()))
    }

    Span startSpan(String name) {
        return self.startSpan(name, SpanKind.Internal)
    }

    Span startSpan(String name, SpanKind kind) {
        if name == null || kind == null {
            throw "Tracer.startSpan: null argument"
        }
        if name.length() == 0 || name.length() > 256 {
            throw "Tracer.startSpan: invalid name"
        }
        Span? parent = self.currentSpan()
        SpanContext? parentContext = null
        if parent != null {
            Span current = parent as Span
            parentContext = current.context()
        }
        return self.createSpan(name, parentContext, kind)
    }

    Span startSpan(String name, SpanContext parent) {
        return self.startSpan(name, parent, SpanKind.Internal)
    }

    Span startSpan(String name, SpanContext parent, SpanKind kind) {
        if name == null || parent == null || kind == null {
            throw "Tracer.startSpan: null argument"
        }
        if name.length() == 0 || name.length() > 256 {
            throw "Tracer.startSpan: invalid name"
        }
        if !parent.isValid() {
            throw "Tracer.startSpan: invalid parent"
        }
        return self.createSpan(name, parent, kind)
    }

    private Span createSpan(String name, SpanContext? parent, SpanKind kind) {
        Bool closed = self.isClosed()
        String spanId = _runtime.newSpanId()
        String traceId = ""
        String? parentSpanId = null
        Bool sampled = false
        Map<String, String> baggage = [:]
        if parent != null {
            SpanContext resolved = parent as SpanContext
            traceId = resolved.traceId()
            parentSpanId = resolved.spanId()
            sampled = resolved.sampled() && !closed
            baggage = resolved.baggage()
        } else {
            traceId = _runtime.newTraceId()
            SpanContext candidate = new SpanContext(traceId, spanId, null, false, [:])
            sampled = !closed && _options.getSampler().shouldSample(candidate)
        }
        SpanContext context = new SpanContext(traceId, spanId, parentSpanId, sampled, baggage)
        Bool recording = sampled && !closed
        TraceHandle handle = _runtime.begin(name, context, kind, _options.getMaxAttributes(),
                                            _options.getMaxEvents(), recording)
        Span span = new Span(name, context, kind, handle)
        _runtime.bind(span)
        return span
    }

    Span? currentSpan() {
        if self.isClosed() { return null }
        return _runtime.currentSpan()
    }

    Unit inject(SpanContext context, Map<String, String> carrier) {
        _propagator.inject(context, carrier)
        return unit
    }

    SpanContext? extract(Map<String, String> carrier) {
        return _propagator.extract(carrier)
    }

    Propagator propagator() { return _propagator }
    TraceOptions options() { return _options.copy() }

    Bool isClosed() {
        _monitor.enter()
        Bool result = _closed
        _monitor.exit()
        return result
    }

    Result<Unit, Error> close() {
        _monitor.enter()
        if _closed {
            Result<Unit, Error> prior = _closeResult as Result<Unit, Error>
            _monitor.exit()
            return prior
        }
        _closed = true
        Result<Unit, Error> result = _runtime.close()
        _closeResult = result
        _monitor.exit()
        return result
    }

    Result<Unit, Error> shutdown() {
        return self.close()
    }
}
```
