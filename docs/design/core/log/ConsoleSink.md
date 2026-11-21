# `ConsoleSink`

| 项 | 值 |
| --- | --- |
| 类型 | `class ConsoleSink implements Sink` |
| 包 | `xdk.log` |
| 稳定性 | `stable` |
| 依赖 | `Writer`、`Formatter`、`TextFormatter` |

---

## 1. 定位

控制台/流 sink：用 Formatter 格式化记录并写一行到指定 Writer。

不做：颜色/ANSI（terminal）、文件轮转、异步。

---

## 2. 设计逻辑

- 字段 `_target: Writer`、`_formatter: Formatter`、`_open`。
- `write` 格式化为一行 + `\n`，写目标；失败返回 Io。
- 默认 TextFormatter；可由构造传入。
- `close` 关闭目标；幂等。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_target` | `Writer` | 输出 |
| `_formatter` | `Formatter` | 格式 |
| `_open` | `Bool` | 可用 |

不变量：target/formatter 非 null；单行输出。

---

## 4. 生命周期

构造后使用；close 关闭目标。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ConsoleSink(Writer target)` | target | 非 null | null → panic |
| `ConsoleSink(Writer target, Formatter formatter)` | target/formatter | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `write` | 写记录 | `LogRecord` | `Result<Unit, Error>` | `Io`/`Unavailable` |
| `flush` | 刷新 | 无 | `Result<Unit, Error>` | `Io` |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io` |
| `isOpen` | 可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- Formatter 组合；
- 行写入；
- 关闭传播。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Result；
- 运行时：`io.Writer`；
- 接口：`Sink`、`Formatter`、`TextFormatter`、`fromUtf8`。

---

## 10. 依赖的特性/接口/类

`Sink`、`Formatter`、`TextFormatter`、`Writer`、`fromUtf8`。

---

## 11. 所有权与并发

持有 Writer/Formatter；close 目标；单 writer。

---

## 12. 示例与反例

正确：`new ConsoleSink(Stdio.stdout())`。  
反例：期望 ANSI；close 后写；多任务共享。

---

## 13. 测试/场景义务

格式化输出；flush/close；失败；默认 Formatter。

---

## 14. XNull 伪代码

```xnull
class ConsoleSink implements Sink {
    Writer _target
    Formatter _formatter
    Bool _open

    ConsoleSink(Writer target) {
        if target == null { throw "ConsoleSink: null target" }
        _target = target
        _formatter = new TextFormatter()
        _open = true
    }

    ConsoleSink(Writer target, Formatter formatter) {
        if target == null || formatter == null { throw "ConsoleSink: null argument" }
        _target = target
        _formatter = formatter
        _open = true
    }

    Result<Unit, Error> write(LogRecord record) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "sink closed"))
        }
        String line = _formatter.format(record) + "\n"
        return _target.writeAll(null, fromUtf8(line))
    }

    Result<Unit, Error> flush() { return _target.flush() }

    Result<Unit, Error> close() {
        _open = false
        return _target.close()
    }

    Bool isOpen() { return _open }
}
```
