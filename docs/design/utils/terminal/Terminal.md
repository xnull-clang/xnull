# `Terminal`

| 项 | 值 |
| --- | --- |
| 类型 | `class Terminal` |
| 包 | `xdk.terminal` |
| 稳定性 | `preview` |
| 依赖 | `Writer`、`Context`、`Error`、`Ansi` |

---

## 1. 定位

`Writer` 之上的文本终端门面：保存是否为终端、宽高快照，提供写文本、写行、清屏和刷新。

不做：全局 stdout、终端能力探测、输入读取、光标全量寻址、日志格式化、颜色策略、后台刷新、窗口大小变化监听。

---

## 2. 设计逻辑

- 构造时接收 `Writer`，本类不拥有、不关闭 writer；writer 的生命周期归调用方。
- `_isTerminal` 是能力开关：为 false 时本类不生成 ANSI，并在写入前剥离 CSI/SGR，`clear` 直接 no-op，所有文本按纯文本写出。
- `_width`/`_height` 是构造时快照；0 表示未知，组件使用默认 80 列。本类不查询操作系统。
- `write` 把 `String` 编码为 UTF-8 后调用 `Writer.writeAll`；非终端模式先移除 CSI/SGR 序列；短写由 writer 协议处理。
- `writeLine` 把文本与 `\n` 合并成一次写入，避免多任务/多组件交错插入换行。
- `clear` 仅在终端模式写入 `Ansi.clearScreen()`；非终端返回成功且不写任何字节。
- `flush` 直接委托 writer；清屏不自动刷新，调用方决定何时刷新。
- 本类无 close；writer 的 close 由持有者负责。
- 本类非线程安全；跨任务共享需外部同步，或每个任务使用独立 Terminal。
- 构造时接收 `Context` 并保存；`write`/`writeLine`/`clear` 使用它调用 Writer，调用方可通过取消该 Context 终止阻塞写入。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_writer` | `Writer` | 非 null；外部拥有 |
| `_isTerminal` | `Bool` | 是否允许 ANSI |
| `_width` | `Int` | ≥0；0 表示未知 |
| `_height` | `Int` | ≥0；0 表示未知 |
| `_context` | `Context` | 调用方传入；用于 Writer 写入取消 |

不变量：writer 非 null；宽高非负；`_isTerminal=false` 时 `clear` 不产生输出；本类不缓存文本内容。

---

## 4. 生命周期

构造后长期使用，通常与 writer 同寿命；无 close、无可变尺寸、无资源。writer 关闭后继续调用 `write`/`writeLine` 返回 `Unavailable`，`flush` 返回 writer 的错误。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Terminal(Context context, Writer writer, Bool isTerminal, Int width, Int height)` | context、writer、isTerminal、width、height | 全部非 null；width/height ≥0 | null/负维度 → panic |

说明：`isTerminal=false` 且宽高为 0 合法；`isTerminal=true` 且宽高为 0 也合法，表示终端未报告尺寸，由使用方回退默认值。

---

## 6. 字段表

见 §3；字段全部私有，构造后不可替换 writer 或尺寸。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `isTerminal` | 是否终端模式 | 无 | `Bool` | 无 |
| `width` | 列数快照 | 无 | `Int` | 无 |
| `height` | 行数快照 | 无 | `Int` | 无 |
| `write` | 写文本 | `String text` | `Result<Unit, Error>` | `Io`/`Unavailable` |
| `writeLine` | 写文本并换行 | `String text` | `Result<Unit, Error>` | `Io`/`Unavailable` |
| `clear` | 清屏 | 无 | `Result<Unit, Error>` | `Io`/`Unavailable`（仅终端模式） |
| `flush` | 刷新 writer | 无 | `Result<Unit, Error>` | `Io` |

说明：

- `write` 先检查 `writer.isOpen()`；关闭时返回 `Unavailable`，不尝试写入。
- `write` 在非终端模式剥离 CSI/SGR 后编码；终端模式原样编码，不做 ANSI 解析。
- `write` 内部调用 `writeAll(_context, fromUtf8(output))`；`output` 是剥离后的文本；`_context` 由构造方传入，不跨实例共享。
- `writeLine` 只调用一次 `write`，参数为 `text + "\n"`；空字符串会写出一个换行。
- `clear` 在非终端模式返回 `Ok(unit)`，不写 ANSI；终端模式写入清屏并归位序列。
- `clear` 不自动 `flush`；需要立即显示时由调用方调用 `flush`。
- `width`/`height` 返回原始快照，不做默认值替换；使用方把 0 当作未知。
- 不支持 `close`；本类不拥有 writer。

