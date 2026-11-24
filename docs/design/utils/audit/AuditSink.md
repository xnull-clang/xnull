# `AuditSink`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol AuditSink` |
| 包 | `xdk.audit` |
| 稳定性 | `preview` |
| 依赖 | `AuditEvent`、`Error` |

---

## 1. 定位

审计输出协议：写事件、刷新、关闭、可用状态。

不做：格式化、重试、异步队列、文件轮转、远程传输、批量 API、全局注册。

---

## 2. 设计逻辑

- 非泛型协议；最小面 `write`/`flush`/`close`/`isOpen`。
- `write`/`flush` 用 `Result` 表达失败；`close` 返回 `void`，必须幂等且不抛。
- `write` 不修改事件；事件不可变，sink 可保留引用，但应在 `write` 内完成序列化或复制。
- `close` 是终态；关闭后 `isOpen` 为 false，`write`/`flush` 返回 `Unavailable`。
- `close` 不能报告失败；需要错误报告时先 `flush`；`AuditLogger.close` 按此顺序调用。
- 协议不要求线程安全；`AuditLogger` 串行化调用；共享 sink 由实现自行同步。
- 无全局 sink、全局注册表或隐式默认 sink。

---

## 3. 表示与不变量

协议无字段。实现保证：

- `write`/`flush` 用返回值表达 I/O 失败，不用异常；
- `write` 不修改传入事件；
- `close` 幂等、非抛出；
- `isOpen` 与生命周期一致：构造后为 true，`close` 后为 false；
- 关闭后不可重新打开。

---

## 4. 生命周期

实现创建后为 open；可 `write`/`flush`；`close` 后为 closed。

`close` 幂等；重复 `close` 无副作用。资源型 sink（文件、网络、进程）必须在 `close` 释放；调用方或 `AuditLogger` 应在 `close` 前 `flush`，以保留可报告的错误。

---

## 5. 构造契约

协议无构造。实现类提供构造器，并在构造完成后处于 open；构造失败由实现决定，协议不规定。

---

## 6. 字段表

无协议字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `write` | 写事件 | `AuditEvent event` | `Result<Unit, Error>` | `Io`/`Unavailable`/`InvalidArgument` |
| `flush` | 刷新缓冲 | 无 | `Result<Unit, Error>` | `Io`/`Unavailable` |
| `close` | 关闭 | 无 | `void` | 无；契约要求不抛 |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |

说明：

- `write` 成功后返回 `Ok(unit)`；失败时不得静默丢弃事件。
- `write` 在关闭后返回 `Unavailable`；不要求检查 `isOpen`，实现应直接拒绝。
- `write` 失败不自动关闭 sink；调用方决定重试、告警或关闭。
- `flush` 对无缓冲 sink 可以是 no-op，返回 `Ok(unit)`；关闭后返回 `Unavailable`。
- `close` 第二次调用无副作用；即使之前的 `write`/`flush` 失败，也必须释放资源。
- `close` 的失败无法通过返回值报告；实现应在 `close` 前尽量完成 `flush`，或由调用方先 `flush`。
- sink 内部不做重试、不排队、不采样；这些属于上层策略。

---

## 8. 使用的技术

- 非泛型协议；
- `Result` 错误传播；
- 幂等关闭；
- 显式生命周期。

---

## 9. 需要的支撑

- 语言：protocol、class、Bool、Result、Unit、void；
- 运行时：由实现决定（文件/网络/内存）；
- 接口：`AuditEvent`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`AuditEvent`、`Error`、`Result`、`Unit`、`ErrorKind`。

---

## 11. 所有权与并发

实现拥有底层资源；调用方或 `AuditLogger` 持有 sink 引用并负责关闭。

协议不承诺线程安全。`AuditLogger` 在独立 sink monitor 内串行化 `write`/`flush`/`close`，状态 monitor 不跨 sink 调用；一个 sink 被一个 logger 独占时无需额外同步；被多个 logger 或调用方直接共享时，实现必须自行同步。

禁止 sink 回调持有它的 logger（`RuntimeMonitor` 不可重入）；回调应通过新任务或外部队列完成。

---

## 12. 示例与反例

正确：内存 sink 追加事件并返回 `Ok(unit)`；文件 sink 写入一行后由 `flush` 落盘；`close` 释放文件句柄。  
反例：磁盘满时抛异常而不是返回 `Err`；关闭后 `write` 返回 `Ok(unit)`；重复 `close` 抛错；全局单例 sink；修改传入事件；异步入队后立即返回成功却不声明持久性。

---

## 13. 测试/场景义务

`write`/`flush`/`close`/`isOpen`；关闭后 `write`/`flush`；重复 `close`；写入失败传播；事件不被修改；无缓冲 sink 的 `flush`；并发声明；资源释放；关闭后不可重新打开。

---

## 14. XNull 伪代码

```xnull
protocol AuditSink {
    Result<Unit, Error> write(AuditEvent event);
    Result<Unit, Error> flush();
    void close();
    Bool isOpen();
}
```
