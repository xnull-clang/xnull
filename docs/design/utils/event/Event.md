# `Event`

| 项 | 值 |
| --- | --- |
| 类型 | `class Event` |
| 包 | `xdk.event` |
| 稳定性 | `preview` |
| 依赖 | `JsonValue`、`nowMono`、`trim` |

---

## 1. 定位

不可变事件信封：生产者提供的 id、精确 topic、`JsonValue` payload、单调毫秒时间戳、可选 source。

它是 `EventBus` 的输入，只描述“发生了什么”，不承担订阅、投递、存储、重试或日志职责。

不做：日志记录、结构化日志字段、序列化格式、Schema 校验、事件去重、事件持久化、墙钟时间、payload 深拷贝、投递状态。

---

## 2. 设计逻辑

- 五个字段全部 `final`；构造时校验，构造后没有 setter。
- `id` 是生产者提供的事件身份，非空白；总线不生成、不改写、不去重。id 允许重复，重复事件会被重复投递。
- `topic` 是精确路由键：非空白、大小写敏感、不做前缀/层级/通配解释；首尾空白保留且参与匹配。
- `payload` 非 null；总线把它当不透明值，不检查结构，也不做 Schema 校验。
- payload 是引用共享：`JsonObject`/`JsonArray` 本身可变，`Event` 不做深拷贝；生产者发布后不得再修改 payload，handler 应按只读使用。
- `timestampMono` 是 `>= 0` 的单调毫秒；只用于同一进程内的相对顺序，不能当墙钟时间或跨进程时间。
- `source` 是可空、不透明的来源标记；不校验内容，null 表示未提供；空串按原样保留。
- 常规创建用 `Event.now` 取当前 `nowMono()`；完整构造器用于测试、重放或显式时间戳。
- `describe` 是紧凑诊断摘要，不包含 payload 内容，避免把敏感数据写进日志或异常；不保证可逆解析。
- 不提供 `copy`：信封不可变，可安全共享；需要不同字段时重新构造，避免制造“副本是否独立”的歧义。
- 不可变信封；线程安全；无 close；无资源。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_id` | `String` | final；去空白后非空；按原样保存 |
| `_topic` | `String` | final；去空白后非空；精确匹配键 |
| `_payload` | `JsonValue` | final；非 null；引用共享 |
| `_timestampMono` | `Long` | final；`>= 0` 的单调毫秒 |
| `_source` | `String?` | final；可空；不透明 |

不变量：id/topic 非空白；payload 非 null；timestampMono 非负；字段全部 final；没有 setter；payload 的容器可变性不属于 `Event` 的不可变保证；`describe` 不输出 payload。

---

## 4. 生命周期

由生产者、测试或重放代码构造；构造后可长期共享，也可被多次 `publish`。不可变，无 close，无资源；回收由 GC 管理。`EventBus` 不在投递后保留事件，handler 收到的是同一个引用。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Event(String eventId, String topic, JsonValue payload, Long timestampMono, String? source)` | 全部 | eventId/topic 去空白非空；payload 非 null；timestampMono `>= 0`；source 可 null | null/空白 id 或 topic、null payload、负时间戳 → panic |
| `Event.now(String eventId, String topic, JsonValue payload, String? source)` | 除时间戳外同上 | 同上；时间戳取 `nowMono()` | 同上 → panic |

说明：

- `Event.now` 只是便捷工厂，不改变校验；需要固定时间戳时使用完整构造器。
- `source` 允许 null；不提供默认参数，调用方必须显式传 `null` 或字符串。
- 构造器不访问总线、不注册订阅、不执行 handler。

---

## 6. 字段表

见 §3；字段私有且 `final`。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `id` | 事件身份 | 无 | `String` | 无 |
| `topic` | 路由 topic | 无 | `String` | 无 |
| `payload` | 事件载荷引用 | 无 | `JsonValue` | 无 |
| `timestampMono` | 单调时间戳 | 无 | `Long` | 无 |
| `source` | 来源/无 | 无 | `String?` | 无 |
| `describe` | 单行诊断摘要 | 无 | `String` | 无 |
| `now` | 当前时间工厂 | `String eventId, String topic, JsonValue payload, String? source` | `Event` | 非法 → panic |

