# `Spinner`

| 项 | 值 |
| --- | --- |
| 类型 | `class Spinner` |
| 包 | `xdk.terminal` |
| 稳定性 | `preview` |
| 依赖 | `Terminal`、`Context`、`Error` |

---

## 1. 定位

显式 `tick()` 驱动的单行旋转指示器：帧序列、间隔提示、消息、启动/停止/重绘。

不做：后台定时线程、自动调度、多行动画、颜色主题、终端能力探测、帧率自适应。

---

## 2. 设计逻辑

- 必须有渲染目标 `Terminal`；本类不直接写 stdout。
- 构造时复制帧列表；帧数 ≥1、间隔 ≥1ms；空帧/非法间隔 panic。
- `start(Context?)` 只置运行标志、记录可选上下文并重绘首帧；**不创建线程、不睡眠、不注册定时器**。
- `tick()` 是唯一推进帧的入口：未运行时 no-op；运行且上下文已取消时清除当前行并返回 `Cancelled`；否则前进一帧并重绘。
- `intervalMillis` 只是建议间隔，供调用方/未来 `schedule` 集成使用；`tick` 本身不等待。
- 终端模式：`tick`/`start`/`setMessage` 写 `\r` + 行并 flush，用空格覆盖旧行；非终端模式不输出动画，只保留状态，`render` 可读。
- `stop()` 停止并清除当前行；重复 stop 幂等。
- `setMessage` 保存消息；运行中终端模式立即重绘。
- 写入失败通过 `Result` 返回；状态保持可重试。
- 无全局线程、无全局帧表；每个实例独立。
- 非线程安全；同一实例的 `tick` 不应并发调用。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_terminal` | `Terminal` | 渲染目标；非 null |
| `_frames` | `List<String>` | 非空；构造时复制 |
| `_intervalMillis` | `Long` | ≥1；建议间隔 |
| `_frameIndex` | `Int` | 0..frames.length-1 |
| `_message` | `String` | 非 null；可为空 |
| `_running` | `Bool` | 是否正在显示 |
| `_context` | `Context?` | 可选取消源 |
| `_lastWidth` | `Int` | 上次终端行可见长度，≥0 |

不变量：frames 非空；frameIndex 始终合法；interval ≥1；message 非 null；非运行状态不推进帧；render 不修改字段。

---

## 4. 生命周期

构造后长期使用；`start` 进入运行、`stop` 退出、可再次 `start`；无 close、无后台资源。上下文由调用方创建和取消，本类不 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Spinner(Terminal terminal, List<String> frames, Long intervalMillis)` | terminal、frames、intervalMillis | terminal 非 null；frames 非 null 且非空；每帧非 null；intervalMillis ≥1 | 非法 → panic |

构造时复制 frames；调用方之后修改原列表不影响 Spinner。初始未运行、frameIndex=0、message=""。

---

## 6. 字段表

见 §3；字段私有；外部只能通过 `isRunning`、`frame`、`intervalMillis` 读取状态。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `start` | 启动并重绘首帧 | `Context? context` | `Result<Unit, Error>` | `Io`/`Unavailable` |
| `tick` | 前进一帧并重绘 | 无 | `Result<Unit, Error>` | `Cancelled`/`Io`/`Unavailable` |
| `stop` | 停止并清行 | 无 | `Result<Unit, Error>` | `Io`/`Unavailable` |
| `setMessage` | 设置消息 | `String text` | `Result<Unit, Error>` | null → panic；`Io`/`Unavailable` |
| `isRunning` | 是否运行 | 无 | `Bool` | 无 |
| `frame` | 当前帧 | 无 | `String` | 无 |
| `intervalMillis` | 建议间隔 | 无 | `Long` | 无 |
| `render` | 生成一行文本 | 无 | `String` | 无 |

说明：

- `start` 已在运行时只更新 `_context` 并返回 `Ok(unit)`，不重绘、不重置帧。
- `start(null)` 表示不启用取消检查。
- `tick` 在未运行时返回 `Ok(unit)`；取消时先 `clearLine`，再返回 `Err(cancelledError("spinner"))`。
- `tick` 的帧推进为 `(frameIndex + 1) % frames.length()`；首帧在 `start` 显示，第一次 tick 显示第二帧。
- `stop` 在未运行时返回 `Ok(unit)`；运行中清除行、置 `_running=false`、清 `_context`。
- `setMessage` 不在运行时只保存，不输出。
- `render` 返回 `"帧"` 或 `"帧 消息"`；不含 ANSI、回车；终端重绘由 `draw` 添加 `\r`。
- `intervalMillis` 不被 `tick` 强制执行；调用方用定时器/循环按该间隔调用 `tick`。
- 本类不创建 `Task`、不调用 `sleep`、不依赖 `schedule`。

---

## 8. 使用的技术

