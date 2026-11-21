# `SpanStatus`

| 项 | 值 |
| --- | --- |
| 类型 | `enum SpanStatus` |
| 包 | `xdk.trace` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

span 的终态：Unset、Ok、Error。

不做：错误分类、重试建议、日志级别、指标计数。

---

## 2. 设计逻辑

- `Unset`：未显式设置；不表示失败，也不表示成功。
- `Ok`：调用方显式确认操作成功。
- `Error`：操作失败；通常由 `Span.recordError` 或 `setStatus(SpanStatus.Error, ...)` 设置。
- 状态只影响导出语义，不影响采样、父子关系或 `Span.end()`。
- 状态迁移由 `Span` 执行：`Unset` 可到 `Ok`/`Error`；`Ok` 可升级到 `Error`；`Error` 为终态。
- 枚举无实例方法；值语义。

---

## 3. 表示与不变量

| 成员 | 含义 |
| --- | --- |
| `Unset` | 未设置 |
| `Ok` | 成功 |
| `Error` | 失败 |

不变量：成员固定；不存在 `Cancelled`/`Timeout` 等细分状态；错误细分由 `ErrorKind`/属性承载。

---

## 4. 生命周期

值类型；无 close；无资源。

---

## 5. 构造契约

枚举成员直接使用；不提供整数/字符串隐式转换。

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

无实例方法；导出层按自己的协议映射状态文本。

---

## 8. 使用的技术

- 简单枚举；
- 显式状态优先级。

---

## 9. 需要的支撑

- 语言：enum。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

值语义；无资源；可跨任务共享。

---

## 12. 示例与反例

正确：`span.setStatus(SpanStatus.Ok, "")`；失败时 `span.setStatus(SpanStatus.Error, "timeout")`。  
反例：把 `Unset` 当成功；用 `Ok` 覆盖已设置的 `Error`；把取消一律标成 `Error` 而不保留原因。

---

## 13. 测试/场景义务

每个成员；`Unset` 默认；`Ok`/`Error` 设置；`Ok` 到 `Error` 升级；`Error` 不被覆盖；重复设置；导出映射。

---

## 14. XNull 伪代码

```xnull
enum SpanStatus {
    Unset,
    Ok,
    Error,
}
```
