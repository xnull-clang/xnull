# `Fallback`

| 项 | 值 |
| --- | --- |
| 类型 | `class Fallback` |
| 包 | `xdk.resilience` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error` |

---

## 1. 定位

主备降级：主操作失败且非取消时执行备用操作；支持自定义降级条件。

不做：重试、熔断、缓存降级、错误聚合、异步降级、全局降级注册表。

---

## 2. 设计逻辑

- 无状态；构造器私有。
- `execute` 在 primary 返回错误且不是 `Cancelled` 时调用 fallback。
- `executeIf` 先检查 `shouldFallback`，再决定是否降级；取消仍然不降级。
- fallback 接收主错误，可据此选择备用值/错误。
- 返回 fallback 的结果；若 fallback 也失败，返回 fallback 错误，主错误不自动聚合（X）。
- 无 sleep/调度；可取消由调用方在闭包内处理。
- 线程安全；无 close。

---

## 3. 表示与不变量

无实例字段。

不变量：primary/fallback 非 null；取消不触发降级；返回值只来自 primary 或 fallback 之一。

---

## 4. 生命周期

静态命名空间；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Fallback()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `execute<T>` | 主备降级 | `Context, Result<T,Error>() primary, Result<T,Error>(Error) fallback` | `Result<T, Error>` | `Cancelled`/primary/fallback 错误 |
| `executeIf<T>` | 条件降级 | `Context, Result<T,Error>() primary, Result<T,Error>(Error) fallback, Bool(Error) shouldFallback` | `Result<T, Error>` | 同上 |

说明：

- 上下文已取消时直接返回 `Cancelled`，不调用 primary/fallback。
- primary 成功时不调用 fallback。
- primary 返回 `Cancelled` 时直接返回，不调用 fallback。
- `shouldFallback` 返回 false 时保留 primary 错误。
- fallback 自身返回 `Cancelled` 时原样返回。
- `execute` 等价于“非取消即降级”。

---

## 8. 使用的技术

- 函数组合；
- 取消感知；
- 错误短路；
- 显式降级条件。

---

## 9. 需要的支撑

- 语言：class、Bool、Result、泛型方法、函数类型；
- 运行时：无；
- 接口：`Context`、`Error`、`isCancellation`、`cancelledError`。

---

## 10. 依赖的特性/接口/类

`Context`、`Error`、`isCancellation`、`cancelledError`。

---

## 11. 所有权与并发

无状态；可并发；闭包由调用方保证线程安全；无资源。

---

## 12. 示例与反例

正确：`Fallback.execute(ctx, () -> remote(), (Error e) -> local())`。  
反例：取消后调用 fallback；fallback 无限递归；用 fallback 隐藏所有错误；忽略 fallback 失败。

---

## 13. 测试/场景义务

primary 成功；primary 非取消失败；primary 取消；`executeIf` true/false；fallback 成功/失败；fallback 取消；null 参数；嵌套降级。

---

## 14. XNull 伪代码

```xnull
class Fallback {
    private Fallback() {
    }

    static Result<T, Error> execute<T>(Context context, Result<T, Error>() primary,
                                       Result<T, Error>(Error) fallback) {
        if context == null || primary == null || fallback == null {
            throw "Fallback.execute: null argument"
        }
        if context.isCancelled() {
            return Err(cancelledError("fallback execute"))
        }
        Result<T, Error> result = primary()
        if result.isOk() { return result }
        Error error = result.error()
        if isCancellation(error) { return result }
        if context.isCancelled() {
            return Err(cancelledError("fallback execute"))
        }
        return fallback(error)
    }

    static Result<T, Error> executeIf<T>(Context context, Result<T, Error>() primary,
                                         Result<T, Error>(Error) fallback,
                                         Bool(Error) shouldFallback) {
        if context == null || primary == null || fallback == null {
            throw "Fallback.executeIf: null argument"
        }
        if shouldFallback == null {
            throw "Fallback.executeIf: null predicate"
        }
        if context.isCancelled() {
            return Err(cancelledError("fallback executeIf"))
        }
        Result<T, Error> result = primary()
        if result.isOk() { return result }
        Error error = result.error()
        if isCancellation(error) { return result }
        if context.isCancelled() {
            return Err(cancelledError("fallback executeIf"))
        }
        if !shouldFallback(error) { return result }
        return fallback(error)
    }
}
```
