# `Span`

| 项 | 值 |
| --- | --- |
| 类型 | `class Span` |
| 包 | `xdk.trace` |
| 稳定性 | `preview` |
| 依赖 | `SpanContext`、`SpanKind`、`SpanStatus`、`SpanEvent`、`TraceHandle`、`Duration`、`Error`、`nowMono`、`Map`、`List` |

---

## 1. 定位

一次操作的记录单元：名称、上下文、属性、事件、状态、时长。

不做：导出协议、采样决策、传播编码、日志输出、指标聚合、资源 close。

---

## 2. 设计逻辑

- 由 `Tracer.startSpan` 创建；持有不可变 `SpanContext`、`SpanKind` 和运行时 `TraceHandle`。
- `TraceHandle` 负责属性/事件的有界缓冲、状态优先级、当前 span 绑定和结束时导出。
- `setAttribute`：已存在键替换值；新键超过 `TraceOptions.maxAttributes` 时丢弃并计数；键为空 panic，值 null panic。
- `addEvent`：事件名非空；超过 `TraceOptions.maxEvents` 时丢弃并计数；属性 Map 复制。
- `setStatus`：`Unset` 忽略；`Ok` 可被 `Error` 升级；`Error` 终态；描述截断到 1024 字符。
- `recordError`：状态置 `Error`，追加 `exception` 事件；事件受上限约束；不抛出业务错误。
- `end` 幂等：设置结束时间、解除当前绑定、把记录交给运行时 sink；之后所有写入 no-op。
- `isRecording`：未采样、已结束或 tracer 已关闭时为 false。
- `duration`：结束前为 0，结束后冻结为结束时刻减开始时刻。
- 无 `close`；end 不是资源关闭，不释放外部资源。
- 线程安全；属性/事件/状态由 `TraceHandle` 串行化；`end` 与其他写入竞争时以先到者为准。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 非空 span 名 |
| `_context` | `SpanContext` | 不可变上下文 |
| `_kind` | `SpanKind` | span 角色 |
| `_handle` | `TraceHandle` | 运行时记录/绑定句柄 |

不变量：name 非空；context 有效；kind 非 null；handle 非 null；end 最多发生一次；属性/事件数量不超过 options 上限；结束后状态/属性/事件不再变化。

---

## 4. 生命周期

