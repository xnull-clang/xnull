# `Process`

| 项 | 值 |
| --- | --- |
| 类型 | `class Process` |
| 包 | `xdk.sys` |
| 稳定性 | `stable` |
| 依赖 | `Signal`、`Duration`、`Context` |

---

## 1. 定位

子进程句柄：id/group/存活/等待/超时/退出码/信号/进程组/stdio 管道/关闭。

不做：PTY、资源限制、作业控制。

---

## 2. 设计逻辑

- 字段 `_handle: ProcessHandle`、`_open: Bool`、`_status: Int?`、`_piped: Bool`。
- `wait` 阻塞；可重复读取同一退出状态。
- `waitTimeout` 超时返回 `Timeout`，进程继续；不 kill。
- `kill` 发 SIGKILL；`signal` 发指定信号；`sendGroupSignal` 向 `-pid` 进程组发信号。
- 非管道进程调用 stdio 方法返回 `Unsupported`，不静默成功。
- `close` 未终结则 kill + 回收；幂等。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_handle` | `ProcessHandle` | OS 句柄 |
| `_open` | `Bool` | 可用 |
| `_status` | `Int?` | 已等待状态 |
| `_piped` | `Bool` | 是否管道进程 |

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
| `groupId` | 进程组 ID | 无 | `Int` | 无；关闭后 -1 |
| `isPiped` | 是否管道进程 | 无 | `Bool` | 无 |
| `isAlive` | 是否存活 | 无 | `Bool` | 无 |
| `wait` | 等待 | `Context` | `Result<Int, Error>` | `Unavailable`/`Io`/`Cancelled` |
| `waitTimeout` | 超时等待 | `Context, Duration` | `Result<Int, Error>` | `Timeout`/`Cancelled` |
| `exitCode` | 已有退出码 | 无 | `Int?` | 无 |
| `kill` | SIGKILL | `Context` | `Result<Unit, Error>` | `Unavailable`/`Io` |
| `signal` | 发信号 | `Context, Signal` | `Result<Unit, Error>` | 同上 |
| `sendSignal` | 1.x 命名信号 | `Signal` | `Result<Unit, Error>` | `InvalidArgument`/`Unsupported`/`Io` |
| `sendGroupSignal` | 进程组信号 | `Signal` | `Result<Unit, Error>` | 同上 |
| `terminate` | SIGTERM | 无 | `Result<Unit, Error>` | `Unavailable`/`Io` |
| `writeStdin` | 写 stdin | `Bytes data` | `Result<Long, Error>` | `Unavailable`/`Unsupported`/`Io` |
| `writeStdinText` | 写 stdin 文本 | `String text` | `Result<Long, Error>` | 同上 |
| `closeStdin` | 关闭 stdin | 无 | `Result<Unit, Error>` | 同上 |
| `readStdout` | 读 stdout | `Long maximumBytes` | `Result<Bytes, Error>` | `InvalidArgument`/`Unavailable`/`Unsupported`/`Io` |
| `readStdoutAll` | 读尽 stdout | 无 | `Result<Bytes, Error>` | 同上 |
| `readStdoutText` | 读 stdout 文本 | 无 | `Result<String, Error>` | 同上 |
| `readStderr` | 读 stderr | `Long maximumBytes` | `Result<Bytes, Error>` | 同上 |
| `readStderrAll` | 读尽 stderr | 无 | `Result<Bytes, Error>` | 同上 |
| `readStderrText` | 读 stderr 文本 | 无 | `Result<String, Error>` | 同上 |
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
    Bool _piped = false

    Process(ProcessHandle handle) {
        _handle = handle
        _open = true
        _status = null
    }

    Long id() { return processId(_handle) }
    Int groupId() {
        if !_open { return -1 }
        return processGroupIdRaw(_handle)
    }
    Bool isPiped() { return _piped }
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

    Result<Unit, Error> sendSignal(Signal signal) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "process closed"))
        }
        return signalProcessRaw(_handle, signalNumber(signal))
    }

    Result<Unit, Error> sendGroupSignal(Signal signal) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "process closed"))
        }
        return signalGroupRaw(_handle, signalNumber(signal))
    }

    Result<Unit, Error> terminate() {
        return self.sendSignal(Signal.Terminate)
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return closeProcessRaw(_handle)
    }

    Bool isOpen() { return _open }
}
```

> `ProcessHandle`、`processId/processGroupIdRaw/processAlive/waitProcessRaw/waitProcessDeadlineRaw/signalProcessRaw/signalGroupRaw/closeProcessRaw` 是 OS/运行时进程原语。

---

## 15. 1.x 进程组/stdio 兼容面（C7）

1.x 已实现、2.x 必须保留：

| 1.x API | 2.x 合同 | 失败/边界 |
| --- | --- | --- |
| `isPiped` | `isPiped()` | 非管道进程的 stdio 方法返回 `Unsupported` |
| `groupId` | `groupId()`；子进程自成组，组号 = pid | 关闭后 -1 |
| `sendGroupSignal(Signal)` | `sendGroupSignal(Signal)`；向 `-pid` 发送 | 未知信号 `Unsupported`；目标无效 `InvalidArgument` |
| `sendSignal(Signal)` | `sendSignal(Signal)` | 同上 |
| `terminate()` | `terminate()`；SIGTERM | 关闭后 `Unavailable` |
| `writeStdin(Bytes)` / `writeStdinText(String)` / `closeStdin()` | 同名；hex 桥保证 NUL/二进制安全 | 非管道/已关闭 `Unsupported`/`Unavailable` |
| `readStdout(Long)` / `readStdoutAll()` / `readStdoutText()` | 同名；返回副本 | 非管道 `Unsupported`；EOF 返回空块 |
| `readStderr(Long)` / `readStderrAll()` / `readStderrText()` | 同名；返回副本 | 同上 |
| `wait()`（无 Context） | `wait(Context)`；信号退出按 `128 + signum` | 取消返回 `Cancelled` |
| `pid(): Int` | `id(): Long` | 类型从 `Int` 迁移到 `Long` |
| `runProcessResult(String)` | `ProcessBuilder` argv-only + `runResult(Context)` | 不接受 shell 字符串；需要 shell 时显式 `/bin/sh -c`，风险自担 |

示例：

```xnull
Result<Process, Error> spawned = ProcessBuilder.of("cat").piped(true).spawnPiped(context)
Process process = spawned.value()
process.writeStdinText("hello\n")
process.closeStdin()
Result<String, Error> output = process.readStdoutText()
Result<Unit, Error> groupSignal = process.sendGroupSignal(Signal.Terminate)
process.close()
```

测试义务：stdin→stdout 往返；stderr 读取；EOF/短读；非管道进程返回 `Unsupported`；进程组 SIGTERM 后 wait 143；`groupId == id`；`terminate` 发 SIGTERM；`sendSignal`/`sendGroupSignal` 未知信号；`pid`/`id` 类型迁移；二进制 NUL 不截断。
