# `Processor`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol Processor` |
| 包 | `xdk.agent` |
| 稳定性 | `preview` |
| 依赖 | `TelemetryKind`、`TelemetryBatch`、`Context`、`Error`、`Result` |

---

## 1. 定位

遥测处理协议：在接收器与导出器之间变换、过滤、聚合或限流批次。

实现可以是无状态变换（属性修改、过滤）、有状态聚合（batch）或资源门控（memory limiter）。
协议只规定输入、下游、生命周期与错误语义。

不做：管线编排、fan-out、接收器/导出器选择、配置解析、全局注册。

---

## 2. 设计逻辑

- 非泛型协议；输入/输出都是 `TelemetryBatch`；
- `start` 非阻塞，接收 downstream 回调；处理器可在 `process` 中同步调用，也可缓冲后异步调用；
- 处理器必须串行化对 downstream 的调用；不得并发调用同一 downstream；
- `process` 可以：转发一个批次、拆分多个批次、过滤为零个批次；过滤是显式丢弃，不调用 downstream；
- `process` 返回错误表示上游应重试/降速；返回 `Ok(unit)` 不代表一定已交付（可能已缓冲）；
- 有状态处理器必须提供有界缓冲；满时返回 `Busy` 或按显式策略丢弃并计数；
- `drain` 冲刷所有缓冲并等待 downstream；`close` 停止定时器/释放资源；
- 处理器没有 `stop`：管线停止向它 `process`，然后 `drain`；这避免“停止入口”和“冲刷”混淆；
- `isHealthy` 反映内部错误/受限状态；批处理器在 pending 过高时可返回 false。

---

## 3. 表示与不变量

协议无字段。实现必须保证：

- `kind()` 稳定且非 null；
- `name()` 非空、单行、在同一 Agent 内唯一；
- `start` 成功后才能 `process`/`drain`；`start` 返回前不得调用 downstream；
- `process` 只接受与 `kind()` 相同的批次；不同 kind 是合同错误；
- 处理器不修改输入批次；需要修改时构造新批次/新记录；
- 缓冲有界；丢弃有计数；
- `close` 后不再调用 downstream；
- `start` 重复调用幂等；未 `start` 调用 `process` 返回 `Unavailable`。

---

## 4. 生命周期

```text
构造 → start → process（多次）→ drain → close
```

- `start`：绑定 downstream；重复调用返回 `Ok(unit)`；已关闭 → `Unavailable`；
- `process`：可多次；未启动/已关闭 → `Unavailable`；下游错误原样返回；
- `drain`：可重复；冲刷缓冲并等待；取消返回 `Cancelled`；关闭后返回 `Unavailable`；
- `close`：可重复；停止定时器；未 drain 的数据丢弃并计数；不关闭 downstream；
- 无 `stop`；管线用“停止喂入 + drain”表达停止。

---

## 5. 构造契约

协议无构造；实现定义依赖注入。构造器必须校验：

- kind/name 非空；
- 缓冲/队列容量 >0（如有）；
- 阈值/时间参数非负且在合法域；
- 溢出策略属于固定三种；
- 注入依赖非 null；
- 非法配置 panic 或返回 `InvalidArgument`（由实现选择并在类型文档写明）。

---

## 6. 字段表

无协议字段；实现字段由具体类型定义。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `kind` | 遥测种类 | 无 | `TelemetryKind` | 无 |
| `name` | 处理器名 | 无 | `String` | 无 |
| `start` | 绑定下游 | `Context context, Result<Unit, Error>(TelemetryBatch) downstream` | `Result<Unit, Error>` | `Unavailable`/`InvalidArgument`/`Cancelled`/`Internal` |
| `process` | 处理一个批次 | `Context context, TelemetryBatch batch` | `Result<Unit, Error>` | `Busy`/`Cancelled`/`Unavailable`/`Internal` |
| `drain` | 冲刷缓冲 | `Context context` | `Result<Unit, Error>` | `Busy`/`Cancelled`/`Unavailable`/`Internal` |
| `close` | 释放资源 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isHealthy` | 是否健康 | 无 | `Bool` | 无 |

说明：

- `start` 对 null context/downstream → panic；重复 start 幂等；
- `process` 对 null context/batch → panic；kind 不匹配 → panic（合同错误）；
- `process` 可在内部把批次放入有界缓冲；缓冲满返回 `Busy`，让上游重试或降速；
- 处理器调用 downstream 时使用传入的 `context` 或其子上下文；不得在 close 后使用；
- `drain` 对 null context → panic；无缓冲返回 `Ok(unit)`；
- `close` 幂等；已关闭返回 `Ok(unit)`；不关闭 downstream；
- `isHealthy` 对未启动/已关闭返回 false；运行中由实现定义。

---

## 8. 使用的技术

- 非泛型协议；
- 函数类型 downstream；
- 无状态变换/有状态缓冲；
- 有界队列；
- 背压与显式丢弃；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：protocol、class、String、Bool、Result、Unit、函数类型；
- 运行时：`Context`、`Timer`（批处理器）、`nowMono`；
- 接口：`TelemetryKind`、`TelemetryBatch`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`TelemetryKind`、`TelemetryBatch`、`Context`、`Error`、`Result`、`Unit`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

- 引用语义；实现由 AgentPipeline 持有；
- `start`/`process`/`drain`/`close` 可并发调用，但实现必须串行化状态与 downstream 调用；
- 输入批次由调用方拥有；处理器不得修改，可保留引用（批次不可变）；
- 输出批次由处理器创建并交给 downstream；downstream 不拥有处理器；
- `isHealthy` 可并发读取；
- 同一处理器实例不应跨管线共享；每条管线独立实例。

---

## 12. 示例与反例

正确：

```xnull
Result<Unit, Error> started = processor.start(context, (TelemetryBatch batch) -> exporter.export(context, batch))
if started.isErr() { return started }
Result<Unit, Error> processed = processor.process(context, batch)
if processed.isErr() { return processed }
Result<Unit, Error> drained = processor.drain(context)
processor.close()
```

反例：`process` 并发调用 downstream；过滤批次但不计数；无限缓冲；`close` 关闭 downstream；
在 `process` 中修改输入批次；未 start 就调用 process。

---

## 13. 测试/场景义务

start/process/drain/close 顺序；重复 start/drain/close；未启动 process；kind 不匹配；
同步转发/缓冲后异步转发/过滤；downstream `Busy`/`Cancelled`/`Unavailable`；
有界缓冲满；三种溢出策略；丢弃计数；并发 process；健康状态；null 参数。

---

## 14. XNull 伪代码

```xnull
protocol Processor {
    TelemetryKind kind();
    String name();
    Result<Unit, Error> start(Context context,
        Result<Unit, Error>(TelemetryBatch) downstream);
    Result<Unit, Error> process(Context context, TelemetryBatch batch);
    Result<Unit, Error> drain(Context context);
    Result<Unit, Error> close();
    Bool isHealthy();
}
```
