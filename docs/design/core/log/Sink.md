# `Sink`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol Sink` |
| 包 | `xdk.log` |
| 稳定性 | `preview` |
| 依赖 | `LogRecord`、`Error` |

---

## 1. 定位

日志输出目标协议：写记录/刷新/关闭/可用。

不做：过滤、格式化（由 Formatter 组合）、全局注册。

---

## 2. 设计逻辑

- 最小面：write/flush/close/isOpen。
- write 失败返回 Result；Logger 只诊断，不抛业务错误。
- close 幂等；关闭后 write `Unavailable`。
- 线程安全由实现声明；默认非线程安全。
- 不提供全局 sink。

---

## 3. 表示与不变量

协议无字段。实现保证：

- 不修改 record；
- write 不保留 record 引用；
- close 幂等。

---

## 4. 生命周期

实现决定；资源 sink 必须 close。

---

## 5. 构造契约

协议无构造。

---

## 6. 字段表

无协议字段。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `write` | 写记录 | `LogRecord record` | `Result<Unit, Error>` | `Io`/`Unavailable` |
| `flush` | 刷新 | 无 | `Result<Unit, Error>` | `Io` |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isOpen` | 可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 非泛型协议；
- Result；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：protocol、class、Bool、Result；
- 运行时：实现决定；
- 接口：`LogRecord`、`Error`。

---

## 10. 依赖的特性/接口/类

`LogRecord`、`Error`、`Result`。

---

## 11. 所有权与并发

Sink 由 Logger/调用方持有；并发由实现声明。

---

## 12. 示例与反例

正确：ConsoleSink/MemorySink 实现；自定义 sink 转发。  
反例：全局 sink；write 抛业务异常；close 后再写。

---

## 13. 测试/场景义务

write/flush/close/isOpen；关闭后；失败；并发声明。

---

## 14. XNull 伪代码

```xnull
protocol Sink {
    Result<Unit, Error> write(LogRecord record);
    Result<Unit, Error> flush();
    Result<Unit, Error> close();
    Bool isOpen();
}
```
