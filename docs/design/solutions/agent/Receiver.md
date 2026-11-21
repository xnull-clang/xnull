# `Receiver`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol Receiver` |
| 包 | `xdk.agent` |
| 稳定性 | `preview` |
| 依赖 | `TelemetryKind`、`TelemetryBatch`、`Context`、`Error`、`Result` |

---

## 1. 定位

遥测接收协议：声明 kind/名称，启动一个采集源，把批次推送给下游，并提供 stop/drain/close 生命周期。

实现可以是推送型（OTLP 接收器）或拉取型（主机指标、文件日志、Prometheus 抓取）；协议只要求
“启动后把批次交给 downstream”。

不做：管线编排、处理器/导出器选择、全局注册、配置解析、远程控制。

---

## 2. 设计逻辑

- 非泛型协议；所有数据以 `TelemetryBatch` 传递；
- `start` 非阻塞：实现自行启动任务/监听；返回后 `isRunning()` 为 true；
- `downstream` 是函数类型 `Result<Unit, Error>(TelemetryBatch)`；接收器只调用，不拥有、不关闭；
- 接收器必须串行化对 `downstream` 的调用（同一时刻最多一个），避免下游处理器重入；
- `downstream` 返回 `Busy`/`Unavailable`/`Cancelled` 时，接收器按自身有界队列与溢出策略处理：
  重试、暂停读取、拒绝或丢弃；不得静默丢弃；`reject` 返回错误，丢弃策略返回 `Ok(unit)` 并计数；
- `stop` 停止入口，不丢弃已接收批次；`drain` 冲刷缓冲并等待下游；`close` 释放资源；
- `close` 幂等；关闭后 `start` 返回 `Unavailable`；
- `isHealthy` 反映最近采集/读取失败，不等同于 `isRunning`；运行中但持续失败可为 false；
- 接收器拥有自己的文件/定时器/监听资源；不拥有 downstream、OsHost、HttpServer 等注入依赖。

---

## 3. 表示与不变量

协议无字段。实现必须保证：

- `kind()` 在生命周期内稳定且非 null；
- `name()` 非空、单行、在同一 Agent 内唯一；
- `start` 成功后才能调用 `downstream`；`start` 返回前不得同步调用 downstream（避免管线尚未提交运行态）；
- `stop` 后不再产生新批次；`drain` 只交付已接收批次；
- `close` 后不再调用 `downstream`；
- 队列有界；容量与溢出策略在实现构造器显式给出；
- 丢弃有计数；健康状态可查询。

---

## 4. 生命周期

```text
构造 → start → 运行（推送批次）→ stop → drain → close
```

- `start`：非阻塞；重复调用返回 `Ok(unit)`；已关闭 → `Unavailable`；
- `stop`：可重复；第一次停止入口并取消内部任务；不自动 drain；
- `drain`：可重复；可在 stop 前或 stop 后调用；取消返回 `Cancelled`；
- `close`：可重复；未 drain 的批次按实现策略丢弃并计数；不关闭 downstream；
- 关闭后 `isRunning` 为 false，`isHealthy` 为 false。

---

## 5. 构造契约

协议无构造；实现定义依赖注入。构造器必须校验：

- kind/name 非空；
- 队列容量 >0（如实现有队列）；
- 溢出策略属于 `reject`/`drop_oldest`/`drop_newest`；
- 注入的依赖（文件系统、OsHost、时钟）非 null；
- 非法配置在构造时 panic 或返回 `InvalidArgument`（由实现选择并在类型文档写明）。

---

## 6. 字段表

无协议字段；实现字段由具体类型定义。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `kind` | 遥测种类 | 无 | `TelemetryKind` | 无 |
| `name` | 接收器名 | 无 | `String` | 无 |
| `start` | 启动采集 | `Context context, Result<Unit, Error>(TelemetryBatch) downstream` | `Result<Unit, Error>` | `Unavailable`/`InvalidArgument`/`Cancelled`/`Internal` |
| `stop` | 停止入口 | `Context context` | `Result<Unit, Error>` | `Cancelled`/`Internal` |
| `drain` | 冲刷在途 | `Context context` | `Result<Unit, Error>` | `Busy`/`Cancelled`/`Internal` |
| `close` | 释放资源 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isRunning` | 是否运行 | 无 | `Bool` | 无 |
| `isHealthy` | 是否健康 | 无 | `Bool` | 无 |

说明：

- `start` 的 `context` 用于启动阶段的监听/打开文件/初始探测；启动后内部任务使用自己的子上下文；
- `start` 对 null context/downstream 是合同错误 → panic；重复 start 幂等；
- `downstream` 抛出的可恢复错误原样返回给接收器内部循环；接收器不得吞掉；
- `stop` 对 null context → panic；已停止/未启动返回 `Ok(unit)`；
- `drain` 对 null context → panic；无缓冲实现返回 `Ok(unit)`；下游持续 `Busy` 时返回 `Busy`；
- `close` 不报告 downstream 错误；它只释放自身资源；已关闭返回 `Ok(unit)`；
- `isHealthy` 对未启动/已关闭返回 false；运行中由实现根据最近错误定义。

---

## 8. 使用的技术

- 非泛型协议；
- 推送/拉取适配；
- 函数类型 downstream；
- 有界队列；
- 背压与显式丢弃；
- 幂等关闭；
- 健康快照。

---

## 9. 需要的支撑

- 语言：protocol、class、String、Bool、Result、Unit、函数类型；
- 运行时：`Context`、`Task`/`Timer`（实现决定）、`nowMono`；
- 接口：`TelemetryKind`、`TelemetryBatch`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`TelemetryKind`、`TelemetryBatch`、`Context`、`Error`、`Result`、`Unit`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

- 引用语义；实现由 AgentPipeline 持有；
- `start`/`stop`/`drain`/`close` 可由不同任务并发调用，但实现必须串行化状态转换；
- `downstream` 由调用方（管线）提供，接收器不拥有；
- 接收器内部的队列/文件/定时器由实现拥有并关闭；
- `isRunning`/`isHealthy` 可并发读取；
- 同一接收器不应被多个 Agent 共享；需要多路复制时由管线 fan-out。

---

## 12. 示例与反例

正确：

```xnull
Result<Unit, Error> started = receiver.start(context, (TelemetryBatch batch) -> pipeline.consume(context, batch))
if started.isErr() { return started }
Result<Unit, Error> stopped = receiver.stop(context)
Result<Unit, Error> drained = receiver.drain(context)
receiver.close()
```

反例：`start` 内同步阻塞到进程结束；在 `stop` 后继续调用 downstream；丢弃批次但不计数；
`close` 关闭 downstream；多个 Agent 共享同一接收器；忽略 downstream 的 `Busy`。

---

## 13. 测试/场景义务

start/stop/drain/close 顺序；重复 start/stop/drain/close；未启动 drain；关闭后 start；
downstream `Busy`/`Cancelled`/`Unavailable`；有界队列满；三种溢出策略；丢弃计数；
并发 start/stop；健康状态；name/kind 稳定；null 参数。

---

## 14. XNull 伪代码

```xnull
protocol Receiver {
    TelemetryKind kind();
    String name();
    Result<Unit, Error> start(Context context,
        Result<Unit, Error>(TelemetryBatch) downstream);
    Result<Unit, Error> stop(Context context);
    Result<Unit, Error> drain(Context context);
    Result<Unit, Error> close();
    Bool isRunning();
    Bool isHealthy();
}
```
