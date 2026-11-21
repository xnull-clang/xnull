# `ProgressBar`

| 项 | 值 |
| --- | --- |
| 类型 | `class ProgressBar` |
| 包 | `xdk.terminal` |
| 稳定性 | `preview` |
| 依赖 | `Terminal`、`Error` |

---

## 1. 定位

调用方驱动的单行进度条：总量、当前值、消息、渲染、完成与清除；终端模式使用回车重绘，非终端退化为纯文本。

不做：后台刷新线程、自动计时、ETA、速率估计、多进度条管理、颜色主题、跨行/全屏进度。

---

## 2. 设计逻辑

- 构造时接收 `Terminal` 和总量 `_total`；总量必须 ≥1。
- `_value` 始终钳制在 0..`_total`；`set` 不抛业务错误，越界自动收敛。
- `_message` 是可选后缀；终端模式会截断以适配宽度，非终端模式完整输出。
- `render` 纯函数：只读状态并返回一行字符串，不写终端。
- 终端模式：`set`/`increment`/`message` 触发 `draw(false)`，写 `\r` + 行，并用空格覆盖上一次更长的行。
- 非终端模式：`set`/`increment`/`message` 只更新状态，不输出；`finish` 输出一行纯文本，避免 CI 日志被刷屏。
- `finish` 把值置为总量、输出最终行并换行；终端模式结束后光标在下一行。
- `clear` 只清除当前行；非终端模式 no-op。
- 无后台线程、无定时器；刷新频率由调用方决定。
- 写入失败通过 `Result` 返回；失败后状态保留，调用方可重试 `finish`/`clear`。
- 非线程安全；跨任务共享需外部同步。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_terminal` | `Terminal` | 输出目标；非 null |
| `_total` | `Int` | ≥1 |
| `_value` | `Int` | 0..`_total` |
| `_message` | `String` | 非 null；可为空 |
| `_finished` | `Bool` | 是否已调用 `finish` |
| `_lastWidth` | `Int` | 上次终端行可见长度，≥0 |

不变量：total ≥1；value 始终在 0..total；message 非 null；`_lastWidth` 只用于覆盖旧行；`render` 不修改任何字段。

---

## 4. 生命周期

构造后可变；`set`/`increment`/`message` 更新；`finish` 结束但仍可再次 `set` 重新开始；`clear` 只擦除显示；无 close、无资源。Terminal 的生命周期由调用方管理。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ProgressBar(Terminal terminal, Int total)` | terminal、total | terminal 非 null；total ≥1 | null/非正总量 → panic |

初始 value=0、message=""、finished=false、lastWidth=0。

---

## 6. 字段表

见 §3；字段私有，外部只能通过方法读取总量/当前值/完成状态。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `total` | 总量 | 无 | `Int` | 无 |
| `value` | 当前值 | 无 | `Int` | 无 |
| `isFinished` | 是否完成 | 无 | `Bool` | 无 |
| `set` | 设置当前值 | `Int value` | `Result<Unit, Error>` | `Io`/`Unavailable` |
| `increment` | 加一 | 无 | `Result<Unit, Error>` | `Io`/`Unavailable` |
| `message` | 设置消息并重绘 | `String text` | `Result<Unit, Error>` | null → panic；`Io`/`Unavailable` |
| `finish` | 置满、输出最终行 | 无 | `Result<Unit, Error>` | `Io`/`Unavailable` |
| `clear` | 清除当前行 | 无 | `Result<Unit, Error>` | `Io`/`Unavailable`（仅终端模式） |
| `render` | 生成一行文本 | 无 | `String` | 无 |

说明：

- `set` 把值钳制到 0..total，清 `finished`，终端模式立即重绘；非终端模式只更新。
- `increment` 在 value 已等于 total 时 no-op；否则等价 `set(value + 1)`。
- `message` 保存文本；终端模式立即重绘；非终端模式只保存。
- `finish` 置 value=total、finished=true；终端模式写 `\r` + 最终行 + `\n` 并 flush；非终端用 `writeLine(render())` 后 flush。
- `clear` 终端模式写 `\r` + `_lastWidth` 个空格 + `\r` 并 flush；非终端返回 `Ok(unit)`。
- `render` 终端模式按 `Terminal.width()` 排布；宽度 0 回退 80；宽度小于 `基础文本+4` 时只返回基础百分比文本。
- `render` 终端模式保留至少 1 个进度格；消息只使用剩余空间，放不下则省略。
- 非终端 `render` 返回 `"百分比% 当前/总量 消息"`，不包含 ANSI、回车或制表控制。
- 本类不在 `Terminal` 层自动 flush；每次 `draw` 写完由本类调用 `Terminal.flush`。

---

## 8. 使用的技术

