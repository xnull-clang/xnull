# `Job`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol Job` |
| 包 | `xdk.schedule` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error` |

---

## 1. 定位

调度作业协议：名称 + 可取消执行。

不做：生命周期、句柄、调度时间、重试、持久化。

---

## 2. 设计逻辑

- 非泛型；`run` 返回 `Result<Unit, Error>`。
- `name` 用于标识/日志；非空。
- `run` 必须检查 `Context.isCancelled()`；长时间工作应协作取消。
- 同一 Job 由调度器保证不并发重入（默认）。
- 普通失败用 `Err` 返回；调度器记录 lastError，不崩溃。
- 无 close；实现可共享；线程安全由实现声明。

---

## 3. 表示与不变量

协议无字段。实现必须保证：

- `name` 非空且稳定；
- `run` 不无限阻塞；
- 取消时尽早返回 `Cancelled`；
- 不吞 `OutOfMemory` 等致命错误（X 策略）。

---

## 4. 生命周期

实现决定；无 close；无资源。

---

## 5. 构造契约

协议无构造；由实现定义。

---

## 6. 字段表

无协议字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 作业名 | 无 | `String` | 无 |
| `run` | 执行 | `Context context` | `Result<Unit, Error>` | 作业错误/`Cancelled` |

---

## 8. 使用的技术

- 非泛型协议；
- 协作取消；
- Result 错误。

---

## 9. 需要的支撑

- 语言：protocol、String、Result、Unit；
- 运行时：无；
- 接口：`Context`、`Error`。

---

## 10. 依赖的特性/接口/类

`Context`、`Error`。

---

## 11. 所有权与并发

实现引用；可共享；同一实例可能被调度器串行调用；无资源。

---

## 12. 示例与反例

正确：`String name() { return "cleanup" }`；`run(ctx)` 检查取消。  
反例：name 为空；run 忽略取消；run 抛异常代替 `Err`；同一 Job 期望并发执行。

---

## 13. 测试/场景义务

成功/失败；取消；长时间运行；名称；同一 Job 不重叠；错误记录。

---

## 14. XNull 伪代码

```xnull
protocol Job {
    String name()
    Result<Unit, Error> run(Context context)
}
```
