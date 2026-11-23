# `RuntimeMonitor`

| 项 | 值 |
| --- | --- |
| 类型 | `class RuntimeMonitor` |
| 包 | `xdk.runtime` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`runtime_raw.xfb` 的 monitor 原语 |

---

## 1. 定位

轻量条件等待/通知原语：进入/退出监视区、等待一次通知、可取消等待、唤醒全部等待者、幂等关闭。

不做：线程创建/终止、优先级、公平锁、超时参数、读写锁、可重入锁、裸句柄暴露。

---

## 2. 设计逻辑

- 构造时创建不透明 monitor 句柄；句柄不出包。
- `enter`/`exit` 保护调用方条件；`wait` 等待一次通知，可能虚假唤醒，调用方必须循环重查条件。
- `waitContext(Context)` 返回 `true` 表示收到通知或已关闭，`false` 表示 `Context` 已取消。
- `notifyAll` 唤醒所有当前等待者；不保证之后进入的等待者被唤醒。
- `close` 幂等；关闭后唤醒所有等待者，后续 `wait` 立即返回。
- 关闭后 `enter`/`exit` 仍可调用，但不再保证互斥。
- 不可重入：同一任务已 `enter` 后再次 `enter` 会阻塞/死锁。
- 无超时参数；超时由调用方 `Context` 或外部调度实现。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_handle` | `Long` | 不透明 monitor 句柄，仅内部使用 |

不变量：构造后句柄有效；关闭只从 false 变 true；关闭幂等。

---

## 4. 生命周期

构造 → enter/exit/wait/notifyAll → close；无资源泄漏；close 后对象可安全丢弃。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `RuntimeMonitor()` | 无 | 新建 monitor | 无 |

---

## 6. 字段表

见 §3；字段私有，不暴露裸句柄。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `enter` | 进入监视区 | 无 | `void` | 无 |
| `exit` | 退出监视区 | 无 | `void` | 无 |
| `wait` | 等待一次通知 | 无 | `void` | 无 |
| `waitContext` | 可取消等待 | `Context context` | `Bool` | null context → panic |
| `notifyAll` | 唤醒全部等待者 | 无 | `void` | 无 |
| `close` | 幂等关闭 | 无 | `void` | 无 |
| `isClosed` | 是否关闭 | 无 | `Bool` | 无 |

说明：

- `waitContext`：`true` = 通知/关闭；`false` = Context 取消。
- `close` 后 `wait`/`waitContext` 立即返回；`enter`/`exit` 不再保证互斥。
- `notify` 是 `notifyAll` 的兼容别名，语义相同。

---

## 8. 使用的技术

- 运行时 monitor FFI；
- 不透明句柄；
- 条件等待/通知。

---

## 9. 需要的支撑

- 语言：class、Bool、Long、Context；
- 运行时：`monitorNewRaw`、`monitorEnterRaw`、`monitorExitRaw`、`monitorWaitRaw`、`monitorWaitContextRaw`、`monitorNotifyAllRaw`、`monitorCloseRaw`、`monitorClosedRaw`。

---

## 10. 依赖的特性/接口/类

`Context`；monitor 原语。无其他 XDK 包依赖。

---

## 11. 所有权与并发

引用语义；不可重入；可跨任务共享；等待者由运行时调度；非线程安全的是调用方条件本身，monitor 只负责等待/通知。

---

## 12. 示例与反例

正确：

```xnull
RuntimeMonitor monitor = new RuntimeMonitor()
monitor.enter()
// 修改受保护状态
monitor.notifyAll()
monitor.exit()
```

可取消等待：

```xnull
monitor.enter()
while !ready && !context.isCancelled() {
    if !monitor.waitContext(context) { break }
}
monitor.exit()
```

反例：把 `wait` 当一次性谓词；同一任务重复 `enter`；close 后仍假设互斥；等待返回后不重查条件。

---

## 13. 测试/场景义务

enter/exit；close 幂等与 isClosed；close 后等待立即返回；已取消 Context 返回 false；另一任务 notifyAll 后返回 true；不可重入/超时由调用方测试覆盖。