- 显式状态机（停止/运行）；
- 帧索引取模；
- 回车重绘与空格覆盖；
- 可选 `Context` 取消；
- Terminal/非终端分支；
- Result 错误传播。

---

## 9. 需要的支撑

- 语言：class、List、Long、Int、Bool、String、可空类型、Result、Unit；
- 运行时：`Context.isCancelled`、`cancelledError`；
- 接口：`Terminal.isTerminal/write/flush`、`Context`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Terminal`、`Context`、`Error`、`BasicError`、`ErrorKind`、`cancelledError`；不依赖 `schedule`、`log`、`i18n`。

---

## 11. 所有权与并发

- `_terminal` 借用，外部拥有。
- `_frames` 构造时复制，之后只读。
- `_context` 借用，不取消、不关闭；调用方拥有。
- 非线程安全；同一实例并发 `tick`/`start`/`stop` 需外部同步。
- 无后台线程、无全局状态；X 自动 Spinner 只能通过显式调度器组合，不能把线程藏进本类。

---

## 12. 示例与反例

正确：`start(ctx)` 后由调用方每 100ms 调用 `tick()`；取消后 `stop()`；非终端模式只调用 `render()` 或完全不显示。  
反例：在 `start` 内创建线程自动 tick；`tick` 内 `sleep` 阻塞调用方；忘记 `stop` 导致光标停在同一行；在非终端输出 `\r`；用同一个 Spinner 并发 tick。

---

## 13. 测试/场景义务

start/tick/stop 顺序；重复 start/stop；未运行 tick；取消后 tick 返回 `Cancelled` 并清行；帧循环；单帧；消息空/长/Unicode；终端宽度 0/1/80；非终端无输出；写失败传播；`render` 纯函数；无后台线程（无定时器断言）；并发误用检测。

---

## 14. XNull 伪代码

```xnull
class Spinner {
    final Terminal _terminal
    final List<String> _frames
    final Long _intervalMillis
    Int _frameIndex
    String _message
    Bool _running
    Context? _context
    Int _lastWidth

    Spinner(Terminal terminal, List<String> frames, Long intervalMillis) {
        if terminal == null { throw "Spinner: null terminal" }
        if frames == null || frames.length() == 0 { throw "Spinner: empty frames" }
        if intervalMillis < 1 { throw "Spinner: interval must be positive" }
        Int index = 0
        while index < frames.length() {
            if frames.get(index) == null { throw "Spinner: null frame" }
            index = index + 1
        }
        _terminal = terminal
        _frames = frames.copy()
        _intervalMillis = intervalMillis
        _frameIndex = 0
        _message = ""
        _running = false
        _context = null
        _lastWidth = 0
    }

    Result<Unit, Error> start(Context? context) {
        if _running {
            _context = context
            return Ok(unit)
        }
        _running = true
        _frameIndex = 0
        _context = context
        return self.draw()
    }

    Result<Unit, Error> tick() {
        if !_running { return Ok(unit) }
        Context? source = _context
        if source != null {
            Context context = source as Context
            if context.isCancelled() {
                Result<Unit, Error> cleared = self.clearLine()
                _running = false
                _context = null
                if cleared.isErr() { return cleared }
                return Err(cancelledError("spinner tick"))
            }
        }
        _frameIndex = (_frameIndex + 1) % _frames.length()
        return self.draw()
    }

    Result<Unit, Error> stop() {
        if !_running { return Ok(unit) }
        _running = false
        _context = null
        return self.clearLine()
    }

    Result<Unit, Error> setMessage(String text) {
        if text == null { throw "Spinner.setMessage: null text" }
        _message = text
        if !_running { return Ok(unit) }
        return self.draw()
    }

    Bool isRunning() { return _running }

    String frame() {
        return _frames.get(_frameIndex)
    }

    Long intervalMillis() {
        return _intervalMillis
    }

    String render() {
        if _message == "" { return self.frame() }
        return self.frame() + " " + _message
    }

    private Result<Unit, Error> draw() {
        if !_terminal.isTerminal() { return Ok(unit) }
        String line = self.render()
        String output = "\r" + line
        if line.length() < _lastWidth {
            Int padding = _lastWidth - line.length()
            while padding > 0 {
                output = output + " "
                padding = padding - 1
            }
        }
        _lastWidth = line.length()
        Result<Unit, Error> written = _terminal.write(output)
        if written.isErr() { return written }
        return _terminal.flush()
    }

    private Result<Unit, Error> clearLine() {
        if !_terminal.isTerminal() { return Ok(unit) }
        String blank = ""
        Int index = 0
        while index < _lastWidth {
            blank = blank + " "
            index = index + 1
        }
        _lastWidth = 0
        Result<Unit, Error> written = _terminal.write("\r" + blank + "\r")
        if written.isErr() { return written }
        return _terminal.flush()
    }
}
```
