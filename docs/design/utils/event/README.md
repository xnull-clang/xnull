# `xdk.event` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.event` |
| 层 | L7 应用服务（文档分组 `utils/`） |
| 依赖 | `xdk.errors`、`xdk.runtime`、`xdk.codec` |
| 被依赖 | 应用、客户端、服务端、插件/组件 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 0.5 实现状态（M21.3）

已实现 `Event`、`EventBus`、`EventSubscription`（3/3）。

- `publish` 同步、按订阅顺序、锁外回调、首错短路；handler 内可 unsubscribe/subscribe/close；
- 订阅/取消/关闭用 `RuntimeMonitor` 保护登记表；订阅 id 单调递增；
- handler 为函数值；编译器不能对函数值判 null，`subscribe` 仅校验 topic；
- 不做异步队列、持久化、通配符、跨进程；无全局总线。

## 1. 包定位

`xdk.event` 提供**进程内、同步、显式持有**的发布/订阅：

- `Event`：不可变事件信封（id、topic、payload、单调时间戳、来源）；
- `EventSubscription`：订阅句柄（id/topic、取消、活动状态）；
- `EventBus`：按 topic 注册 handler，同步 `publish`，返回投递数。

明确不做：

- 不是日志别名：不依赖 `xdk.log`，不定义 `Logger`/`Sink`/`Level`/`Formatter`，不把事件格式化或转发为日志；
- 不做异步投递：没有队列、worker、线程、Timer、Executor；`publish` 在当前任务同步调用 handler；
- 不做全局总线：每个 `EventBus` 由调用方显式创建、注入、关闭；没有全局单例或服务定位器；
- 不做通配符 topic、优先级、过滤 DSL、事件存储、重放、持久化、分布式总线；
- 不做反射式 handler 注册、注解扫描、typed event 泛型；
- 不做 handler 级超时/取消；`publish` 没有 `Context` 参数，长 handler 会阻塞发布者。

> 事件是应用数据，日志是诊断输出。两者可以由应用组合，但依赖方向不能是 event → log；本包只返回错误，不写日志。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 显式实例 | `EventBus` 由调用方 `new EventBus()` 创建并持有；无全局注册表 |
| 不可变信封 | `Event` 字段全部 final；构造后不可修改；payload 引用按只读约定共享 |
| 同步投递 | `publish` 在返回前完成当前快照内的 handler 调用；无后台投递 |
| 首错停止 | 第一个返回 `Err` 的 handler 终止本次投递，错误原样返回 |
| 取消即时 | `cancel`/`unsubscribe` 从总线登记中移除；后续投递不再选中 |
| 无锁回调 | `RuntimeMonitor` 只保护登记表与关闭标志；handler 在锁外调用 |
| 线程安全 | 总线可在任务间共享；并发 `publish` 允许，但同一 handler 可能并发执行 |
| 精确 topic | topic 按字符串相等匹配；不解释层级、不做通配、大小写敏感 |
| 显式关闭 | `close` 幂等；关闭后订阅全部失效，`publish`/`subscribe` 返回 `Unavailable` |
| 无日志依赖 | 不引用 `xdk.log`；handler 错误由调用方处理，不自动记录 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `Event` | class | 不可变事件信封/描述 | [`Event.md`](Event.md) |
| `EventSubscription` | class | 订阅句柄/取消/活动状态 | [`EventSubscription.md`](EventSubscription.md) |
| `EventBus` | class | 订阅/同步发布/退订/关闭 | [`EventBus.md`](EventBus.md) |

共 3/3 个类型文件；README 索引与文件一一对应。

X：异步投递/队列、通配符与层级 topic、优先级/过滤、事件存储与重放、分布式总线、订阅数量上限、handler 超时、弱引用订阅、typed payload 泛型。

---

## 4. 顶层函数

无。订阅、发布、取消、关闭全部通过 `EventBus`/`EventSubscription` 方法表达，不提供全局 `publish`/`subscribe` 快捷函数。

---

## 5. 技术/支撑/依赖

- 技术：不可变信封、精确 topic 索引、监视器保护登记表、同步快照投递、首错短路、幂等取消/关闭。
- 支撑：`RuntimeMonitor.enter/exit`、`nowMono`、`JsonValue`、`BasicError`、`ErrorKind`、`trim`、`str`。
- 依赖：`xdk.errors`、`xdk.runtime`、`xdk.codec`。
- 明确不依赖：`xdk.log`、`xdk.execution`、`xdk.net`、`xdk.metrics`。
- 线程模型：投递发生在调用 `publish` 的任务；本包不创建线程、任务或定时器。