---

## 8. 使用的技术

- Writer 适配器；
- UTF-8 文本编码；
- 终端能力布尔开关；
- CSI/SGR 剥离（仅非终端模式）；
- 尺寸快照；
- ANSI 门控；
- Result 错误传播。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Int、Result、Unit、StringBuilder；
- 运行时：UTF-8 编码、writer 的关闭可见性；
- 接口：`Writer`、`Context`、`Error`、`BasicError`、`ErrorKind`、`Ansi.clearScreen`、`fromUtf8`。

---

## 10. 依赖的特性/接口/类

`Writer`、`Context`、`Error`、`Ansi`、`BasicError`、`ErrorKind`、`fromUtf8`、`StringBuilder`。

---

## 11. 所有权与并发

- `_writer` 借用，外部拥有并负责 close。
- 不保留调用方字符串的引用。
- 引用语义；非线程安全；并发写可能交错，需调用方加锁或分片。
- 无全局状态；每个 Terminal 独立保存 writer、尺寸和能力开关。
- `_context` 由调用方持有；取消后写入返回 `Cancelled`；Terminal 不重置/替换它。

---

## 12. 示例与反例

正确：`new Terminal(context, Stdio.stdout(), true, 120, 40)`；`writeLine("done")`；重定向时传 `isTerminal=false`，带样式的文本会被剥离为纯文本。  
反例：把 Terminal 做成全局 stdout 单例；非终端模式仍生成 ANSI；Terminal 关闭 writer；用已取消 Context 写入；期望 `width()` 随窗口变化自动更新；并发写同一 Terminal 不加同步；传入 OSC 超链接并期望非终端模式剥离。

---

## 13. 测试/场景义务

终端/非终端两种模式；空字符串；多行文本；Unicode/emoji；带 SGR 的文本在非终端被剥离；终端模式保留 SGR；CSI 非 SGR 序列；OSC 不被剥离（记录为限制）；writer 短写；writer 关闭后写；writer 写失败；`clear` 在非终端不产生字节；终端 `clear` 产生清屏序列；`flush` 失败传播；宽高 0；负宽高 panic；null context/writer panic；取消 Context 写入；并发写交错检测。

---

## 14. XNull 伪代码

```xnull
class Terminal {
    final Writer _writer
    final Bool _isTerminal
    final Int _width
    final Int _height
    final Context _context

    Terminal(Context context, Writer writer, Bool isTerminal, Int width, Int height) {
        if context == null || writer == null { throw "Terminal: null context/writer" }
        if width < 0 || height < 0 { throw "Terminal: negative dimension" }
        _writer = writer
        _isTerminal = isTerminal
        _width = width
        _height = height
        _context = context
    }

    Bool isTerminal() {
        return _isTerminal
    }

    Int width() {
        return _width
    }

    Int height() {
        return _height
    }

    Result<Unit, Error> write(String text) {
        if text == null { throw "Terminal.write: null text" }
        if !_writer.isOpen() {
            return Err(new BasicError(ErrorKind.Unavailable, "terminal writer is closed"))
        }
        String output = text
        if !_isTerminal {
            output = self.plain(text)
        }
        return _writer.writeAll(_context, fromUtf8(output))
    }

    Result<Unit, Error> writeLine(String text) {
        if text == null { throw "Terminal.writeLine: null text" }
        return self.write(text + "\n")
    }

    Result<Unit, Error> clear() {
        if !_isTerminal {
            return Ok(unit)
        }
        return self.write(Ansi.clearScreen())
    }

    Result<Unit, Error> flush() {
        return _writer.flush()
    }

    private String plain(String text) {
        StringBuilder builder = new StringBuilder()
        Int index = 0
        while index < text.length() {
            Char character = text.charAt(index)
            if (character as Int) == 27 && index + 1 < text.length() && text.charAt(index + 1) == '[' {
                index = self.ansiEnd(text, index)
            } else {
                builder.appendChar(character)
                index = index + 1
            }
        }
        return builder.build()
    }

    private Int ansiEnd(String text, Int start) {
        Int index = start + 2
        while index < text.length() {
            Int code = text.charAt(index) as Int
            index = index + 1
            if code >= 64 && code <= 126 { return index }
        }
        return index
    }
}
```
