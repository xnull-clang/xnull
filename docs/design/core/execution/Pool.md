# `Pool<T>`

| 项 | 值 |
| --- | --- |
| 类型 | `class Pool<T>` |
| 包 | 执行层内建 |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error`、`RuntimeMonitor` |

---

## 1. 定位

通用对象池：限制同时借出的对象数，复用空闲对象，关闭时销毁空闲对象；等待可取消。

不做：连接协议、健康检查、空闲超时、后台清理线程、跨进程池、公平性保证。

---

## 2. 设计逻辑

- 字段 `_capacity`、`_idle: List<T>`、`_inUse`、`_creating`、`_closed`、`_monitor`、
  `_factory`、`_destroy`。
- `acquire` 优先取空闲对象；没有空闲且 `inUse + creating < capacity` 时调用工厂创建；
  否则等待。
- 工厂在锁外调用，避免阻塞其他借出；用 `_creating` 预留容量。
- `release` 归还；关闭后直接销毁；`_inUse` 减一。
- `close` 标记关闭，销毁当前空闲对象；已借出对象在 release 时销毁；不等待借出归还。
- 取消：等待中取消返回 `Cancelled`，不改变计数。
- `factory`/`destroy` 必须非 null；`destroy` 不得抛出可恢复错误（返回 void）。
- 不跟踪对象归属；调用方只能 release 自己 acquire 的对象。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_capacity` | `Int` | >0 |
| `_idle` | `List<T>` | 空闲对象 |
| `_inUse` | `Int` | 已借出数 |
| `_creating` | `Int` | 正在创建数 |
| `_closed` | `Bool` | 是否关闭 |
| `_monitor` | `RuntimeMonitor` | 等待/通知 |
| `_factory` | `Result<T, Error>()` | 创建对象 |
| `_destroy` | `void(T)` | 销毁对象 |

不变量：capacity > 0；`inUse >= 0`；`inUse + creating <= capacity`；`idle.length <= capacity`；
closed 后 acquire 返回 `Unavailable`。

---

## 4. 生命周期

构造创建空池；`acquire/release` 使用；`close` 销毁空闲；已借出对象在 release 时销毁；
无 `deinit` 依赖。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Pool(Int capacity, Result<T,Error>() factory, void(T) destroy)` | capacity/factory/destroy | capacity >0；函数非 null | ≤0/null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `acquire` | 借出对象 | `Context context` | `Result<T, Error>` | `Cancelled`/`Unavailable`/工厂错误；null → panic |
| `release` | 归还对象 | `T value` | `Bool` | 无 |
| `close` | 关闭池 | 无 | `void` | 无 |
| `isClosed` | 是否关闭 | 无 | `Bool` | 无 |
| `capacity` | 容量 | 无 | `Int` | 无 |
| `idleCount` | 空闲数 | 无 | `Int` | 无 |
| `inUseCount` | 借出数 | 无 | `Int` | 无 |

说明：

- `acquire` 工厂失败返回工厂错误；`_creating` 回退，唤醒等待者。
- `release` 在 closed 时销毁并返回 false；正常归还返回 true。
- `close` 幂等；不等待借出对象；`destroy` 在调用线程执行。
- `idleCount`/`inUseCount` 是瞬时快照。

---

## 8. 使用的技术

- 对象池；
- 容量预留；
- 运行时监视器；
- 取消感知等待；
- 关闭清理。

---

## 9. 需要的支撑

- 语言：class、泛型、Int、Bool、Result、函数类型、闭包；
- 运行时：`RuntimeMonitor.enter/exit/wait(Context)/notifyAll`；
- 接口：`Context`、`Error`、`cancelledError`、`unavailableError`。

---

## 10. 依赖的特性/接口/类

`Context`、`Error`、`RuntimeMonitor`、`cancelledError`、`unavailableError`。

---

## 11. 所有权与并发

引用语义；线程安全；对象所有权从池转移给调用方，release 归还；close 可并发；无全局池。
相等：引用身份；不推荐作为 `Map` 键。

---

## 12. 示例与反例

正确：

```xnull
Pool<Buffer> pool = new Pool<Buffer>(16,
    () -> { return Buffer.allocate(4096) },
    (Buffer buffer) -> { buffer.release() })
