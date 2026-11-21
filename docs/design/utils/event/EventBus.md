# `EventBus`

| 项 | 值 |
| --- | --- |
| 类型 | `class EventBus` |
| 包 | `xdk.event` |
| 稳定性 | `preview` |
| 依赖 | `Event`、`EventSubscription`、`RuntimeMonitor`、`Error` |

---

## 1. 定位

进程内同步事件总线：按精确 topic 注册 handler，`publish` 在当前任务依次调用 handler，返回成功投递数；支持退订、取消、幂等关闭。

不做：异步投递、队列、后台线程、定时器、全局单例、通配符、优先级、事件存储/重放、分布式总线、日志格式化、handler 超时或自动重试。

---

## 2. 设计逻辑

- 状态：监视器、订阅表（id → 句柄）、topic 索引（topic → id 列表）、handler 表（id → 函数值）、订阅 id 计数器、关闭标志。
- `subscribe` 校验 topic 与 handler；空白 topic 返回 `InvalidArgument`，关闭后返回 `Unavailable`；成功时生成 `sub-N`，同时登记句柄与 handler。
- `publish` 在监视器内检查关闭并复制当前 topic 的订阅 id 快照；释放监视器后逐个解析句柄/handler，检查活动状态并同步调用。
- handler 返回 `Ok(unit)` 计一次投递；返回 `Err` 立即停止，错误原样返回；没有订阅时返回 `Ok(0)`。
- 不在持有监视器时调用 handler：handler 可以 `subscribe`/`unsubscribe`/`publish`/`close`，不会因监视器不可重入而死锁。
- `unsubscribe` 按“同一实例”移除；已取消、已关闭、外来句柄返回 false；`EventSubscription.cancel` 委托到这里。
- `close` 幂等：置关闭标志并清空三张表；所有句柄的 `isActive` 立即为 false；不调用 handler，不等待在途 handler，不支持重新打开。
- `isSubscribed` 是给 `EventSubscription.isActive` 的支撑查询；应用通常不直接调用。
- topic 精确、大小写敏感、无通配/层级语义；订阅顺序即同一 topic 的投递顺序。
- 线程安全；并发 `publish` 允许，但同一 handler 可能被并发调用；跨 `publish` 无顺序保证。
- 无全局总线；每个实例独立，关闭一个不影响另一个；不依赖 `xdk.log`，handler 错误不自动记录。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_monitor` | `RuntimeMonitor` | 保护登记表、计数器、关闭标志 |
| `_subscriptions` | `Map<String,EventSubscription>` | id → 句柄 |
| `_topics` | `Map<String,List<String>>` | topic → 订阅 id 列表 |
| `_handlers` | `Map<String,Result<Unit, Error>(Event)>` | id → handler |
| `_nextSubscriptionId` | `Long` | 下一个订阅 id，起始 1 |
| `_closed` | `Bool` | 是否关闭 |

不变量：`_subscriptions` 与 `_handlers` 的键集合一致；`_topics` 中每个 id 都存在于 `_subscriptions`；topic 列表非空（空列表在退订时删除）；id 单调递增且不复用；`_nextSubscriptionId >= 1`；关闭后三张表为空且 `_closed` 为 true；handler 非 null；topic 与 `Event.topic` 都按原样保存并精确匹配。

---

## 4. 生命周期

`new EventBus()` 创建空总线；长期使用；`close` 结束，幂等且不可重开。关闭后 `subscribe`/`publish` 返回 `Unavailable`，`unsubscribe`/`isSubscribed` 返回 false。没有后台线程、定时器或待排空队列；关闭立即返回。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `EventBus()` | 无 | 无 | 无 |

说明：

- 构造器初始化监视器与三张空表；不读取全局配置、不注册全局单例、不启动任务。
- 不提供 options；订阅数量上限、异步队列、handler 超时属于 X，不在当前构造器预留可变默认值。
- 多个 `EventBus` 实例彼此隔离；订阅 id 只在各自实例内有意义。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `subscribe` | 注册 handler | `String topic, Result<Unit, Error>(Event) handler` | `Result<EventSubscription, Error>` | `InvalidArgument`/`Unavailable`；null → panic |
| `publish` | 同步投递 | `Event event` | `Result<Int, Error>` | `Unavailable`/handler 错误；null → panic |
| `unsubscribe` | 移除订阅 | `EventSubscription subscription` | `Bool` | null → panic |
| `isSubscribed` | 是否登记该实例 | `EventSubscription subscription` | `Bool` | null → panic |
| `isClosed` | 是否关闭 | 无 | `Bool` | 无 |
| `close` | 关闭并清空 | 无 | `void` | 无；幂等 |

说明：

- `subscribe` 的失败顺序：null 参数 panic；空白 topic 返回 `InvalidArgument`；已关闭返回 `Unavailable`。
- `subscribe` 每次调用创建独立订阅；同一 handler 订阅同一 topic 两次会收到两次投递。
- `publish` 无订阅者返回 `Ok(0)`；关闭后即使无订阅者也返回 `Unavailable`。
- `publish` 在单个 topic 快照内按订阅顺序调用；第一个 `Err` 停止，后续 handler 不执行，错误不包装、不记录。
- `publish` 成功返回实际调用并返回 `Ok(unit)` 的次数；返回 `Err` 时不报告已投递数，已发生的副作用不回滚。
- handler 只能通过 `Err` 报告可恢复失败；抛出致命异常时总线不捕获、不转换为 `Error`，异常按语言语义传播；此时监视器未被持有，总线状态不变。
- `publish` 进行中若被 `close`（包括 handler 内关闭），本次调用仍可结束并返回已投递数；尚未执行的 handler 不再执行。
- handler 内再次 `publish` 是同步嵌套；总线不检测订阅环，应用必须避免无界递归。
- handler 是同步函数值；总线不传 `Context`，不超时、不取消、不重试。长任务应交给应用自己的执行器。
- `unsubscribe` 只接受本总线登记过的同一实例；已取消/已关闭/外来句柄返回 false，重复调用不抛错。
- `isSubscribed` 只用于句柄状态查询；关闭、取消、外来实例均返回 false。
- `close` 不调用 handler、不等待 handler；在途 handler 可以完成，但后续订阅不再投递。
- 私有 `subscriptionFor`/`handlerFor` 只做短临界区查询；`publish` 用它们在快照后重新确认状态，避免把已移除的订阅投递给 handler。

---

## 8. 使用的技术

- 监视器保护的登记表；
- topic 索引；
- 订阅 id 生成；
- 同步快照投递；
- 锁外回调；
- 首错短路；
- 身份校验与幂等关闭。

---

## 9. 需要的支撑

- 语言：class、Map、List、String、Long、Int、Bool、Result、Unit、函数类型、可空类型；
- 运行时：`RuntimeMonitor.enter`/`RuntimeMonitor.exit`；
- 接口：`Event`、`EventSubscription`、`Error`、`BasicError`、`ErrorKind`、`trim`、`str`。

---

## 10. 依赖的特性/接口/类

`Event`、`EventSubscription`、`RuntimeMonitor`、`Error`、`BasicError`、`ErrorKind`、`trim`、`str`；明确不依赖 `xdk.log`、`xdk.execution`、`xdk.net`、`xdk.metrics`。

---

## 11. 所有权与并发

引用语义；线程安全；可跨任务共享。`_monitor` 保护全部登记状态；handler 永远在锁外调用。并发 `publish` 可能同时调用同一 handler，handler 必须线程安全或由应用串行化；跨 `publish` 不承诺顺序，单次 `publish` 内按 topic 快照的订阅顺序执行。`subscribe`/`unsubscribe`/`close` 可与 `publish` 并发：快照之后的变更不会加入当前投递；已通过活动检查的 handler 仍可能完成一次投递。`close` 不等待在途 handler，也没有后台任务资源。无全局状态；每个实例独立。

---

## 12. 示例与反例

正确：创建总线；两个 handler 订阅同一 topic；`publish` 同步返回 `Ok(2)`；`unsubscribe` 后只剩一个。  
正确：handler 返回 `Err` 时停止后续 handler，把错误交给调用方记录或重试。  
正确：handler 内取消自己或订阅新 topic；当前投递继续，后续投递按新登记执行。  
反例：依赖全局总线；期望 `publish` 异步/排队；期望 `publish` 有 `Context` 可取消；在 handler 里做长时间阻塞并期望不阻塞发布者；期望 handler 错误被自动记录；期望 `Err` 返回已投递数；`close` 后继续 `publish` 期望成功；期望 `close` 等待在途 handler；把 `EventBus` 当日志 `Logger` 使用；多个总线共享订阅 id 并期望互操作。

---

## 13. 测试/场景义务

构造空总线；订阅一个/多个/零个；同一 handler 重复订阅；`publish` 返回计数与顺序；无订阅者 `Ok(0)`；首错停止与错误原样返回；关闭后 `subscribe`/`publish`；`close` 幂等、订阅失效、清空表；`unsubscribe` 首次 true/再次 false/外来句柄；`isSubscribed` 与 `isActive` 一致；空白 topic/null 参数；精确 topic 与大小写；取消与发布竞态；handler 内取消/订阅/嵌套发布；并发发布与 handler 并发；`close` 与发布竞态；无后台线程/无日志副作用；多实例隔离；订阅 id 不复用。

---

## 14. XNull 伪代码

```xnull
class EventBus {
    final RuntimeMonitor _monitor
    final Map<String, EventSubscription> _subscriptions
    final Map<String, List<String>> _topics
    final Map<String, Result<Unit, Error>(Event)> _handlers
    Long _nextSubscriptionId = 1
    Bool _closed = false

