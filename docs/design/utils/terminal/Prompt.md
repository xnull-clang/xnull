# `Prompt`

| 项 | 值 |
| --- | --- |
| 类型 | `class Prompt` |
| 包 | `xdk.terminal` |
| 稳定性 | `preview` |
| 依赖 | `Reader`、`Writer`、`LineReader`、`Context`、`Error` |

---

## 1. 定位

基于显式 `Reader`/`Writer` 的阻塞式交互提示：自由文本、密码、确认、单选。

不做：GUI/事件循环、raw mode、密码回显控制、行编辑/历史、自动补全、超时调度、表单校验 DSL、国际化。

---

## 2. 设计逻辑

- 构造时接收 `Reader` 与 `Writer`，本类不拥有、不关闭二者；内部用 `LineReader` 按行读取。
- `text`：写提示语，读一行；EOF 返回 `Io` 错误。
- `password`：写提示语，读一行；**从不把用户输入写回 Writer**。终端驱动是否回显由 Reader/终端模式决定，本类不做开关。
- `confirm`：提示 `[y/N]`；空输入、`n`、`no` 为 false；`y`/`yes` 为 true；其他输入重试，最多 8 次。
- `select`：打印编号选项，读取编号；1..N 合法，其他重试，最多 8 次；返回选中的选项文本。
- 所有阻塞方法首参 `Context`；取消由 `LineReader.readLine` 和显式检查共同响应。
- 每次提示写入后 `flush`，确保提示语先于读取显示。
- 输入为 null（EOF）一律返回 `Io`，不返回空串冒充输入。
- 选项为空/为 null 返回 `InvalidArgument`，不进入循环。
- 无全局 stdin/stdout、无后台任务、无线程；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_reader` | `Reader` | 输入源；非 null；外部拥有 |
| `_writer` | `Writer` | 输出目标；非 null；外部拥有 |
| `_lines` | `LineReader` | 包装 `_reader`；仅本类使用 |

不变量：reader/writer 非 null；Prompt 不关闭 reader/writer；不缓存密码/输入；所有输出都经过 `_writer`。

---

## 4. 生命周期

构造后长期使用；无 close；reader/writer 的生命周期由调用方管理。Prompt 不持有系统全局句柄，可在测试中用内存流替换。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Prompt(Reader reader, Writer writer)` | reader、writer | 均非 null | null → panic |

构造时创建 `LineReader(reader)`，不读取、不写提示。

---

## 6. 字段表

见 §3；字段私有且构造后不替换。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `text` | 读取自由文本 | `Context context, String message` | `Result<String, Error>` | `Cancelled`/`Io`/`Unavailable` |
| `password` | 读取密码 | `Context context, String message` | `Result<String, Error>` | `Cancelled`/`Io`/`Unavailable` |
| `confirm` | 是/否确认 | `Context context, String message` | `Result<Bool, Error>` | `Cancelled`/`Io`/`InvalidArgument` |
| `select` | 单选 | `Context context, String message, List<String> options` | `Result<String, Error>` | `Cancelled`/`Io`/`InvalidArgument` |

说明：

- `text`/`password` 写入 `message + ": "`，然后读一行；空行是合法输入，返回 `""`。
- `password` 只写提示语，不写输入值，也不在返回后补写密码；调用方不得把密码再交给日志/终端。
- `confirm` 写入 `message + " [y/N]: "`；大小写不敏感、去首尾空白；空输入为 false。
- `confirm` 非法输入写一行 `Please answer yes or no.\n` 后重试；8 次仍非法返回 `InvalidArgument`。
- `select` 写入 `message`、换行、每个选项 `  n) 文本`、最后 `Select 1-N: `；读取并 `parseInt`。
- `select` 编号越界/非数字写 `Invalid selection.\n` 后重试；8 次仍非法返回 `InvalidArgument`。
- `select` 返回选项原文（`List.get`），不返回索引；需要索引的调用方用 `options.indexOf` 自行计算。
- 所有方法在入口检查 `context`/`message` 非 null；null 参数是编程错误，panic。
- 写入前检查 `context.isCancelled()`；取消返回 `Cancelled`，不输出提示语。
- 写入失败立即返回；读取取消返回 `Cancelled`；EOF 返回 `Io`。
- 提示语与选项按调用方提供的原文写出；本类不做 ANSI 处理、不转义换行、不做 i18n；内置的 `[y/N]`、重试/无效选择提示为英文，X 允许注入消息表。

---

## 8. 使用的技术

- 行式阻塞读取；
- Writer 提示与 flush；
- Context 取消；
- 有限重试；
- 编号菜单解析；
- Result 错误传播。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Int、List、可空类型、Result、Unit；
- 运行时：阻塞读取由底层 Reader 决定；
- 接口：`Reader`、`Writer`、`LineReader.readLine`、`Context.isCancelled`、`parseInt`、`BasicError`、`ErrorKind`、`fromUtf8`。

---

## 10. 依赖的特性/接口/类

`Reader`、`Writer`、`LineReader`、`Context`、`Error`、`BasicError`、`ErrorKind`、`parseInt`、`fromUtf8`。

不依赖 `Terminal`、`log`、`i18n`、`sys`/PTY。

---

## 11. 所有权与并发

- reader 与 writer 借用，外部拥有并负责 close。
- `LineReader` 只被 Prompt 使用；不关闭底层 reader。
- 不保存输入内容；密码读取后只存在于返回字符串中，调用方负责及时清理（XNull 字符串不可变，清理能力有限）。
- 阻塞期间占用调用任务；不要同时在多个任务复用同一个 Prompt/Reader。
- 非线程安全；无全局状态。

