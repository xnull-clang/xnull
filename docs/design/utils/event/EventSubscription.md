# `EventSubscription`

| 项 | 值 |
| --- | --- |
| 类型 | `class EventSubscription` |
| 包 | `xdk.event` |
| 稳定性 | `preview` |
| 依赖 | `EventBus`、`trim` |

---

## 1. 定位

单个 topic 订阅的轻量句柄：订阅 id、topic、取消、活动状态。

它不持有 handler，不负责投递，也不拥有总线；活动状态由所属 `EventBus` 的登记表决定。

不做：handler 访问、事件投递、重试、异步取消、优先级、过滤、持久化。

---

## 2. 设计逻辑

- 三个 final 字段：所属总线、订阅 id、topic；没有本地可变状态。
- 只由 `EventBus.subscribe` 创建；id 由总线生成（`sub-N`），在单个总线内唯一，跨总线不保证。
- topic 与 `Event.topic` 使用同一规则：精确、大小写敏感、首尾空白保留；空白 topic 拒绝。
- `cancel` 委托 `EventBus.unsubscribe(self)`；成功移除返回 true，已取消/已关闭/外来句柄返回 false。
- `isActive` 委托 `EventBus.isSubscribed(self)`；只认“同一总线登记表中的同一实例”。
- 取消幂等：第一次成功返回 true，之后返回 false；不会抛错，也不会重复移除。
- 总线关闭后所有订阅失效；`isActive` 返回 false，`cancel` 返回 false。
- 取消与投递存在固有竞态：已经通过活动检查的 handler 可能继续完成一次投递；`cancel` 不等待运行中的 handler。
- 构造器在 XNull 中只能公开；应用不应直接构造，否则得到的句柄没有登记，`isActive` 恒为 false。
- 线程安全由总线监视器保证；句柄本身无锁、无资源、无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_bus` | `EventBus` | final；所属总线，非 null |
| `_id` | `String` | final；总线生成的订阅 id，去空白非空 |
| `_topic` | `String` | final；去空白后非空，按原样保存 |

不变量：三个字段 final；`_bus` 非 null；`_id` 非空白；`_topic` 非空白；没有本地 active 标志；“活动”等价于 `_bus.isSubscribed(self) == true`。

---

## 4. 生命周期

由 `EventBus.subscribe` 创建并登记；活动直到 `cancel`、`EventBus.unsubscribe` 或 `EventBus.close`。失效后句柄仍可查询 id/topic，`isActive` 为 false，`cancel` 为 false；无 close，GC 回收。句柄持有总线引用；应用长期保留失效句柄会延迟总线对象回收，但不会保留 handler（总线已移除登记）。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `EventSubscription(EventBus ownerBus, String subscriptionId, String topic)` | 全部 | ownerBus 非 null；subscriptionId 去空白非空；topic 去空白非空 | null/空白 id/空白 topic → panic |

说明：

- 构造器不向总线登记；它只建立句柄。
- XNull 没有包内可见性，因此构造器公开；约定只由 `EventBus.subscribe` 调用。
- 手工构造的句柄不会获得投递；`isActive` 为 false，`cancel` 为 false。
- 不提供默认参数；source 等事件字段不属于订阅句柄。

---

## 6. 字段表

见 §3；字段私有且 `final`。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `id` | 订阅 id | 无 | `String` | 无 |
| `topic` | 订阅 topic | 无 | `String` | 无 |
| `cancel` | 取消订阅 | 无 | `Bool` | 无 |
| `isActive` | 是否仍活动 | 无 | `Bool` | 无 |

说明：

- `cancel` 返回 true 表示本次调用从总线移除了活动登记；再次调用或总线已关闭返回 false。
- `cancel` 不抛异常、不等待 handler、不改变事件或 payload。
- `isActive` 是瞬时快照；返回 true 后可能立刻被其他任务取消，调用方不能把返回值当作后续投递保证。
- 不支持把句柄用于其他总线；把句柄交给其他总线的 `unsubscribe`/`isSubscribed` 恒为 false。
- 不提供 handler 访问器、`publish`、`close`；这些职责属于 `EventBus`。
- 不提供 `equals`/`hashCode`；按引用身份识别，不能作为跨总线 Map 键。

---

## 8. 使用的技术

- 句柄/委托；
- 身份校验；
- 总线持有的登记状态；
- 幂等取消；
- 无锁句柄。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Bool、引用类型；
- 运行时：`RuntimeMonitor`（由 `EventBus` 持有）；
- 接口：`EventBus.unsubscribe`、`EventBus.isSubscribed`、`trim`。

---

## 10. 依赖的特性/接口/类

`EventBus`、`EventBus.unsubscribe`、`EventBus.isSubscribed`、`trim`；不依赖 `Event`、`xdk.log`、执行层或网络层。

---

## 11. 所有权与并发

引用语义；句柄可在任务间共享；`cancel`/`isActive` 线程安全，因为状态操作全部进入总线监视器。多个任务同时 `cancel` 同一句柄时，只有一个得到 true。`isActive` 返回后状态可立即变化；取消不等待已经运行的 handler。无资源、无 close、无取消点。

---

## 12. 示例与反例

正确：`EventSubscription subscription = bus.subscribe("orders.created", handler).value()`；`subscription.cancel()` 第一次 true，第二次 false。  
正确：handler 内取消自己；当前 handler 继续完成，后续投递不再选中。  
反例：手工 `new EventSubscription(bus, "x", "topic")` 后期望收到事件；把 A 总线的句柄传给 B 总线并期望取消成功；`cancel` 后立即期望正在运行的 handler 被中断；重复 `cancel` 期望一直 true；关闭后期望 `isActive` 仍为 true；把句柄当事件或日志记录。

---

## 13. 测试/场景义务

id/topic 读取；构造 null/空 id/空白 topic；`cancel` 首次 true、再次 false；`isActive` 前后变化；总线 close 后 `isActive` false、`cancel` false；跨总线/伪造 id 的句柄；并发 `cancel` 只有一个 true；`cancel` 与 `publish` 竞态；取消自己与取消后续 handler；失效句柄仍可读 id/topic；同一订阅重复取消不抛错。

---

## 14. XNull 伪代码

```xnull
class EventSubscription {
    final EventBus _bus
    final String _id
    final String _topic

    EventSubscription(EventBus ownerBus, String subscriptionId, String topic) {
        if ownerBus == null || subscriptionId == null || topic == null {
            throw "EventSubscription: null argument"
        }
        if trim(subscriptionId) == "" {
            throw "EventSubscription: empty id"
        }
        if trim(topic) == "" {
            throw "EventSubscription: empty topic"
        }
        _bus = ownerBus
        _id = subscriptionId
        _topic = topic
    }

    String id() { return _id }
    String topic() { return _topic }

    Bool cancel() {
        return _bus.unsubscribe(self)
    }

    Bool isActive() {
        return _bus.isSubscribed(self)
    }
}
```