`Tracer.startSpan` 创建；调用方持有；`end` 后进入终态；无 close；GC 管理。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Span(String name, SpanContext context, SpanKind kind, TraceHandle handle)` | 全部 | name 1..256；context 有效；kind/handle 非 null | 非法 → panic |

构造器主要供 `Tracer`/运行时使用；业务代码不应直接构造。

---

## 6. 字段表

见 §3；字段私有且 `final`。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | span 名 | 无 | `String` | 无 |
| `context` | 上下文 | 无 | `SpanContext` | 无 |
| `kind` | span 类型 | 无 | `SpanKind` | 无 |
| `setAttribute` | 写属性 | `String key, String value` | `void` | null/空键 → panic；超限丢弃 |
| `addEvent` | 追加事件 | `String name, Map<String,String> attributes` | `void` | null/空名 → panic；超限丢弃 |
| `setStatus` | 设置状态 | `SpanStatus status, String description` | `void` | null → panic |
| `recordError` | 记录错误 | `Error error` | `void` | null → panic |
| `end` | 结束 span | 无 | `void` | 无；幂等 |
| `isRecording` | 是否记录 | 无 | `Bool` | 无 |
| `duration` | 时长 | 无 | `Duration` | 无 |
| `status` | 当前状态 | 无 | `SpanStatus` | 无 |
| `statusDescription` | 状态描述 | 无 | `String` | 无 |
| `attributes` | 属性快照 | 无 | `Map<String,String>` | 无 |
| `events` | 事件快照 | 无 | `List<SpanEvent>` | 无 |
| `droppedAttributes` | 丢弃属性数 | 无 | `Int` | 无 |
| `droppedEvents` | 丢弃事件数 | 无 | `Int` | 无 |

说明：

- `setAttribute` 的键长度 >256 或值长度 >1024 时丢弃并增加丢弃计数，不抛异常。
- `addEvent` 的事件名 1..256；属性条目超过 `maxAttributes` 时只保留前若干项；事件总数超过 `maxEvents` 时丢弃。
- `setStatus(SpanStatus.Error, description)` 的描述会截断到 1024；`Ok`/`Unset` 不改变已设置的 `Error`。
- `recordError` 使用 `error.kind()` 的稳定名和 `error.describe()`；描述截断。
- `end` 之后 `setAttribute`/`addEvent`/`setStatus`/`recordError` 的写入被忽略；参数校验仍先执行（null、空键等仍 panic）。`context`/`name`/`kind`/`duration` 仍可读。
- `duration` 使用 `nowMono`，不受墙钟回拨影响。

---

## 8. 使用的技术

- 有界缓冲；
- 状态优先级；
- 单调时钟；
- 幂等结束；
- 任务本地当前 span 绑定；
- 运行时句柄导出。

---

## 9. 需要的支撑

- 语言：class、String、Int、Bool、Map、List、`Duration`、`Error`；
- 运行时：`TraceHandle`、`nowMono`、`durationOfMillis`、`errorKindName`、`truncate`；`TraceHandle` 负责超长 key/value 和超出数量上限的属性/事件丢弃并计数；
- 接口：`SpanContext`、`SpanKind`、`SpanStatus`、`SpanEvent`。

---

## 10. 依赖的特性/接口/类

`SpanContext`、`SpanKind`、`SpanStatus`、`SpanEvent`、`TraceHandle`、`Duration`、`Error`、`errorKindName`、`nowMono`、`truncate`。

---

## 11. 所有权与并发

引用语义；线程安全；可由多个任务读取；写入/结束由 `TraceHandle` 串行化；当前绑定是任务本地；`end` 可从任意任务调用，但只生效一次；无外部资源。

---

## 12. 示例与反例

正确：

```text
Span span = tracer.startSpan("GET /orders", SpanKind.Server)
span.setAttribute("http.method", "GET")
span.addEvent("cache.miss", [:])
span.setStatus(SpanStatus.Ok, "")
span.end()
Duration elapsed = span.duration()
```

反例：end 后继续写属性并期望导出；用 `Span` 当 `Logger`；在属性里放大对象/二进制；依赖 `end` 返回错误；把未采样 span 当已导出；在多个任务共享同一个当前 span 而不显式传父上下文。

---

## 13. 测试/场景义务

属性新增/替换/超限/空键；事件追加/超限/空名；状态迁移；`recordError`；`end` 幂等；end 后 no-op；`duration` 前后；未采样/关闭后 `isRecording`；并发写入；`droppedAttributes`/`droppedEvents`；上下文快照不可变。

---

## 14. XNull 伪代码

```xnull
class Span {
    final String _name
    final SpanContext _context
    final SpanKind _kind
    final TraceHandle _handle

    Span(String name, SpanContext context, SpanKind kind, TraceHandle handle) {
        if name == null || context == null || kind == null || handle == null {
            throw "Span: null argument"
        }
        if name.length() == 0 || name.length() > 256 {
            throw "Span: invalid name"
        }
        if !context.isValid() {
            throw "Span: invalid context"
        }
        _name = name
        _context = context
        _kind = kind
        _handle = handle
    }

    String name() { return _name }
    SpanContext context() { return _context }
    SpanKind kind() { return _kind }

    void setAttribute(String key, String value) {
        if key == null || value == null {
            throw "Span.setAttribute: null argument"
        }
        if key.length() == 0 {
            throw "Span.setAttribute: empty key"
        }
        _handle.setAttribute(key, value)
    }

    void addEvent(String name, Map<String, String> attributes) {
        if name == null || attributes == null {
            throw "Span.addEvent: null argument"
        }
        if name.length() == 0 || name.length() > 256 {
            throw "Span.addEvent: invalid name"
        }
        _handle.addEvent(new SpanEvent(name, nowMono(), attributes))
    }

    void setStatus(SpanStatus status, String description) {
        if status == null || description == null {
            throw "Span.setStatus: null argument"
        }
        _handle.setStatus(status, description)
    }

    void recordError(Error error) {
        if error == null { throw "Span.recordError: null error" }
        if !_handle.isRecording() { return }
        String description = truncate(error.describe(), 1024)
        Map<String, String> attributes = [:]
        attributes.put("exception.type", errorKindName(error.kind()))
        attributes.put("exception.message", description)
        _handle.setStatus(SpanStatus.Error, description)
        _handle.addEvent(new SpanEvent("exception", nowMono(), attributes))
    }

    void end() {
        _handle.end()
    }

    Bool isRecording() { return _handle.isRecording() }
    Duration duration() { return _handle.duration() }

    SpanStatus status() { return _handle.status() }
    String statusDescription() { return _handle.statusDescription() }
    Map<String, String> attributes() { return _handle.attributes() }
    List<SpanEvent> events() { return _handle.events() }
    Int droppedAttributes() { return _handle.droppedAttributes() }
    Int droppedEvents() { return _handle.droppedEvents() }
}
```
