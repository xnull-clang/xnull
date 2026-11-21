# `ApiMiddleware`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol ApiMiddleware` |
| 包 | `xdk.api` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`ApiContext`、`ApiHandler`、`Error` |

---

## 1. 定位

可组合 API 中间件：在处理器前后执行逻辑，或短路请求并直接响应。

不做：路由匹配、认证/限流内建阶段、依赖注入、反射、异步回调注册。

---

## 2. 设计逻辑

- 单方法 `handle`，显式 `next`；非泛型协议。
- 必须先决定是否继续：调用 `next.handle(context, exchange)` 至多一次。
- 短路时可以响应并返回 `Ok(unit)`；也可以返回 `Err` 交给服务器映射。
- 已响应后不得再调用 `next`；调用 `next` 后不得再次响应（除非 `next` 未响应且返回 Err）。
- 中间件列表“先添加者在外层”；`ApiOptions.middleware` 最外层，其次是路由器/路由中间件。全局中间件在路由匹配前执行，`ApiContext.route()` 可能为 null；路由器/路由中间件在匹配与安全阶段之后执行。
- 中间件可在调用 `next` 前设置响应头、状态、认证属性、限流键等。
- 调用 `next` 后只能观察结果；响应已写出，不能再改状态/头。
- 中间件可被多请求并发调用；不得共享可变状态而不加同步。
- 无 close；实例由调用方管理。

---

## 3. 表示与不变量

协议无字段。实现必须保证：

- `next` 非 null；
- 每个请求最多调用 `next` 一次；
- 短路响应与 `next` 互斥；
- 不吞掉 `Err` 而返回成功，除非已生成等价响应；
- 不保留 `ApiContext` 超出请求生命周期；
- 记录耗时/日志时不写入敏感头或 body。

---

## 4. 生命周期

协议无构造；实现通常长期存活、并发复用；请求级状态放在 `ApiContext` 属性或局部变量。

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
| `handle` | 执行中间件 | `Context context, ApiContext exchange, ApiHandler next` | `Result<Unit, Error>` | 业务/IO/取消 |

说明：

- `context`/`exchange`/`next` 非 null；null 是合同错误。
- 短路：直接调用 `exchange.respond*` 并返回 `Ok(unit)`。
- 继续：`return next.handle(context, exchange)`。
- 前后逻辑：在 `next` 前设置请求级属性/头；在 `next` 后读取 `exchange.isResponded()`/状态做日志。
- 认证/限流不应通过普通中间件绕过内建阶段；内建阶段在路由中间件之前执行。全局中间件是应用信任边界内的代码，若短路响应，认证/限流不会执行，需自行保证安全。
- 取消：`context` 取消时返回 `Cancelled` 或让 `next` 处理。

---

## 8. 使用的技术

- 非泛型协议；
- 显式续延；
- 短路；
- 中间件链；
- Result 传播。

---

## 9. 需要的支撑

- 语言：protocol、Result；
- 运行时：无；
- 接口：`Context`、`ApiContext`、`ApiHandler`、`Error`。

---

## 10. 依赖的特性/接口/类

`Context`、`ApiContext`、`ApiHandler`、`Error`、`ErrorKind`。

---

## 11. 所有权与并发

协议引用；实现可被并发调用；`next` 是本次请求的续延，不得跨请求保存；无资源；无取消回调。

---

## 12. 示例与反例

正确：

```text
Result<Unit, Error> handle(Context context, ApiContext exchange, ApiHandler next) {
    exchange.setHeader("X-Request-Start", str(nowMono()))
    return next.handle(context, exchange)
}
```

反例：

- 调用 `next` 两次；
- 先 `respondJson` 再 `next`；
- 吞掉 `next` 的 `Err` 并返回 `Ok`；
- 在中间件里把 `ApiContext` 存入全局 Map；
- 在 `next` 返回后修改响应头；
- 用中间件替代认证阶段并信任客户端头。

---

## 13. 测试/场景义务

顺序/嵌套；短路响应；短路 Err；`next` 只调用一次；前后头设置；认证失败不进入路由中间件；并发复用；取消；日志不泄露敏感信息。

---

## 14. XNull 伪代码

> 非可执行设计伪代码。

```xnull
protocol ApiMiddleware {
    Result<Unit, Error> handle(Context context, ApiContext exchange, ApiHandler next);
}
```