- 定宽字符条；
- 回车重绘与空格覆盖；
- 百分比整数运算；
- 终端/非终端分支；
- 显式状态机（进行中/已结束）；
- Result 错误传播。

---

## 9. 需要的支撑

- 语言：class、Int、Bool、String、Result、Unit；
- 运行时：无定时器、无后台线程；
- 接口：`Terminal.isTerminal/width/write/writeLine/flush`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Terminal`、`Error`、`BasicError`、`ErrorKind`；不依赖 `log`、`i18n`、`Context`、`schedule`。

---

## 11. 所有权与并发

- `_terminal` 借用，外部拥有。
- 本类持有可变显示状态；非线程安全；并发调用可能产生交错输出。
- 无后台任务、无共享全局；每个进度条一个实例。
- 写入失败不破坏 value/message；调用方可重试或降低刷新频率。

---

## 12. 示例与反例

正确：终端下每处理一项调用 `increment()`；完成后 `finish()`；CI 下用 `Terminal(context, Stdio.stdout(), false, 0, 0)`，只在 `finish` 看到一行。  
反例：在 `set` 里启动线程自动刷新；非终端每次 `set` 打印一行；`finish` 不换行导致下一条日志接在进度条后；宽度不足时消息覆盖进度格；忽略写入错误。

---

## 13. 测试/场景义务

0%、50%、100%；total=1；set 越界钳制；increment 到上限；message 空/长/Unicode；窄终端（width 0/1/10/80）；非终端无 ANSI；finish 换行与 flush；clear 只擦当前行；重复 finish；finish 后 set 重新开始；写失败传播；并发误用检测；无后台线程（测试无定时器）。

---

## 14. XNull 伪代码

```xnull
class ProgressBar {
    final Terminal _terminal
    final Int _total
    Int _value
    String _message
    Bool _finished
    Int _lastWidth

    ProgressBar(Terminal terminal, Int total) {
        if terminal == null { throw "ProgressBar: null terminal" }
        if total < 1 { throw "ProgressBar: total must be positive" }
        _terminal = terminal
        _total = total
        _value = 0
        _message = ""
        _finished = false
        _lastWidth = 0
    }

    Int total() { return _total }
    Int value() { return _value }
    Bool isFinished() { return _finished }

    Result<Unit, Error> set(Int value) {
        if value < 0 { value = 0 }
        if value > _total { value = _total }
        _value = value
        _finished = false
        if !_terminal.isTerminal() { return Ok(unit) }
        return self.draw(false)
    }

    Result<Unit, Error> increment() {
        if _value >= _total { return Ok(unit) }
        return self.set(_value + 1)
    }

    Result<Unit, Error> message(String text) {
        if text == null { throw "ProgressBar.message: null text" }
        _message = text
        if !_terminal.isTerminal() { return Ok(unit) }
        return self.draw(false)
    }

    Result<Unit, Error> finish() {
        _value = _total
        _finished = true
        if _terminal.isTerminal() {
            return self.draw(true)
        }
        Result<Unit, Error> written = _terminal.writeLine(self.render())
        if written.isErr() { return written }
        return _terminal.flush()
    }

    Result<Unit, Error> clear() {
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

    String render() {
        Int percent = (_value * 100) / _total
        String base = str(percent) + "% " + str(_value) + "/" + str(_total)
        if !_terminal.isTerminal() {
            if _message == "" { return base }
            return base + " " + _message
        }
        Int width = _terminal.width()
        if width <= 0 { width = 80 }
        if width < base.length() + 4 {
            return base
        }
        Int barWidth = width - base.length() - 3
        String message = _message
        if message != "" {
            Int messageRoom = barWidth - 4
            if messageRoom > 0 {
                if message.length() > messageRoom {
                    message = message.substring(0, messageRoom)
                }
                barWidth = barWidth - message.length() - 1
            } else {
                message = ""
            }
        }
        if barWidth < 1 { barWidth = 1 }
        Int filled = (_value * barWidth) / _total
        if filled > barWidth { filled = barWidth }
        String bar = ""
        Int index = 0
        while index < barWidth {
            if index < filled {
                bar = bar + "#"
            } else {
                bar = bar + "-"
            }
            index = index + 1
        }
        String line = "[" + bar + "] " + base
        if message != "" {
            line = line + " " + message
        }
        if line.length() > width {
            line = line.substring(0, width)
        }
        return line
    }

    private Result<Unit, Error> draw(Bool newline) {
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
        if newline {
            output = output + "\n"
            _lastWidth = 0
        } else {
            _lastWidth = line.length()
        }
        Result<Unit, Error> written = _terminal.write(output)
        if written.isErr() { return written }
        return _terminal.flush()
    }
}
```
