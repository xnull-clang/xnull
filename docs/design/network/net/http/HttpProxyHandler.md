# `HttpProxyHandler`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol HttpProxyHandler` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`HttpProxyExchange`、`Error` |

---

## 1. 定位

HTTP 代理处理入口：处理一次 `HttpProxyExchange`。

不做：路由、认证后端、缓存、TLS 终止。

---

## 2. 设计逻辑

- 单方法 `handle`；返回 `Result<Unit, Error>`。
- Handler 负责 forward/openTunnel/respond 和 close。
- 未响应由服务器生成 502/500；不得重复响应。
- 无状态/有状态由实现决定。

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
| `handle` | 处理代理交换 | `Context context, HttpProxyExchange exchange` | `Result<Unit, Error>` | 业务/IO |

---

## 8. 使用的技术

- 非泛型协议；
- Result。

---

## 9. 需要的支撑

- 语言：protocol、Result；
- 运行时：代理服务器分派；
- 接口：`Context`、`HttpProxyExchange`、`Error`。

---

## 10. 依赖的特性/接口/类

`Context`、`HttpProxyExchange`、`Error`。

---

## 11. 所有权与并发

可并发调用；实现自行同步。

---

## 12. 示例与反例

正确：`handle` 内 `exchange.forward(...)`。  
反例：不响应；重复 respond；不 close。

---

## 13. 测试/场景义务

forward；tunnel；未响应；Err；取消；并发。

---

## 14. XNull 伪代码

```xnull
protocol HttpProxyHandler {
    Result<Unit, Error> handle(Context context, HttpProxyExchange exchange);
}
```
