# `TaskHandle`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol TaskHandle` |
| 包 | 执行层内建 |
| 稳定性 | `preview` |
| 依赖 | `Error` |

---

## 1. 定位

非泛型任务句柄协议：完成查询、取消、等待完成、读取失败。用于 `TaskGroup` 持有异构 `Task<T>`。

不做：返回成功值（由 `Task<T>.join` 提供）、消费结果、任务调度。

---

## 2. 设计逻辑

- 协议只有 `isDone`、`cancel`、`awaitDone`、`failure`。
- 不含泛型，避免泛型协议限制；`Task<T>` 实现它。
- `awaitDone` 可被多个等待者调用，不消费结果。
- `failure` 只在完成后调用；`Ok` 返回 null，`Err` 返回错误。
- `cancel` 协作式、幂等。
-  不鼓励用户自定义实现；`Task<T>` 是唯一实现。

---

## 3. 表示与不变量

协议无字段。实现必须保证：

- `isDone` 不阻塞；
- `awaitDone` 完成后立即返回；
- `failure` 在未完成时是合同错误；
- `cancel` 不改变已完成任务的结果；
- 方法可并发调用，`awaitDone` 支持多等待者。

---

## 4. 生命周期

实现决定；任务完成后句柄仍可查询；无 close。

---

## 5. 构造契约

协议无构造。

---

## 6. 字段表

无协议字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `isDone` | 是否完成 | 无 | `Bool` | 无 |
| `cancel` | 请求取消 | 无 | `void` | 无 |
| `awaitDone` | 等待完成 | 无 | `void` | 无 |
| `failure` | 失败值 | 无 | `Error?` | 未完成 → panic |

说明：

- `failure` 返回 null 表示任务成功。
- 取消错误也是 `Error`，`kind() == Cancelled`。
- `TaskGroup.close` 先 `awaitDone` 再 `failure`。
- `awaitDone` 不返回 `Result`；任务错误通过 `failure` 读取。

---

## 8. 使用的技术

- 非泛型协议；
- 任务完成状态；
- 多等待者；
- 错误查询。

---

## 9. 需要的支撑

- 语言：protocol、Bool、void、Error；
- 运行时：任务完成同步；
- 接口：`Error`。

---

## 10. 依赖的特性/接口/类

`Error`。

---

## 11. 所有权与并发

句柄引用语义；`Task<T>` 持有；可共享；`awaitDone` 可多等待者。

---

## 12. 示例与反例

正确：`TaskGroup.close` 遍历 `List<TaskHandle>`，先 await 再 failure。  
反例：未完成调用 `failure`；把 `awaitDone` 当消费；自定义实现返回 null 表示失败。

---

## 13. 测试/场景义务

完成前/后；Ok/Err；多等待者；取消；重复 await；未完成 failure panic；TaskGroup 异构任务。

---

## 14. XNull 伪代码

```xnull
protocol TaskHandle {
    Bool isDone();
    void cancel();
    void awaitDone();
    Error? failure();
}
```