Result<Buffer, Error> buffer = pool.acquire(ctx)
pool.release(buffer.value())
pool.close()
```

反例：release 非本池对象；close 后继续 acquire；工厂在锁内做长 I/O；忽略 Cancelled；
依赖池做连接健康检查。

---

## 13. 测试/场景义务

容量 1/N；空闲复用；创建失败；等待/取消；close 销毁空闲；借出后 close；release 销毁；
计数；多任务竞争；工厂/销毁异常路径；重复 close。

---

## 14. XNull 伪代码

```xnull
class Pool<T> {
    final Int _capacity
    List<T> _idle = []
    Int _inUse = 0
    Int _creating = 0
    Bool _closed = false
    final RuntimeMonitor _monitor
    final Result<T, Error>() _factory
    final void(T) _destroy

    Pool(Int capacity, Result<T, Error>() factory, void(T) destroy) {
        if capacity <= 0 { throw "Pool: capacity <= 0" }
        if factory == null || destroy == null { throw "Pool: null function" }
        _capacity = capacity
        _monitor = new RuntimeMonitor()
        _factory = factory
        _destroy = destroy
    }

    Result<T, Error> acquire(Context context) {
        if context == null { throw "Pool.acquire: null context" }
        _monitor.enter()
        while true {
            if _closed {
                _monitor.exit()
                return Err(unavailableError("pool acquire"))
            }
            if context.isCancelled() {
                _monitor.exit()
                return Err(cancelledError("pool acquire"))
            }
            if _idle.length() > 0 {
                T value = _idle.remove(_idle.length() - 1)
                _inUse = _inUse + 1
                _monitor.exit()
                return Ok(value)
            }
            if _inUse + _creating < _capacity {
                _creating = _creating + 1
                _monitor.exit()
                Result<T, Error> created = _factory()
                _monitor.enter()
                _creating = _creating - 1
                if created.isErr() {
                    _monitor.notifyAll()
                    _monitor.exit()
                    return Err(created.error())
                }
                if _closed {
                    _monitor.exit()
                    _destroy(created.value())
                    return Err(unavailableError("pool acquire"))
                }
                _inUse = _inUse + 1
                _monitor.notifyAll()
                _monitor.exit()
                return Ok(created.value())
            }
            Bool woke = _monitor.wait(context)
            if !woke {
                _monitor.exit()
                return Err(cancelledError("pool acquire"))
            }
        }
    }

    Bool release(T value) {
        _monitor.enter()
        if _inUse <= 0 {
            _monitor.exit()
            return false
        }
        _inUse = _inUse - 1
        if _closed {
            _monitor.exit()
            _destroy(value)
            return false
        }
        _idle.push(value)
        _monitor.notifyAll()
        _monitor.exit()
        return true
    }

    void close() {
        _monitor.enter()
        if _closed {
            _monitor.exit()
            return
        }
        _closed = true
        List<T> idle = _idle
        _idle = []
        _monitor.notifyAll()
        _monitor.exit()
        Int index = 0
        while index < idle.length() {
            _destroy(idle.get(index))
            index = index + 1
        }
    }

    Bool isClosed() {
        _monitor.enter()
        Bool result = _closed
        _monitor.exit()
        return result
    }

    Int capacity() { return _capacity }

    Int idleCount() {
        _monitor.enter()
        Int result = _idle.length()
        _monitor.exit()
        return result
    }

    Int inUseCount() {
        _monitor.enter()
        Int result = _inUse
        _monitor.exit()
        return result
    }
}
```
