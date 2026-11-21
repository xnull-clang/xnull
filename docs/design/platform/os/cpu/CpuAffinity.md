# `CpuAffinity`

| 项 | 值 |
| --- | --- |
| 类型 | `class CpuAffinity` |
| 包 | `xdk.os.cpu` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error`、`CpuTopology` |

---

## 1. 定位

CPU 亲和性控制器：查询/设置当前进程或线程可运行的 CPU 集合。

不做：调度策略、实时优先级、cgroup cpuset、跨进程绑核、性能计数。

---

## 2. 设计逻辑

- 由 `OsHost.cpuAffinity(context)` 返回；持有不透明 `Long` 句柄。
- `get` 返回当前集合；`set` 设置集合；`reset` 恢复默认。
- 集合必须非空、id 在 OS 可见范围、无重复；非法返回 `InvalidArgument`。
- 影响范围由实现声明（进程或当前线程）；跨平台语义不同。
- 写操作可能需权限；`PermissionDenied` 不重试、不提权。
- `close` 幂等；关闭后方法 `Unavailable`。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_handle` | `Long` | final | >0；不透明 |
| `_open` | `Bool` | 内部 | 是否可用 |

不变量：handle>0；close 后 open=false；close 幂等。

---

## 4. 生命周期

由宿主创建；调用方 `close()`；close 幂等；无 `deinit` 依赖。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `CpuAffinity(Long handle)` | handle | >0 | ≤0 → panic |

构造器主要供宿主/测试使用；业务代码通过 `OsHost.cpuAffinity` 获取。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `get` | 当前亲和性 | `Context context` | `Result<List<Int>, Error>` | `Unsupported`/`PermissionDenied`/`Cancelled` |
| `set` | 设置集合 | `Context context, List<Int> cpuIds` | `Result<Unit, Error>` | 同上 + `InvalidArgument` |
| `reset` | 恢复默认 | `Context context` | `Result<Unit, Error>` | 同上 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 不透明句柄；
- OS 亲和性原语；
- Context/Result；
- 幂等关闭。

---

## 9. 需要的支撑

- 语言：class、Long、List、Bool、Result；
- 运行时/适配器：`cpuAffinityGetRaw`/`cpuAffinitySetRaw`/`cpuAffinityResetRaw`/`cpuAffinityCloseRaw`；
- 接口：`Context`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`Error`、`CpuTopology`、`OsHost`、`unavailableError`。

---

## 11. 所有权与并发

引用语义；控制器由调用方持有；`get/set/reset` 可并发但 OS 可能串行化；`close` 可并发；无资源泄漏。
相等：引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：`affinity.set(ctx, [0, 1])` 绑定到前两个 CPU；`affinity.reset(ctx)` 恢复。  
反例：空集合；id 越界；close 后继续 set；期望跨平台完全一致；无权限时重试。

---

## 13. 测试/场景义务

get/set/reset；空/重复/越界集合；无权限；取消；close 幂等；关闭后 `Unavailable`；
容器 cpuset；多线程语义。

---

## 14. XNull 伪代码

```xnull
class CpuAffinity {
    final Long _handle
    Bool _open

    CpuAffinity(Long handle) {
        if handle <= 0 { throw "CpuAffinity: invalid handle" }
        _handle = handle
        _open = true
    }

    Result<List<Int>, Error> get(Context context) {
        if context == null { throw "CpuAffinity.get: null context" }
        if !_open { return Err(unavailableError("cpu affinity")) }
        return cpuAffinityGetRaw(context, _handle)
    }

    Result<Unit, Error> set(Context context, List<Int> cpuIds) {
        if context == null { throw "CpuAffinity.set: null context" }
        if cpuIds == null || cpuIds.length() == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "empty cpu set"))
        }
        if !_open { return Err(unavailableError("cpu affinity")) }
        return cpuAffinitySetRaw(context, _handle, cpuIds.copy())
    }

    Result<Unit, Error> reset(Context context) {
        if context == null { throw "CpuAffinity.reset: null context" }
        if !_open { return Err(unavailableError("cpu affinity")) }
        return cpuAffinityResetRaw(context, _handle)
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return cpuAffinityCloseRaw(_handle)
    }

    Bool isOpen() { return _open }
}
```
