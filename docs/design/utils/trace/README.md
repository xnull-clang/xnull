# `xdk.trace` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.trace` |
| 层 | L7 应用服务（文档分组 `utils/`） |
| 依赖 | `xdk.errors`、`xdk.time`、`xdk.runtime`、`xdk.math`、`xdk.text`、`xdk.collections` |
| 被依赖 | 应用、客户端、服务端、协议中间件 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |
| 实现状态 | M14.1：`SpanKind`/`SpanStatus`/`SpanContext`/`SpanEvent`/`TraceOptions`/`Sampler`/`Propagator`/`W3cPropagator`/`Span`/`Tracer`/`TraceRuntime` implemented；`@Traced` planned |

---

## 1. 包定位

`xdk.trace` 提供进程内分布式追踪的**最小公共面**：

- span 树：`Tracer` 创建 `Span`，`Span` 形成父子关系；
- 采样：`Sampler` 在根 span 创建时决定是否记录；
- 传播：`Propagator` 在请求头/消息头中注入或提取 `SpanContext`；
- 有界记录：属性、事件、baggage 都有上限，避免把内存写爆；
- 关闭：`Tracer` 幂等 `close`/`shutdown`，活动 span 变为非记录状态。

明确不做：

- 不是日志别名：span 不是 `LogRecord`，不写 `Logger`/`Sink`；
- 不依赖 metrics：trace 不注册 Counter/Histogram，也不导出指标；
- 不做 OTLP/Jaeger/Zipkin exporter、collector、查询 UI；
- 不做 tracestate、span links、tail sampling、exemplars（X）；
- 不做全局 tracer、全局采样器、自动字节码/反射注入；
- 不替代 `log` 的上下文字段，也不替代 `metrics` 的聚合。
- 不把 `Context` 当作值容器；`Context` 没有值槽，跨任务传递父 span 必须显式传 `SpanContext`。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 显式对象 | `Tracer` 由调用方创建并持有；没有全局单例 |
| 不可变快照 | `SpanContext`、`SpanEvent` 构造时复制输入，读取时返回副本 |
| 有界记录 | `TraceOptions.maxAttributes`/`maxEvents` 限制每个 span；超限丢弃并计数 |
| 采样确定性 | `Sampler.ratio` 按 traceId 稳定哈希，同一 trace 在各进程得到一致决策 |
| 传播与记录分离 | `Propagator` 只处理载体，不负责导出；`Tracer` 负责 span 生命周期 |
| 无 close 的 Span | `Span.end()` 幂等；只有 `Tracer` 有 `close`/`shutdown` |
| 关闭安全 | 关闭后 `startSpan` 返回非记录 span，避免停机路径因追踪崩溃 |
| 线程安全 | `Tracer`、`Span`、`Sampler` 可并发；当前 span 按任务绑定 |
| 无 metrics/log | 结束的 span 交给运行时 trace sink；不写日志、不记指标 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `SpanKind` | enum | Internal/Server/Client/Producer/Consumer | [`SpanKind.md`](SpanKind.md) |
| `SpanStatus` | enum | Unset/Ok/Error | [`SpanStatus.md`](SpanStatus.md) |
| `SpanContext` | class | traceId/spanId/parent/sampled/baggage | [`SpanContext.md`](SpanContext.md) |
| `SpanEvent` | class | 不可变事件快照 | [`SpanEvent.md`](SpanEvent.md) |
| `TraceOptions` | class | 服务名/采样器/属性与事件上限 | [`TraceOptions.md`](TraceOptions.md) |
| `Sampler` | class | alwaysOn/alwaysOff/ratio | [`Sampler.md`](Sampler.md) |
| `Propagator` | protocol | 注入/提取 trace 上下文 | [`Propagator.md`](Propagator.md) |
| `Span` | class | 属性/事件/状态/结束 | [`Span.md`](Span.md) |
| `Tracer` | class | 创建 span/当前 span/传播/关闭 | [`Tracer.md`](Tracer.md) |

X：tracestate、span links、tail sampling、exemplars、OTLP exporter、自动 instrumentation、跨任务自动上下文继承。

实现偏差（M14.1）：

- 不新增 C 运行时；包内私有 `TraceRuntime` 承担 ID 生成与关闭状态，`Span` 自身承担属性/事件/状态缓冲，不另设 `TraceHandle`。
- 当前 span 由每个 `Tracer` 的锁保护栈维护，是 tracer 级而非任务级；跨任务必须显式传 `SpanContext`。
- `W3cPropagator` 是 `Propagator` 默认实现；`fields()` 返回 `traceparent`/`tracestate`，但本批不解析或注入 `tracestate`；baggage 不传播。
- `Sampler.ratio` 使用 32 位掩码 FNV-1a 变体（当前 `String` 没有字符码 API；`charAt` 返回子串），同一 traceId 的采样决策仍稳定，跨进程一致。
- `SpanKind`/`SpanStatus` 内部增加 `Unknown` 0 号占位，避免枚举 0/null 哨兵；业务不使用。
- 文档中的 `Tracer.startSpan`/`create` 重载改为不同名称：`startSpanKind`/`startSpanFrom`/`startSpanFromKind`、`createWithPropagator`。