---

## 12. 示例与反例

正确：`new Prompt(Stdio.stdin(), Stdio.stdout())`；`prompt.text(ctx, "Name")`；`prompt.confirm(ctx, "Delete")`；`prompt.select(ctx, "Target", options)`。  
反例：用 Prompt 读密码后把结果写回 Writer；把 EOF 当空串；选项为空仍进入循环；在 UI 线程无限阻塞且不传 Context；多个任务并发读同一个 Reader；把提示语当作 i18n 消息目录。

---

## 13. 测试/场景义务

文本空行/普通/Unicode/EOF；密码输入不回写；confirm 的 y/yes/n/no/空/非法/大小写/首尾空白；confirm 8 次上限；select 合法/越界/非数字/空选项；取消前后；写失败；读失败；flush 调用；null 参数 panic；多 Prompt 共享 writer 的交错检测；无全局 stdin/stdout。

---

## 14. XNull 伪代码

```xnull
class Prompt {
    final Reader _reader
    final Writer _writer
    final LineReader _lines

    Prompt(Reader reader, Writer writer) {
        if reader == null || writer == null { throw "Prompt: null reader or writer" }
        _reader = reader
        _writer = writer
        _lines = new LineReader(reader)
    }

    Result<String, Error> text(Context context, String message) {
        if context == null { throw "Prompt.text: null context" }
        if message == null { throw "Prompt.text: null message" }
        Result<Unit, Error> written = self.writeText(context, message + ": ")
        if written.isErr() { return Err(written.error()) }
        return self.readAnswer(context, "prompt.text")
    }

    Result<String, Error> password(Context context, String message) {
        if context == null { throw "Prompt.password: null context" }
        if message == null { throw "Prompt.password: null message" }
        Result<Unit, Error> written = self.writeText(context, message + ": ")
        if written.isErr() { return Err(written.error()) }
        return self.readAnswer(context, "prompt.password")
    }

    Result<Bool, Error> confirm(Context context, String message) {
        if context == null { throw "Prompt.confirm: null context" }
        if message == null { throw "Prompt.confirm: null message" }
        Int attempts = 0
        while attempts < 8 {
            attempts = attempts + 1
            Result<Unit, Error> written = self.writeText(context, message + " [y/N]: ")
            if written.isErr() { return Err(written.error()) }
            Result<String, Error> answer = self.readAnswer(context, "prompt.confirm")
            if answer.isErr() { return Err(answer.error()) }
            String normalized = answer.value().trim().toLower()
            if normalized == "" || normalized == "n" || normalized == "no" {
                return Ok(false)
            }
            if normalized == "y" || normalized == "yes" {
                return Ok(true)
            }
            Result<Unit, Error> invalid = self.writeText(context, "Please answer yes or no.\n")
            if invalid.isErr() { return Err(invalid.error()) }
        }
        return Err(new BasicError(ErrorKind.InvalidArgument, "prompt.confirm: too many invalid answers"))
    }

    Result<String, Error> select(Context context, String message, List<String> options) {
        if context == null { throw "Prompt.select: null context" }
        if message == null { throw "Prompt.select: null message" }
        if options == null || options.length() == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "prompt.select: empty options"))
        }
        Int index = 0
        while index < options.length() {
            if options.get(index) == null {
                return Err(new BasicError(ErrorKind.InvalidArgument, "prompt.select: null option"))
            }
            index = index + 1
        }
        Int attempts = 0
        while attempts < 8 {
            attempts = attempts + 1
            String menu = message + "\n"
            index = 0
            while index < options.length() {
                menu = menu + "  " + str(index + 1) + ") " + options.get(index) + "\n"
                index = index + 1
            }
            menu = menu + "Select 1-" + str(options.length()) + ": "
            Result<Unit, Error> written = self.writeText(context, menu)
            if written.isErr() { return Err(written.error()) }
            Result<String, Error> answer = self.readAnswer(context, "prompt.select")
            if answer.isErr() { return Err(answer.error()) }
            Result<Int, Error> parsed = parseInt(answer.value().trim())
            if parsed.isErr() {
                Result<Unit, Error> invalid = self.writeText(context, "Invalid selection.\n")
                if invalid.isErr() { return Err(invalid.error()) }
            } else {
                Int picked = parsed.value()
                if picked >= 1 && picked <= options.length() {
                    return Ok(options.get(picked - 1))
                }
                Result<Unit, Error> invalid = self.writeText(context, "Invalid selection.\n")
                if invalid.isErr() { return Err(invalid.error()) }
            }
        }
        return Err(new BasicError(ErrorKind.InvalidArgument, "prompt.select: too many invalid answers"))
    }

    private Result<String, Error> readAnswer(Context context, String label) {
        if context.isCancelled() {
            return Err(cancelledError(label))
        }
        Result<String?, Error> line = _lines.readLine(context)
        if line.isErr() { return Err(line.error()) }
        String? value = line.value()
        if value == null {
            return Err(new BasicError(ErrorKind.Io, label + ": end of input"))
        }
        return Ok(value as String)
    }

    private Result<Unit, Error> writeText(Context context, String text) {
        if context.isCancelled() { return Err(cancelledError("prompt write")) }
        Result<Unit, Error> written = _writer.writeAll(context, fromUtf8(text))
        if written.isErr() { return written }
        return _writer.flush()
    }
}
```
