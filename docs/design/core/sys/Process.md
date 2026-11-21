# `Process`

| 项 | 值 |
| --- | --- |
| 类型 | `class Process` |
| 包 | `xdk.sys` |
| 稳定性 | `stable` |
| 依赖 | `Signal`、`Duration`、`Context` |

---

## 1. 定位

子进程句柄：id/存活/等待/超时/退出码/信号/关闭。

不做：PTY、stdio 管道（X）、进程组、资源限制。

---

## 2. 设计逻辑

- 字段 `_handle: ProcessHandle`、`_open: Bool`、`_status: Int?`。
- `wait` 阻塞；可重复读取同一退出状态。
- `waitTimeout` 超时返回 `Timeout`，进程继续；不 kill。
- `kill` 发 SIGKILL；`signal` 发指定信号。
- `close` 未终结则 kill + 回收；幂等。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_handle` | `ProcessHandle` | OS 句柄 |
| `_open` | `Bool` | 可用 |
| `_status` | `Int?` | 已等待状态 |

不变量：close 后 open=false；status 缓存不变。

---

## 4. 生命周期

spawn 创建；必须 close；close 幂等。

---

## 5. 构造契约

构造器内部；由 `ProcessBuilder.spawn` 创建。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `id` | 进程 ID | 无 | `Long` | 无 |
| `isAlive` | 是否存活 | 无 | `Bool` | 无 |
| `wait` | 等待 | `Context` | `Result<Int, Error>` | `Unavailable`/`Io`/`Cancelled` |
| `waitTimeout` | 超时等待 | `Context, Duration` | `Result<Int, Error>` | `Timeout`/`Cancelled` |
| `exitCode` | 已有退出码 | 无 | `Int?` | 无 |
| `kill` | SIGKILL | `Context` | `Result<Unit, Error>` | `Unavailable`/`Io` |
| `signal` | 发信号 | `Context, Signal` | `Result<Unit, Error>` | 同上 |
| `close` | 回收 | 无 | `Result<Unit, Error>` | `Io` |
| `isOpen` | 可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- OS 进程句柄；
- wait/waitpid；
- 信号；
- 超时/取消；
- 回收。

---

## 9. 需要的支撑

- 语言：class、Long、Int、Bool、Result、Context；
- 运行时/OS：wait/kill/close；
- 接口：`Signal`、`Duration`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Signal`、`Duration`、`Context`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

持有子进程；close 回收；单任务；非线程安全。

---

## 12. 示例与反例

正确：spawn → wait → close。  
反例：wait 超时后 close 期望进程已退出；重复 close；忽略僵尸回收。

---

## 13. 测试/场景义务

id；存活；wait；超时；kill/signal；close 幂等；退出码缓存；取消。

---

## 14. XNull 伪代码

```xnull
class Process {
    ProcessHandle _handle
    Bool _open
    Int? _status

    Process(ProcessHandle handle) {
        _handle = handle
        _open = true
        _status = null
    }

    Long id() { return processId(_handle) }
    Bool isAlive() { return _open && processAlive(_handle) }
    Int? exitCode() { return _status }

    Result<Int, Error> wait(Context context) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "process closed"))
        }
        if context == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null context"))
        }
        Result<Int, Error> status = waitProcessRaw(_handle, context)
        if status.isErr() { return Err(status.error()) }
        _status = status.value()
        return status
    }

    Result<Int, Error> waitTimeout(Context context, Duration timeout) {
        if timeout == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null timeout"))
        }
        Long deadline = nowMono() + timeout.millis()
        return waitProcessDeadlineRaw(_handle, context, deadline)
    }

    Result<Unit, Error> kill(Context context) {
        return self.signal(context, Signal.Kill)
    }

    Result<Unit, Error> signal(Context context, Signal signal) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "process closed"))
        }
        if context == null || signal == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null argument"))
        }
        return signalProcessRaw(_handle, signalNumber(signal))
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return closeProcessRaw(_handle)
    }

    Bool isOpen() { return _open }
}
```

> `ProcessHandle`、`processId/processAlive/waitProcessRaw/waitProcessDeadlineRaw/signalProcessRaw/closeProcessRaw` 是 OS/运行时进程原语。