说明：

- `payload()` 返回构造时的引用，不复制；调用方修改 `JsonObject`/`JsonArray` 会影响所有持有该引用的人。
- `source()` 返回 null 表示未提供；空串是合法值。
- `describe()` 包含 id、topic、timestampMono、source 和 payload 的 kind，不包含 payload 内容，也不转义分隔符。
- 不提供 `copy`/`with*`：不可变值直接共享；派生事件必须重新走构造校验。
- 不提供 `equals`/`hashCode`；需要值比较时逐字段比较，不依赖引用身份以外的隐式语义。

---

## 8. 使用的技术

- 不可变值对象；
- 构造期校验；
- 单调时间戳；
- 可空元数据；
- 引用共享与只读约定；
- 紧凑字符串摘要。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Long、Bool、可空类型、字符串拼接；
- 运行时：`nowMono`；
- 接口：`JsonValue`、`trim`、`str`。

---

## 10. 依赖的特性/接口/类

`JsonValue`、`nowMono`、`trim`、`str`；不依赖 `xdk.log`、`EventBus` 或 `EventSubscription`。`Event` 可以在没有总线的情况下单独构造和测试。

---

## 11. 所有权与并发

引用语义；信封字段不可变，可跨任务共享，读取无锁。payload 引用共享且可能包含可变容器，`Event` 不提供同步；生产者与消费者必须遵守只读约定。无资源、无 close、无取消点。`describe` 只读，线程安全。

---

## 12. 示例与反例

正确：`Event.now("evt-1", "orders.created", JsonValue.string("42"), "checkout")`；同一事件发布两次会投递两次。  
正确：重放时用完整构造器固定 `timestampMono`，保留原事件相对顺序。  
反例：空 id/topic；null payload；负时间戳；发布后继续修改 payload 的 `JsonObject`；用 `timestampMono` 当墙钟时间；期望 `Event` 深拷贝 payload；把 `describe` 当 JSON 解析；用 `Event` 的 id 当全局去重键。

---

## 13. 测试/场景义务

构造校验：null/空白 id、null/空白 topic、null payload、负时间戳；首尾空白保留但全空白拒绝；`source` null/空串/普通字符串；`timestampMono` 为 0 合法；`now` 工厂产生非负时间戳；`describe` 不泄露 payload 内容；payload 引用共享；同一事件重复发布；并发读取；不可变字段无 setter；topic 大小写与精确匹配由总线场景覆盖。

---

## 14. XNull 伪代码

```xnull
class Event {
    final String _id
    final String _topic
    final JsonValue _payload
    final Long _timestampMono
    final String? _source

    Event(String eventId, String topic, JsonValue payload,
          Long timestampMono, String? source) {
        if eventId == null || topic == null || payload == null {
            throw "Event: null argument"
        }
        if trim(eventId) == "" {
            throw "Event: empty id"
        }
        if trim(topic) == "" {
            throw "Event: empty topic"
        }
        if timestampMono < 0 {
            throw "Event: negative timestamp"
        }
        _id = eventId
        _topic = topic
        _payload = payload
        _timestampMono = timestampMono
        _source = source
    }

    static Event now(String eventId, String topic, JsonValue payload,
                     String? source) {
        return new Event(eventId, topic, payload, nowMono(), source)
    }

    String id() { return _id }
    String topic() { return _topic }
    JsonValue payload() { return _payload }
    Long timestampMono() { return _timestampMono }
    String? source() { return _source }

    String describe() {
        String head = "Event(id=" + _id + ", topic=" + _topic
        String time = ", mono=" + str(_timestampMono)
        String origin = ", source=" + (_source ?? "(none)")
        String kind = ", payloadKind=" + str(_payload.kind())
        return head + time + origin + kind + ")"
    }
}
```