---

## 4. 顶层函数

无。ID 生成、当前 span 绑定、导出由运行时原语 `TraceRuntime`/`TraceHandle` 提供，不作为公开顶层函数。

---

## 5. 技术/支撑/依赖

- 技术：span 树、W3C trace context、确定性哈希采样、有界缓冲、任务本地当前 span、幂等关闭。
- 支撑：`TraceRuntime`、`TraceHandle`、`nowMono`、`Duration`、`RuntimeMonitor`、`truncate`、`isNaN`、`errorKindName`。
- `TraceRuntime`/`TraceHandle` 是内部原语，不属于本包 9 个公开类型。
- 依赖：`xdk.errors`、`xdk.time`、`xdk.runtime`、`xdk.math`、`xdk.text`、`xdk.collections`。
- 明确不依赖：`xdk.metrics`、`xdk.log`、`xdk.net.*`。

---

## 6. 场景

### S2：服务端请求

```text
Tracer.create(options)
  → startSpan("GET /orders", SpanKind.Server)
  → startSpan("db.query")
  → setAttribute("db.system", "sql")
  → end 子 span → end 父 span
```

### S3：客户端到服务端传播

```text
客户端：tracer.inject(span.context(), headers)
服务端：SpanContext? remote = tracer.extract(headers)
        tracer.startSpan("handler", remote)
```

缺失或损坏的 `traceparent` 返回 null，服务端从新根开始；不因传播失败拒绝业务请求。

### S4：比例采样

`new TraceOptions().sampler(Sampler.ratio(0.1))`；同一 traceId 在客户端、服务端得到相同采样决策。

### S5：错误记录

`span.recordError(error)` 将状态置为 `SpanStatus.Error`，并追加 `exception` 事件；事件受 `maxEvents` 限制。

### S5：关闭

`tracer.close()` 幂等；第二次返回同一结果。关闭后 `startSpan` 返回非记录 span，`currentSpan()` 返回 null。

### S6：并发任务

`currentSpan()` 只反映当前任务的绑定；跨任务/线程池必须显式传 `SpanContext` 父上下文，不依赖隐式全局。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| OTLP/Jaeger/Zipkin exporter | 不在本包；由运行时 sink 或 X 集成层实现 |
| trace 与 metrics 关联 | 不做；trace 不依赖 metrics，也不生成 exemplar |
| trace 与 log 关联 | 应用可在日志字段中写 traceId；trace 不依赖 log，不把 span 当日志 |
| tracestate | X；当前 `SpanContext` 不携带 tracestate |
| span links | X；当前只有父子关系 |
| tail sampling | 不做；`Sampler` 只看 traceId，不看属性/结果 |
| baggage 修改 | 不在 `Span` 上暴露 setter；子 span 继承父 baggage 快照 |
| `spanFromContext(Context)` | 不提供；`Context` 没有值槽，改用 `currentSpan()` 或显式父 `SpanContext` |
| 全局 tracer | 禁止；每个应用/组件显式创建并关闭 |
| 关闭时活动 span | `close` 不自动 `end`；运行时句柄转为非记录，之后 `end` 不再导出 |
| 跨任务当前 span | 按任务绑定；跨任务显式传父上下文，X 再做自动继承 |
| 采样器扩展 | 自定义采样需要新类型时走 X；当前只提供三种内置模式 |
| 资源自动 instrumentation | X；本包不依赖反射/字节码 |

---

## 8. 依赖与顺序

```text
xdk.errors / xdk.time / xdk.runtime / xdk.math / xdk.text / xdk.collections
  └─ xdk.trace
       ├─ 应用
       ├─ 协议中间件（HTTP/DB/消息）
       └─ 服务端
```

`xdk.trace` 不进入 `xdk.metrics` 的依赖链，也不被 `xdk.metrics` 依赖；两者只共享 `core` 层的时间与错误类型。

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | `@Traced` |
| 本包消费 | `@Value`、`@Builder` |
| 处理器 | TraceAnnotationProcessor（Validate/Generate） |
| 生成物 | span/包装器元数据 |
| 状态 | 领域注解 `@Traced` planned；M14.1 运行时包 implemented；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 服务方法 | `@Traced` | span 包装 |
| `SpanContext`/`SpanEvent`/`TraceOptions` | `@Value`/`@Builder` | 值语义/选项 |

### 声明

```x
@Target(Method)
@Retention(Source)
@annotation Traced {
    final String name
}
```

声明文件：每个注解单独一个 PascalCase 文件；处理器为构建期类型；生成代码在 `<package>/generated/`。

### 使用

```x
class UserService {
    @Traced("user.find")
    User find(Long id) {
        // ...
    }
}
```

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
