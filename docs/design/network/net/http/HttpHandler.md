# `HttpHandler`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol HttpHandler` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`HttpExchange`、`Error` |

---

## 1. 定位

HTTP 服务端处理入口：处理一次 `HttpExchange`。

不做：路由、中间件、依赖注入、自动响应。

---

## 2. 设计逻辑

- 单方法 `handle`；返回 `Result<Unit, Error>`。
- Handler 负责调用 `respond` 或 `upgrade`；未响应由服务器生成 500。
- Handler 返回 `Err` 且未响应时，服务器生成 500；不得重复响应。
- Handler 必须关闭请求 body（或 `exchange.close()`）。
- 无状态/有状态由实现决定；并发由服务器决定。

---

## 3. 表示与不变量

协议无字段。

---

## 4. 生命周期

协议无构造；实现决定。

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
| `handle` | 处理交换 | `Context context, HttpExchange exchange` | `Result<Unit, Error>` | 业务/IO |

---

## 8. 使用的技术

- 非泛型协议；
- Result。

---

## 9. 需要的支撑

- 语言：protocol、Result；
- 运行时：服务器分派；
- 接口：`Context`、`HttpExchange`、`Error`。

---

## 10. 依赖的特性/接口/类

`Context`、`HttpExchange`、`Error`。

---

## 11. 所有权与并发

实现可被并发调用；不得共享可变状态而不加同步。

---

## 12. 示例与反例

正确：`handle` 内 `exchange.respond(...)`。  
反例：不响应直接返回；响应两次；忽略请求 body。

---

## 13. 测试/场景义务

正常响应；未响应；Err；upgrade；取消；并发。

---

## 14. XNull 伪代码

```xnull
protocol HttpHandler {
    Result<Unit, Error> handle(Context context, HttpExchange exchange);
}
```