---

## 6. 场景

### E1：同 topic 多订阅

```text
EventBus bus = new EventBus()
bus.subscribe("orders.created", handlerA)
bus.subscribe("orders.created", handlerB)
bus.publish(Event.now("evt-1", "orders.created", payload, "checkout"))
  → 两个 handler 依次执行 → Ok(2)
```

### E2：handler 失败

```text
handlerA 返回 Err(validationError)
publish
  → handlerB 不再执行
  → Err(validationError)
```

投递数只在成功时返回；失败前已经执行的 handler 副作用不回滚。

### E3：取消与退订

```text
EventSubscription subscription = bus.subscribe("orders.created", handler).value()
subscription.cancel()   → true
subscription.cancel()   → false
subscription.isActive() → false
bus.unsubscribe(subscription) → false
```

### E4：关闭

```text
bus.close()
bus.isClosed()               → true
bus.publish(event)           → Err(Unavailable)
bus.subscribe("x", handler)  → Err(Unavailable)
subscription.isActive()      → false
```

### E5：并发发布

两个任务同时 `publish` 同一 topic；每个任务同步调用自己快照中的 handler。同一 handler 可能并发执行，handler 必须线程安全或由应用层串行化。跨 `publish` 不承诺顺序。

### E6：不是日志

handler 返回错误时，总线不打印、不落盘、不创建日志记录；调用方决定记录、重试或向上返回。需要日志时，在 handler 或发布方显式调用 `xdk.log`，本包不提供日志能力。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 异步投递/队列 | 不做；`publish` 同步；X 再设计队列/worker |
| 全局总线 | 禁止；每个应用/组件显式创建自己的 `EventBus` |
| 日志别名 | 禁止；不依赖 `xdk.log`，不提供 logger/sink/formatter |
| topic 通配符/层级 | 不做；精确、大小写敏感匹配 |
| 优先级/过滤 | 不做；按订阅顺序调用 |
| handler 超时/取消 | 不做；无 `Context` 参数；长任务应在 handler 内移交应用自己的执行器 |
| 事件存储/重放 | 不做；事件只投递给当前活动订阅 |
| 分布式/持久化 | 不做 |
| typed event/泛型载荷 | 不做；统一 `JsonValue`，由 handler 解释 |
| 反射注册/注解扫描 | 不做 |
| 订阅数量上限 | 当前无上限；需要上限时由 X 的 options 提供 |
| handler 错误聚合 | 不做；首错停止并原样返回 |
| 部分投递计数 | `Err` 不携带已投递数；调用方不能从返回值得知部分成功数 |
| 同一 handler 并发 | 允许；并发 `publish` 可能重入同一 handler |
| handler 内嵌套发布 | 同步嵌套；不检测订阅环，应用必须避免无界递归 |
| 重复订阅 | 允许；每个 `subscribe` 是独立订阅，按次投递 |
| 事件去重 | 不做；同一 `Event` 可重复发布并重复投递 |
| payload 深拷贝 | 不做；引用共享，生产者/消费者按只读约定使用 |
| 订阅 ID 唯一性 | 仅在单个 `EventBus` 内唯一；跨总线不保证 |
| 关闭排空 | `close` 不等待在途 handler；没有后台任务可排空 |
| 弱引用订阅 | 不做；必须显式 `cancel`/`unsubscribe`/`close` |

---

## 8. 依赖与顺序

```text
xdk.errors / xdk.runtime / xdk.codec
  └─ xdk.event
       ├─ 应用
       ├─ 客户端
       ├─ 服务端
       └─ 插件/组件
```

规则：

- `xdk.event` 只依赖错误、运行时监视器/单调时钟、JSON 值树；不进入 `xdk.log` 的依赖链。
- 应用可以在 handler 或发布方调用 `xdk.log`；`xdk.event` 不反向依赖 `xdk.log`。
- `xdk.event` 不依赖 `xdk.graph`/`xdk.reflect`/`xdk.metrics`；这些包也不能把事件总线当作日志或指标通道。
- 不创建全局总线；跨组件传递时必须显式传入 `EventBus` 或 `EventSubscription`。

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | 无领域注解 |
| 本包消费 | `@Value`、`@Override` |
| 处理器 | 标准 A8 / 编译器内建 |
| 生成物 | 事件值语义、订阅/总线签名 |
| 状态 | 无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Event` | `@Value` | 值语义成员 |
| `EventSubscription`/`EventBus` | `@Override` | 订阅/关闭签名；不套 builder |

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
