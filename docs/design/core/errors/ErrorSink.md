# `ErrorSink`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol ErrorSink` |
| 包 | `xdk.errors` |
| 稳定性 | `preview` |
| 依赖 | `Error` |

---

## 1. 定位

显式错误观测出口。只负责把错误写到某处；不改变控制流、不做重试、不做全局注册。

---

## 2. 设计逻辑

- S5 禁止全局错误通知中心/隐式日志；Sink 由调用方显式持有。
- Sink 可能失败；`report` 返回 `Result`，由 `reportTo` 决定是否诊断 sink 失败。
- `close` 幂等；关闭后 `report` 返回 `Unavailable`。
- 默认非线程安全；实现必须声明。

---

## 3. 表示与不变量

`ErrorSink` 是协议，无字段。实现可持有资源/缓冲/容量。

---

## 4. 生命周期

- 由实现决定；资源 sink 必须 `close`。
- `close` 幂等；关闭后 `isOpen=false`，`report` 返回 `Unavailable`。
- `flush` 刷新缓冲；无缓冲可 no-op。

---

## 5. 构造契约

协议无构造；由具体实现定义。

---

## 6. 字段表

无协议字段。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `report` | 观测错误 | `Error error` | `Result<Unit, Error>` | `Io`/`Unavailable` |
| `flush` | 刷新 | 无 | `Result<Unit, Error>` | `Io` |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 非泛型协议；
- Result 失败通道；
- 显式生命周期。

---

## 9. 需要的支撑

- 语言：protocol、class、Result、Bool；
- 运行时：无（具体实现决定）；
- 接口：`Error`。

---

## 10. 依赖的特性/接口/类

`Error`。

---

## 11. 所有权与并发

- Sink 由调用方拥有；`reportTo` 不接管所有权。
- 并发由实现声明；默认非线程安全。

---

## 12. 示例与反例

正确：生产用 `DiagnosticErrorSink`，测试用 `MemoryErrorSink`，自定义实现转发日志/审计。  
反例：全局 `setErrorSink`；sink 失败吞原错误；用 sink 做业务分支。

---

## 13. 测试/场景义务

report/flush/close/isOpen；关闭后 Unavailable；失败路径；并发声明。

---

## 14. XNull 伪代码

```xnull
protocol ErrorSink {
    Result<Unit, Error> report(Error error);
    Result<Unit, Error> flush();
    Result<Unit, Error> close();
    Bool isOpen();
}
```
