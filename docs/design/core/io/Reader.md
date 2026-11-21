# `Reader`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol Reader` |
| 包 | `xdk.io` |
| 稳定性 | `stable` |
| 依赖 | `Bytes`、`Context`、`Error` |

---

## 1. 定位

顺序字节读协议：`read` 写入调用方缓冲，返回实际字节数；0 = EOF。

不做：定位（`Seekable`）、写、格式化、行处理（`LineReader`）。

---

## 2. 设计逻辑

- 协议最小面：`read/close/isOpen`。
- `read` 0 明确 EOF；不是错误，也不是“无数据”。
- 短读是正常；循环读取由调用方/`readFully` 处理。
- 阻塞/资源流必须接受 `Context`；内存流不阻塞但仍保留参数。
- 单 reader；非线程安全。

---

## 3. 表示与不变量

协议无字段。实现必须保证：

- `close` 幂等；
- 关闭后 `read` 返回 `Unavailable`；
- 不保留调用方缓冲区引用；
- 读取不修改源（除非协议另有声明）。

---

## 4. 生命周期

- 实现决定；资源流必须 close。
- 内存流 close 是 no-op，`isOpen` 恒 true。

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
| `read` | 读字节 | `Context context, Bytes buffer` | `Result<Int, Error>` | `Io`/`Cancelled`/`Unavailable` |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 非泛型协议；
- 缓冲借用；
- EOF=0；
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

- `buffer` 借用；`read` 不保留。
- 实现持有源/资源；close 释放。
- 单 reader；非线程安全。

---

## 12. 示例与反例

正确：`while read(ctx, buf) > 0 { ... }`。  
反例：把 0 当“暂时无数据”无限重试；关闭后继续读；多任务并发 read。

---

## 13. 测试/场景义务

EOF；短读；关闭后；取消；缓冲不保留；空缓冲；负容量实现拒绝。

---

## 14. XNull 伪代码

```xnull
protocol Reader {
    Result<Int, Error> read(Context context, Bytes buffer);
    Result<Unit, Error> close();
    Bool isOpen();
}
```
