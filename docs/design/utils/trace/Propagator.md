# `Propagator`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol Propagator` |
| 包 | `xdk.trace` |
| 稳定性 | `preview` |
| 依赖 | `SpanContext`、`Map`、`List`、`Unit` |

---

## 1. 定位

跨进程/跨消息传播 trace 上下文的最小协议：把 `SpanContext` 注入字符串载体，或从载体提取。

不做：导出 span、采样、日志、序列化任意对象、tracestate、B3/Jaeger 具体格式实现。

---

## 2. 设计逻辑

- 非泛型协议；实现负责具体格式（W3C traceparent、B3 等）。
- `name()` 返回稳定小写标识，例如 `w3c`、`b3`；`fields()` 返回会读写的头字段名。
- `inject(context, carrier)` 成功返回 `unit`；无效上下文按 no-op 处理，不阻塞业务。
- `extract(carrier)` 缺失或格式错误返回 null；部分字段损坏不抛异常。
- `SpanContext` 的 sampled 标志必须传播；即使未采样也要写 traceparent（flags=00），便于下游关联。
- carrier 是调用方提供的可变 `Map<String,String>`；实现只增删自己的字段，不清空其他键。
- baggage 传播按实现格式编码；当前内置 W3C 实现只承诺 traceparent + 简单 baggage，tracestate 为 X。
- 无 close；实现应不可变/无状态，线程安全。

---

## 3. 表示与不变量

协议无字段。

实现不变量：`name()` 非空且稳定；`fields()` 不返回 null；`inject` 不删除无关键；`extract` 不因单个坏字段崩溃；同一 carrier 上 `inject` 后 `extract`（在支持的字段上）应可往返。

---

## 4. 生命周期

协议无构造；实现对象由调用方/`Tracer` 持有；无 close；无资源。

---

## 5. 构造契约

协议无构造；实现类自行定义构造/工厂。

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 协议标识 | 无 | `String` | 无 |
| `fields` | 读写的头字段 | 无 | `List<String>` | 无 |
| `inject` | 写入载体 | `SpanContext, Map<String,String>` | `Unit` | null → panic；无效上下文 no-op |
| `extract` | 读取载体 | `Map<String,String>` | `SpanContext?` | null → panic；缺失/损坏 → null |

说明：

- `inject` 的 carrier 允许是只读 Map 时，实现应 panic 或抛错；当前契约要求可变 Map。
- `extract` 返回的是**远端 span 上下文**：traceId 来自载体，spanId 是远端 span 的 spanId，parentSpanId 为 null；调用方把它作为 `startSpan` 的 parent。
- 采样标志无效/缺失按 0 处理；traceparent 缺失或 traceId/spanId 非法返回 null。
- baggage 解析失败的条目跳过；超过 `SpanContext` 上限的条目丢弃。
- `fields()` 至少包含 `traceparent`；W3C 实现同时包含 `baggage`。

---

## 8. 使用的技术

- 非泛型协议；
- W3C trace context 文本格式；
- 百分号编码的 baggage；
- 容错解析；
- 防御性复制。

---

## 9. 需要的支撑

- 语言：protocol、String、Map、List、Unit、可空引用；
- 运行时：字符串分割/拼接、百分号编码辅助；
- 接口：`SpanContext`。

---

## 10. 依赖的特性/接口/类

`SpanContext`、`Map`、`List`、`Unit`。

---

## 11. 所有权与并发

协议不持有状态；实现应不可变或无共享可变状态；carrier 归调用方所有；实现若被多个任务共享必须线程安全。

---

## 12. 示例与反例

正确：

```text
Propagator propagator = TraceRuntime.defaultPropagator()
propagator.inject(span.context(), headers)
SpanContext? remote = propagator.extract(headers)
```

反例：`extract` 把远端上下文当成新根；`inject` 清空 carrier；缺失 traceparent 时抛异常；把 tracestate 当已支持；在 `inject` 中修改 `SpanContext`。

---

## 13. 测试/场景义务

inject/extract 往返；缺失 traceparent；非法长度/非十六进制；全零 ID；sampled=0/1；baggage 往返；baggage 坏条目；无关键保留；重复 `inject` 覆盖自己的字段；null 参数；多实现的一致性。

---

## 14. XNull 伪代码

```xnull
protocol Propagator {
    String name();
    List<String> fields();
    Unit inject(SpanContext context, Map<String, String> carrier);
    SpanContext? extract(Map<String, String> carrier);
}
```
