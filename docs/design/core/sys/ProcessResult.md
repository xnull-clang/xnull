# `ProcessResult`

| 项 | 值 |
| --- | --- |
| 类型 | `class ProcessResult` |
| 包 | `xdk.sys` |
| 稳定性 | `stable` |
| 依赖 | 无 |

---

## 1. 定位

子进程结果快照：退出码、stdout/stderr、耗时、终止信号。

不做：流式输出、PTY、进程句柄。

---

## 2. 设计逻辑

- 不可变快照；字段 `_status: Int`、`_stdout: String`、`_stderr: String`、`_durationMillis: Long`、`_signal: Signal?`。
- `isSuccess` = status == 0。
- 信号终止时 status 按 128+signal；`signal` 可记录具体信号。
- 无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_status` | `Int` | 退出码 |
| `_stdout` | `String` | 标准输出 |
| `_stderr` | `String` | 标准错误 |
| `_durationMillis` | `Long` | 耗时 |
| `_signal` | `Signal?` | 终止信号 |

不变量：duration ≥0；status 可为 128+signal。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

构造器内部；由 `ProcessBuilder.runResult` 创建。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `status` | 退出码 | 无 | `Int` | 无 |
| `stdout` | 标准输出 | 无 | `String` | 无 |
| `stderr` | 标准错误 | 无 | `String` | 无 |
| `durationMillis` | 耗时 | 无 | `Long` | 无 |
| `signal` | 终止信号 | 无 | `Signal?` | 无 |
| `isSuccess` | 成功 | 无 | `Bool` | 无 |
| `describe` | 摘要 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 不可变快照；
- 退出码/信号；
- 输出捕获。

---

## 9. 需要的支撑

- 语言：class、Int、Long、String、Bool；
- 运行时：进程等待/输出捕获；
- 接口：`Signal`。

---

## 10. 依赖的特性/接口/类

`Signal`。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`result.isSuccess()`；`result.stdout()`。  
反例：用 status 判断信号而不看 signal；把大输出当流；修改快照。

---

## 13. 测试/场景义务

成功/失败；stdout/stderr；信号终止；耗时；空输出；大输出（X）。

---

## 14. XNull 伪代码

```xnull
class ProcessResult {
    final Int _status
    final String _stdout
    final String _stderr
    final Long _durationMillis
    final Signal? _signal

    ProcessResult(Int status, String stdout, String stderr, Long durationMillis, Signal? signal) {
        _status = status
        _stdout = stdout
        _stderr = stderr
        _durationMillis = durationMillis
        _signal = signal
    }

    Int status() { return _status }
    String stdout() { return _stdout }
    String stderr() { return _stderr }
    Long durationMillis() { return _durationMillis }
    Signal? signal() { return _signal }
    Bool isSuccess() { return _status == 0 }

    String describe() {
        return "status=" + str(_status)
            + " duration=" + str(_durationMillis) + "ms"
            + " stdout=" + str(_stdout.length())
            + " stderr=" + str(_stderr.length())
    }
}
```

---

## 15. 1.x 字段兼容（C7）

- 1.x `ProcessResult.code`（`Int`）→ 2.x `status()`。
- 1.x `ProcessResult.output`（`String`）→ 2.x `stdout()`。
- 2.x 增加 `stderr()`、`durationMillis()`、`signal()`、`isSuccess()`；1.x 的 stdout-only 行为由 `stdout()` 保留。
- 1.x 公共字段访问迁移到访问器；不保留第二套结果类型。
- 1.x `runProcessResult` 只捕获 stdout；2.x `ProcessBuilder.runResult` 可同时提供 stderr，但不得改变 `stdout()` 语义。

测试义务：`code`→`status()`、`output`→`stdout()` 迁移；stderr/duration/signal 增量；成功/失败/信号终止；空输出。
