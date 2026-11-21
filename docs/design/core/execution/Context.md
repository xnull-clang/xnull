# `Context`

| 项 | 值 |
| --- | --- |
| 类型 | `class Context` |
| 包 | 执行层内建 |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

协作取消令牌：根上下文、子上下文、取消查询、取消标记。

不做：线程终止、截止时间、取消原因、上下文值、取消回调、进程信号。

---

## 2. 设计逻辑

- 字段 `_parent: Context?`、`_cancelled: Bool`。
- `background()` 创建独立根上下文，不是全局单例；调用方显式传递。
- `withCancel(parent)` 创建子上下文；父取消后子自动看到取消。
- 子取消不反向影响父。
- `isCancelled` 检查自身及祖先；`cancel` 只标记自身，幂等。
- 取消是协作式的；任务/锁/通道必须主动查询或通过阻塞原语响应。
- 无锁、无 close；运行时保证取消标记的可见性。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_parent` | `Context?` | 父上下文；根为 null |
| `_cancelled` | `Bool` | 自身取消标记 |

不变量：根无父；子有父；取消只从父向子传播；不可重新激活。

---

## 4. 生命周期

`background`/`withCancel` 创建；无 close；可跨任务共享；进程结束时释放。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Context.background()` | 无 | 无 | 无 |
| `Context.withCancel(Context parent)` | parent | 非 null | null → panic |

构造器私有；业务代码不直接 `new Context`。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `background` | 根上下文 | 无 | `Context` | 无 |
| `withCancel` | 派生子上下文 | `Context parent` | `Context` | null → panic |
| `isCancelled` | 是否已取消 | 无 | `Bool` | 无 |
| `cancel` | 标记取消 | 无 | `void` | 无 |

说明：

- `background()` 每次返回新的根；两个根互不影响。
- `withCancel` 不复制父状态；父之后取消仍会影响子。
- `cancel` 已取消时 no-op。
- `isCancelled` 不阻塞、不分配。
- 不支持 `reason()`；取消原因用任务的 `Error` 表达。

---

## 8. 使用的技术

- 父子令牌树；
- 布尔取消标记；
- 运行时可见性保证。

---

## 9. 需要的支撑

- 语言：class、Bool、可空引用；
- 运行时：原子/可见的取消标记；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

引用语义；可跨任务共享；`cancel` 与 `isCancelled` 并发安全；无资源。

---

## 12. 示例与反例

正确：`Context child = Context.withCancel(parent)`；父取消后 `child.isCancelled()` 为 true。  
反例：把 `background()` 当全局单例；子取消后期望父取消；依赖取消立即终止线程。

---

## 13. 测试/场景义务

根上下文；父子传播；子取消隔离；重复 cancel；多任务共享；深层父链；取消后 isCancelled。

---

## 14. XNull 伪代码

```xnull
class Context {
    final Context? _parent
    Bool _cancelled = false

    private Context(Context? parent) {
        _parent = parent
    }

    static Context background() {
        return new Context(null)
    }

    static Context withCancel(Context parent) {
        if parent == null { throw "Context.withCancel: null parent" }
        return new Context(parent)
    }

    Bool isCancelled() {
        if _cancelled { return true }
        if _parent == null { return false }
        Context parent = _parent as Context
        return parent.isCancelled()
    }

    void cancel() {
        _cancelled = true
    }
}
```
