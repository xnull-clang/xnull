# `Connector`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol Connector` |
| 包 | `xdk.agent` |
| 稳定性 | `preview` |
| 依赖 | `TelemetryKind`、`TelemetryBatch`、`Context`、`Error`、`Result` |

---

## 1. 定位

跨管线连接协议：在一条管线的末端消费批次，在另一条管线的起点产出批次。

连接器同时具有导出侧（`consume`）与接收侧（`start` + downstream）；输入/输出 kind 可相同，
也可不同（例如 traces → metrics 的计数连接器）。

不做：管线编排、fan-out、组件注册、配置解析、内置 count/router 实现。

---

## 2. 设计逻辑

- 非泛型协议；输入/输出都是 `TelemetryBatch`；
- `inputKind()` 必须匹配源管线 kind；`outputKind()` 必须匹配目标管线 kind；
- `consume` 是导出侧：源管线像调用 Exporter 一样调用它；
- `start` 是接收侧：目标管线把 downstream 交给它；连接器在转换/聚合后向下游推送；
- 一个连接器实例必须且只能接入一条源管线和一条目标管线；
- 连接器由 `Agent` 拥有生命周期，`AgentPipeline` 只引用；避免两条管线重复 start/close；
- 连接器不得形成环；Agent 启动时校验连接图；
- 连接器可以缓冲/聚合；缓冲有界；满时返回 `Busy` 或显式丢弃并计数；
- 同 kind 连接器可以路由/复制；跨 kind 连接器可以聚合（traces/logs → metrics）；
- 连接器不是 `Exporter`/`Receiver` 的子协议，避免单一 `kind()` 无法表达输入/输出差异。

---

## 3. 表示与不变量

协议无字段。实现必须保证：

- `name()` 非空、单行、在同一 Agent 内唯一；
- `inputKind()`/`outputKind()` 稳定且非 null；
- `start` 成功后才能向下游推送；`consume` 只能在 start 后调用；
- `start` 返回前不得同步调用 downstream；初始数据只能由后续 `consume`/`drain` 触发；
- `consume` 只接受 `inputKind()` 批次；下游只收到 `outputKind()` 批次；
- 一个实例只有一个 downstream；重复 start 返回 `Ok(unit)`，不得替换 downstream；
- 缓冲有界；丢弃有计数；`isHealthy` 可查询；
- `close` 后不再 consume/推送；close 幂等。

---

## 4. 生命周期

```text
构造 → start（目标管线绑定 downstream）→ consume（源管线多次）→ drain → close
```

- `start`：非阻塞；绑定 downstream；重复调用幂等；已关闭 → `Unavailable`；
- `consume`：可多次；未启动/已关闭 → `Unavailable`；输入 kind 不匹配 → panic；
- `drain`：冲刷连接器内部缓冲并等待目标 downstream；取消返回 `Cancelled`；
- `close`：可重复；未 drain 的缓冲丢弃并计数；不关闭 downstream；
- Agent 负责 start/drain/close 一次；源/目标管线不关闭连接器。

---

## 5. 构造契约

协议无构造；实现定义依赖注入。构造器必须校验：

- name 非空；inputKind/outputKind 非 null；
- 缓冲容量 >0（如有）；溢出策略属于固定三种；
- 转换所需的依赖非 null；
- 非法配置 panic 或返回 `InvalidArgument`（由实现选择并在类型文档写明）。

---

## 6. 字段表

无协议字段；实现字段由具体类型定义。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 连接器名 | 无 | `String` | 无 |
| `inputKind` | 源管线 kind | 无 | `TelemetryKind` | 无 |
| `outputKind` | 目标管线 kind | 无 | `TelemetryKind` | 无 |
| `start` | 绑定目标下游 | `Context context, Result<Unit, Error>(TelemetryBatch) downstream` | `Result<Unit, Error>` | `Unavailable`/`InvalidArgument`/`Cancelled`/`Internal` |
| `consume` | 消费源批次 | `Context context, TelemetryBatch batch` | `Result<Unit, Error>` | `Busy`/`Cancelled`/`Unavailable`/`DataCorrupted`/`Internal` |
| `drain` | 冲刷缓冲 | `Context context` | `Result<Unit, Error>` | `Busy`/`Cancelled`/`Unavailable`/`Internal` |
| `close` | 释放资源 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isHealthy` | 是否健康 | 无 | `Bool` | 无 |

说明：

- `start` 对 null context/downstream → panic；重复 start 幂等；
- `consume` 对 null context/batch → panic；kind 不匹配 → panic；
- `consume` 可同步转换后调用 downstream，也可缓冲/聚合后异步调用；
- `drain` 对 null context → panic；无缓冲返回 `Ok(unit)`；
- `close` 幂等；已关闭返回 `Ok(unit)`；不关闭 downstream；
- `isHealthy` 对未启动/已关闭返回 false；运行中由实现根据最近失败定义。

---

## 8. 使用的技术

- 非泛型协议；
- 双 kind 输入/输出；
- 函数类型 downstream；
- 有界缓冲；
- 聚合/路由/复制；
- 幂等关闭。

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

- 引用语义；连接器由 Agent 拥有；源/目标管线只引用；
- `start`/`consume`/`drain`/`close` 可并发调用，但实现必须串行化状态与 downstream 调用；
- 连接器不得被多个 Agent 共享；一个实例只服务一对管线；
- downstream 由目标管线提供；连接器不拥有；
- 内部缓冲/定时器由连接器拥有并关闭；
- `isHealthy` 可并发读取。

---

## 12. 示例与反例

正确：

```xnull
Result<Unit, Error> started = connector.start(context,
    (TelemetryBatch batch) -> metricsPipeline.consume(context, batch))
if started.isErr() { return started }
Result<Unit, Error> consumed = connector.consume(context, traceBatch)
if consumed.isErr() { return consumed }
Result<Unit, Error> drained = connector.drain(context)
connector.close()
```

反例：一个连接器同时接入两条目标管线；源管线 close 连接器；跨 kind 但未在 AgentConfig 声明；
`consume` 接受错误 kind；连接图成环；`start` 替换已有 downstream。

---

## 13. 测试/场景义务

同 kind/跨 kind 连接；input/output kind 校验；start/consume/drain/close 顺序；
重复 start/close；未启动 consume；一个 downstream；缓冲满/三种溢出策略；丢弃计数；
目标下游 `Busy`/`Cancelled`；并发 consume；健康状态；连接图唯一入/出校验；null 参数。

---

## 14. XNull 伪代码

```xnull
protocol Connector {
    String name();
    TelemetryKind inputKind();
    TelemetryKind outputKind();
    Result<Unit, Error> start(Context context,
        Result<Unit, Error>(TelemetryBatch) downstream);
    Result<Unit, Error> consume(Context context, TelemetryBatch batch);
    Result<Unit, Error> drain(Context context);
    Result<Unit, Error> close();
    Bool isHealthy();
}
```
