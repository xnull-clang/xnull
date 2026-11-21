# `ApiHandler`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol ApiHandler` |
| 包 | `xdk.api` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`ApiContext`、`Error` |

---

## 1. 定位

API 业务处理器入口：接收一次请求的 `ApiContext`，读取请求并产生响应。

不做：路由匹配、认证、限流、CORS、参数绑定、模板渲染、ORM、依赖注入。

---

## 2. 设计逻辑

- 单方法 `handle`，固定 `ApiContext`，不使用泛型协议。
- 处理器负责调用 `respondJson`/`respondText`/`respondBytes`/`respondEmpty`/`respondProblem`/`openSse` 之一。
- 处理器返回 `Ok(unit)` 但未响应时，`ApiServer` 生成 500 ProblemDetails。
- 处理器返回 `Err` 且未响应时，`ApiServer` 按 `ErrorKind` 映射状态。
- 处理器返回 `Err` 但已响应时，错误只作为诊断，不产生第二个响应。
- 打开 SSE 后必须 `close`；`ApiServer` 会在处理器返回后调用 `finishSse` 兜底。
- 处理器可以调用中间件链中的 `next` 吗：不可以；`next` 只属于 `ApiMiddleware`。
- 处理器可被并发调用；不得依赖请求间共享可变状态而不加同步。
- 无 close；处理器实例生命周期由调用方管理。

---

## 3. 表示与不变量

协议无字段。实现必须保证：

- 每个请求最多一次响应；
- 不在响应后继续写；
- 不保留 `ApiContext` 超出请求生命周期；
- 读取 body 时使用传入的 `Context`；
- 关闭自己创建的流/资源；
- 不把密码/令牌写入响应或日志。

---

## 4. 生命周期

协议无构造；由实现定义。处理器通常长期存活、并发复用；请求级状态放在 `ApiContext`。

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
| `handle` | 处理请求 | `Context context, ApiContext exchange` | `Result<Unit, Error>` | 业务/IO/取消 |

说明：

- `exchange` 非 null；null 是合同错误。
- `context` 用于 body/SSE/下游调用取消。
- 成功响应后返回 `Ok(unit)`；业务失败返回 `Err`，由服务器映射。
- 响应状态 4xx/5xx 仍通过 `respond*` 表达，不通过 `Err` 表达。
- 需要早退时调用 `exchange.close()`；服务器也会关闭。

---

## 8. 使用的技术

- 非泛型协议；
- 上下文对象；
- Result；
- 显式响应；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：protocol、Result；
- 运行时：无；
- 接口：`Context`、`ApiContext`、`Error`。

---

## 10. 依赖的特性/接口/类

`Context`、`ApiContext`、`Error`、`ErrorKind`。

---

## 11. 所有权与并发

协议引用；实现可被多请求并发调用；`ApiContext` 只在当前请求内有效；无资源句柄；无取消回调。

---

## 12. 示例与反例

正确：

```text
Result<Unit, Error> handle(Context context, ApiContext exchange) {
    JsonValue body = exchange.bodyJson(context).value()
    return exchange.respondJson(context, body)
}
```

反例：

- 只返回 `Ok(unit)` 不响应；
- 响应两次；
- 用 `Err` 表达 404；
- 在另一个任务中长期持有 `ApiContext`；
- 打开 SSE 后不关闭；
- 把内部异常堆栈写入 `detail`。

---

## 13. 测试/场景义务

正常 JSON 响应；文本/空响应；ProblemDetails；未响应；Err 映射；响应后 Err；取消；HEAD；SSE 打开/关闭；并发调用；body 读取失败。

---

## 14. XNull 伪代码

> 非可执行设计伪代码。

```xnull
protocol ApiHandler {
    Result<Unit, Error> handle(Context context, ApiContext exchange);
}
```
