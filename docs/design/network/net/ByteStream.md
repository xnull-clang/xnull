# `ByteStream`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol ByteStream` |
| 包 | `xdk.net` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Bytes`、`Error` |

---

## 1. 定位

网络层统一字节流协议：TCP/TLS/HTTP 正文/WebSocket 底层都只依赖它。

不做：地址、socket 选项、消息分帧、TLS 握手、HTTP 语义。

---

## 2. 设计逻辑

- 最小面：`read`/`write`/`writeAll`/截止时间/`isOpen`/`close`。
- `read` 把最多 `buffer.length()` 字节写入调用方缓冲，返回实际数；0 = EOF。
- `write` 可短写；`writeAll` 写全或返回错误。
- 截止时间是单调毫秒；过期立即 `Timeout`。
- `close` 幂等；关闭后 I/O `Unavailable`。
- 一个 reader + 一个 writer 可并发；多个 reader/多个 writer 不承诺安全。
- 不暴露 socket 地址；具体流类型提供地址。

---

## 3. 表示与不变量

协议无字段。实现必须保证：

- 不保留调用方缓冲区/数据引用；
- `read` 0 只在 EOF 返回；
- `write` 不静默丢弃；
- `close` 幂等；
- 截止时间与 Context 同时存在时先到者生效。

---

## 4. 生命周期

实现决定；资源流必须 close；内存流 close 可为 no-op。

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
| `read` | 读字节 | `Context context, Bytes buffer` | `Result<Int, Error>` | `Unavailable`/`Network`/`Timeout`/`Cancelled` |
| `write` | 写字节 | `Context context, Bytes data` | `Result<Int, Error>` | 同上 |
| `writeAll` | 写全 | `Context context, Bytes data` | `Result<Unit, Error>` | 同上 |
| `setReadDeadline` | 读截止 | `Long deadlineMonoMillis` | `Result<Unit, Error>` | `InvalidArgument`/`Unavailable` |
| `setWriteDeadline` | 写截止 | `Long deadlineMonoMillis` | `Result<Unit, Error>` | 同上 |
| `isOpen` | 是否打开 | 无 | `Bool` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

---

## 8. 使用的技术

- 非泛型协议；
- 0=EOF；
- 短写 + writeAll；
- 单调截止；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：protocol、Bytes、Int、Long、Bool、Result；
- 运行时：实现决定；
- 接口：`Context`、`Error`、`Bytes`。

---

## 10. 依赖的特性/接口/类

`Context`、`Bytes`、`Error`。

---

## 11. 所有权与并发

`buffer`/`data` 借用；实现不保留；一个 reader + 一个 writer；close 可并发。

---

## 12. 示例与反例

正确：`while read(ctx, buf) > 0 { writeAll(ctx, slice(buf,0,n)) }`。  
反例：把 0 当“暂时无数据”；忽略短写；close 后继续读；多 reader 并发。

---

## 13. 测试/场景义务

EOF；短读/短写；writeAll；截止过期；取消；close 幂等；关闭后；缓冲不保留；并发 reader/writer。

---

## 14. XNull 伪代码

```xnull
protocol ByteStream {
    Result<Int, Error> read(Context context, Bytes buffer);
    Result<Int, Error> write(Context context, Bytes data);
    Result<Unit, Error> writeAll(Context context, Bytes data);
    Result<Unit, Error> setReadDeadline(Long deadlineMonoMillis);
    Result<Unit, Error> setWriteDeadline(Long deadlineMonoMillis);
    Bool isOpen();
    Result<Unit, Error> close();
}
```
