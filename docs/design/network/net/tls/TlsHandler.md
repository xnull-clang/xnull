# `TlsHandler`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol TlsHandler` |
| 包 | `xdk.net.tls` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`TlsStream`、`Error` |

---

## 1. 定位

TLS 服务端连接处理入口。

不做：TCP accept、证书加载、HTTP。

---

## 2. 设计逻辑

- 单方法 `handle`；返回 `Result<Unit, Error>`。
- Handler 拥有 `TlsStream`，必须 close。
- 可并发处理多个连接。

---

## 3. 表示与不变量

协议无字段。

---

## 4. 生命周期

协议无构造。

---

## 5. 构造契约

协议无构造。

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `handle` | 处理连接 | `Context, TlsStream` | `Result<Unit, Error>` | 业务/IO |

---

## 8. 使用的技术

- 非泛型协议。

---

## 9. 需要的支撑

- 语言：protocol、Result；
- 运行时：服务器分派；
- 接口：`Context`、`TlsStream`、`Error`。

---

## 10. 依赖的特性/接口/类

`Context`、`TlsStream`、`Error`。

---

## 11. 所有权与并发

可并发；实现自行同步。

---

## 12. 示例与反例

正确：`handle` 内读写并 close。  
反例：不 close；多 reader；忽略取消。

---

## 13. 测试/场景义务

正常处理；握手失败；关闭；取消；并发。

---

## 14. XNull 伪代码

```xnull
protocol TlsHandler {
    Result<Unit, Error> handle(Context context, TlsStream stream);
}
```
