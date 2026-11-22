# `PipelineExporter`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol PipelineExporter` |
| 包 | `xdk.agent` |
| 稳定性 | `preview` |
| 依赖 | `TelemetryKind`、`TelemetryBatch`、`Context`、`Error`、`Result` |

---

## 1. 定位

遥测导出协议：把批次发送到远端或本地目标，并声明 kind、名称、启动/冲刷/关闭生命周期。

实现可以是网络推送（OTLP）、本地抓取视图（Prometheus）或测试用内存导出器。协议只规定
“接收批次、可排队、可冲刷、可关闭”，不规定编码与传输。

不做：管线 fan-out、接收器/处理器选择、配置解析、全局注册、认证扩展、后端 SDK。

---

## 2. 设计逻辑

- 非泛型协议；输入是 `TelemetryBatch`；一次 `export` 只接受同 kind 批次；
- `start` 准备连接/资源；`export` 可同步发送或进入有界队列；
- 队列满返回 `Busy`，由管线/接收器决定重试或丢弃；不静默丢；
- 允许实现按显式策略丢弃（如 `drop_oldest`/`drop_newest`），必须计数并可观察；
- `drain` 等待队列清空与在途请求完成；取消返回 `Cancelled`；
- `close` 幂等；未 drain 的队列丢弃并计数；实现拥有自己的 HttpClient/文件/缓冲；
- 导出语义是 at-least-once；重试可能重复，不承诺 exactly-once；
- `isHealthy` 反映最近导出失败/队列状态；运行中但持续失败可为 false；
- 导出器不拥有调用方 Writer/HttpClient（若注入），只拥有自己创建的连接资源。

---

## 3. 表示与不变量

协议无字段。实现必须保证：

- `kind()` 稳定且非 null；
- `name()` 非空、单行、在同一 Agent 内唯一；
- `start` 成功后才能 `export`/`drain`；
- `export` 对 null/不同 kind 批次 panic；对已关闭返回 `Unavailable`；
- 队列有界；容量与溢出策略在构造器显式给出；
- 丢弃有计数；`isHealthy` 可查询；
- `close` 后不再发起网络请求，不再接受批次；
- `drain` 不关闭导出器；`close` 不自动 drain（Agent 负责顺序）。

---

## 4. 生命周期

```text
构造 → start → export（多次）→ drain → close
```

- `start`：可阻塞（DNS/连接/打开文件），首参 `Context`；重复调用返回 `Ok(unit)`；
- `export`：可阻塞（同步发送）或非阻塞（入队）；取消返回 `Cancelled`；
- `drain`：可重复；清空队列并等待在途；取消返回 `Cancelled`；
- `close`：可重复；停止工作线程、关闭自有资源；未 drain 队列丢弃并计数；
- 关闭后 `start`/`export`/`drain` 返回 `Unavailable`。

---

## 5. 构造契约

协议无构造；实现定义依赖注入。构造器必须校验：

- kind/name 非空；
- 目标地址/协议/路径合法；
- 队列容量 >0；溢出策略属于固定三种；
- 超时/重试参数在合法域；
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
| `name` | 导出器名 | 无 | `String` | 无 |
| `start` | 准备导出 | `Context context` | `Result<Unit, Error>` | `Network`/`Timeout`/`Cancelled`/`Unavailable`/`Internal` |
| `export` | 导出一个批次 | `Context context, TelemetryBatch batch` | `Result<Unit, Error>` | `Busy`/`Network`/`Timeout`/`Cancelled`/`Unavailable`/`DataCorrupted`/`Internal` |
| `drain` | 冲刷队列 | `Context context` | `Result<Unit, Error>` | `Busy`/`Timeout`/`Cancelled`/`Unavailable`/`Internal` |
| `close` | 释放资源 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isHealthy` | 是否健康 | 无 | `Bool` | 无 |

说明：

- `start` 对 null context → panic；重复 start 幂等；不能重新打开已关闭实例；
- `export` 对 null context/batch → panic；kind 不匹配 → panic；队列满 → `Busy`；
- `export` 返回 `Ok(unit)` 表示“已发送或已入队”，不保证后端已持久化；
- 同步实现可在 `export` 内完成重试；异步实现由工作线程重试，`drain` 等待完成；
- `drain` 对 null context → panic；无队列实现返回 `Ok(unit)`；
- `close` 幂等；已关闭返回 `Ok(unit)`；不关闭注入的 Writer/HttpClient；
- `isHealthy` 对未启动/已关闭返回 false；运行中由实现根据最近失败定义。

---

## 8. 使用的技术

- 非泛型协议；
- 有界发送队列；
- 同步/异步导出；
- 重试与退避（实现决定）；
- at-least-once；
- 幂等关闭；
- 健康快照。

---

## 9. 需要的支撑

- 语言：protocol、class、String、Bool、Result、Unit；
- 运行时：`Context`、`Task`/`Timer`（实现决定）、`nowMono`；
- 接口：`TelemetryKind`、`TelemetryBatch`、`Error`、`BasicError`、`ErrorKind`、`RetryPolicy`（可选）。

---

## 10. 依赖的特性/接口/类

`TelemetryKind`、`TelemetryBatch`、`Context`、`Error`、`Result`、`Unit`、`BasicError`、`ErrorKind`、
`RetryPolicy`（实现可选）。

---

## 11. 所有权与并发

- 引用语义；实现由 AgentPipeline 持有；
- `start`/`export`/`drain`/`close` 可并发调用，但实现必须串行化状态与队列；
- 输入批次由调用方拥有；导出器不得修改；可保留引用（批次不可变）；
- 导出器拥有自己的队列/工作线程/连接；注入的 Writer/HttpClient 所有权由构造契约写明；
- `isHealthy` 可并发读取；
- 同一导出器可被多条管线使用（fan-out），但实现必须线程安全；基线建议一条管线一个实例。

---

## 12. 示例与反例

正确：

```xnull
Result<Unit, Error> started = exporter.start(context)
if started.isErr() { return started }
Result<Unit, Error> exported = exporter.export(context, batch)
if exported.isErr() { return exported }
Result<Unit, Error> drained = exporter.drain(context)
exporter.close()
```

反例：队列满时静默丢弃；`export` 返回 Ok 但从未发送且无计数；`close` 关闭调用方 Writer；
`drain` 不等待在途请求；导出器修改批次；多个管线共享非线程安全实例。

---

## 13. 测试/场景义务

start/export/drain/close 顺序；重复 start/drain/close；未启动 export；kind 不匹配；
队列满 `Busy`/丢弃策略；同步/异步导出；重试成功/耗尽；Context 取消；drain 等待在途；
close 后 Unavailable；不关闭注入资源；健康状态；并发 export；null 参数。

---

## 14. XNull 伪代码

```xnull
protocol PipelineExporter {
    TelemetryKind kind();
    String name();
    Result<Unit, Error> start(Context context);
    Result<Unit, Error> export(Context context, TelemetryBatch batch);
    Result<Unit, Error> drain(Context context);
    Result<Unit, Error> close();
    Bool isHealthy();
}
```