    EventBus() {
        _monitor = new RuntimeMonitor()
        _subscriptions = [:]
        _topics = [:]
        _handlers = [:]
    }

    Result<EventSubscription, Error> subscribe(String topic,
            Result<Unit, Error>(Event) handler) {
        if topic == null || handler == null {
            throw "EventBus.subscribe: null argument"
        }
        if trim(topic) == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "event topic is blank"))
        }
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "event bus is closed"))
        }
        String subscriptionId = "sub-" + str(_nextSubscriptionId)
        _nextSubscriptionId = _nextSubscriptionId + 1
        EventSubscription subscription = new EventSubscription(self, subscriptionId, topic)
        _subscriptions.put(subscriptionId, subscription)
        _handlers.put(subscriptionId, handler)
        List<String>? ids = _topics.getOrNull(topic)
        if ids == null {
            ids = []
            _topics.put(topic, ids)
        }
        ids.push(subscriptionId)
        _monitor.exit()
        return Ok(subscription)
    }

    Result<Int, Error> publish(Event event) {
        if event == null {
            throw "EventBus.publish: null event"
        }
        List<String> targets = []
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "event bus is closed"))
        }
        List<String>? ids = _topics.getOrNull(event.topic())
        if ids != null {
            targets = ids.copy()
        }
        _monitor.exit()
        Int delivered = 0
        Int index = 0
        while index < targets.length() {
            String subscriptionId = targets.get(index)
            EventSubscription? subscription = self.subscriptionFor(subscriptionId)
            Result<Unit, Error>(Event)? handler = self.handlerFor(subscriptionId)
            if subscription != null && handler != null && subscription.isActive() {
                Result<Unit, Error> result = handler(event)
                if result.isErr() {
                    return Err(result.error())
                }
                delivered = delivered + 1
            }
            index = index + 1
        }
        return Ok(delivered)
    }

    Bool unsubscribe(EventSubscription subscription) {
        if subscription == null {
            throw "EventBus.unsubscribe: null subscription"
        }
        _monitor.enter()
        EventSubscription? existing = _subscriptions.getOrNull(subscription.id())
        if existing == null || existing != subscription {
            _monitor.exit()
            return false
        }
        _subscriptions.remove(subscription.id())
        _handlers.remove(subscription.id())
        List<String>? ids = _topics.getOrNull(subscription.topic())
        if ids != null {
            Int index = 0
            while index < ids.length() {
                if ids.get(index) == subscription.id() {
                    ids.remove(index)
                    break
                }
                index = index + 1
            }
            if ids.length() == 0 {
                _topics.remove(subscription.topic())
            }
        }
        _monitor.exit()
        return true
    }

    Bool isSubscribed(EventSubscription subscription) {
        if subscription == null {
            throw "EventBus.isSubscribed: null subscription"
        }
        _monitor.enter()
        EventSubscription? existing = _subscriptions.getOrNull(subscription.id())
        Bool result = existing != null && existing == subscription
        _monitor.exit()
        return result
    }

    Bool isClosed() {
        _monitor.enter()
        Bool result = _closed
        _monitor.exit()
        return result
    }

    void close() {
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return
        }
        _closed = true
        _subscriptions.clear()
        _handlers.clear()
        _topics.clear()
        _monitor.exit()
    }

    private EventSubscription? subscriptionFor(String subscriptionId) {
        _monitor.enter()
        EventSubscription? result = _subscriptions.getOrNull(subscriptionId)
        _monitor.exit()
        return result
    }

    private Result<Unit, Error>(Event)? handlerFor(String subscriptionId) {
        _monitor.enter()
        Result<Unit, Error>(Event)? result = _handlers.getOrNull(subscriptionId)
        _monitor.exit()
        return result
    }
}
```
