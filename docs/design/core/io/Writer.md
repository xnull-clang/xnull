# `Writer`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol Writer` |
| 包 | `xdk.io` |
| 稳定性 | `stable` |
| 依赖 | `Bytes`、`Context`、`Error` |

---

## 1. 定位

顺序字节写协议：`write` 可短写；`writeAll` 写全；`flush` 刷新；`close` 关闭。

不做：定位（`Seekable`）、读、格式化、行处理（`LineWriter`）。

---

## 2. 设计逻辑

- `write` 返回实际写入数；短写不是错误。
- `writeAll` 必须循环到写完或失败。
- `flush` 对无缓冲实现是 no-op。
- 关闭后写返回 `Unavailable`；close 幂等。
- 单 writer；非线程安全。

---

## 3. 表示与不变量

协议无字段。实现保证：

- 不保留调用方数据引用；
- `writeAll` 不静默短写；
- `close` 幂等；
- `flush` 失败返回 `Io`。

---

## 4. 生命周期

- 实现决定；资源流必须 close。
- 内存流 close no-op。

---

## 5. 构造契约

协议无构造；由实现定义。

---

## 6. 字段表

无协议字段。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `write` | 写字节 | `Context context, Bytes data` | `Result<Int, Error>` | `Io`/`Cancelled`/`Unavailable` |
| `writeAll` | 写全 | 同上 | `Result<Unit, Error>` | 同上 |
| `flush` | 刷新 | 无 | `Result<Unit, Error>` | `Io` |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 非泛型协议；
- 短写/写全；
- 缓冲刷新；
- Result/Context。

---

## 9. 需要的支撑

- 语言：protocol、class、Bytes、Int、Bool、Result、Context；
- 运行时：实现决定；
- 接口：`Error`、`Bytes`、`Context`。

---

## 10. 依赖的特性/接口/类

`Bytes`、`Context`、`Error`、`Result`。

---

## 11. 所有权与并发

- `data` 借用；不保留。
- 单 writer；非线程安全。

---

## 12. 示例与反例

正确：`writeAll(ctx, data)`；`flush` 后 close。  
反例：忽略 `write` 短写；关闭后继续写；多任务并发写。

---

## 13. 测试/场景义务

短写；writeAll；flush；close 幂等；关闭后；取消；空数据。

---

## 14. XNull 伪代码

```xnull
protocol Writer {
    Result<Int, Error> write(Context context, Bytes data);
    Result<Unit, Error> writeAll(Context context, Bytes data);
    Result<Unit, Error> flush();
    Result<Unit, Error> close();
    Bool isOpen();
}
```
