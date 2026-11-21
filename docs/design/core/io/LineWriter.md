# `LineWriter`

| 项 | 值 |
| --- | --- |
| 类型 | `class LineWriter implements Writer, Closer` |
| 包 | `xdk.io` |
| 稳定性 | `preview` |
| 依赖 | `Writer`、`fromUtf8` |

---

## 1. 定位

按行写入：`writeLine` 追加文本 + `\n`；其余委托底层 Writer。

不做：行缓冲、格式化、异步。

---

## 2. 设计逻辑

- 包装 Writer；`writeLine` = writeText + 换行。
- `writeLines` 逐行；`write/writeAll` 直接委托。
- `flush/close` 委托；close 幂等。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_target` | `Writer` | 底层 |
| `_open` | `Bool` | 可用 |

不变量：无内部缓冲；非线程安全。

---

## 4. 生命周期

构造后使用；close 关闭目标。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `LineWriter(Writer target)` | target | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `writeLine` | 写一行 | `Context, String line` | `Result<Unit, Error>` | `Io`/`Unavailable` |
| `writeLines` | 写多行 | `Context, List<String> lines` | `Result<Unit, Error>` | 同上 |
| `write` | 写字节 | `Context, Bytes data` | `Result<Int, Error>` | 同上 |
| `writeAll` | 写全 | 同上 | `Result<Unit, Error>` | 同上 |
| `flush` | 刷新 | 无 | `Result<Unit, Error>` | `Io` |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io` |
| `isOpen` | 可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 行尾追加；
- UTF-8 编码；
- 委托。

---

## 9. 需要的支撑

- 语言：class、String、Bytes、List、Result；
- 运行时：底层 Writer；
- 接口：`Writer`、`Closer`、`fromUtf8`。

---

## 10. 依赖的特性/接口/类

`Writer`、`Closer`、`fromUtf8`。

---

## 11. 所有权与并发

包装目标；close 传递；单 writer。

---

## 12. 示例与反例

正确：writeLine("a") 输出 `a\n`。  
反例：期望不添加换行；close 后写；多任务共享。

---

## 13. 测试/场景义务

单/多行；空行；writeLines；flush/close；写入失败；取消。

---

## 14. XNull 伪代码

```xnull
class LineWriter implements Writer, Closer {
    Writer _target
    Bool _open

    LineWriter(Writer target) {
        if target == null { throw "LineWriter: null target" }
        _target = target
        _open = true
    }

    Result<Unit, Error> writeLine(Context context, String line) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "writer closed"))
        }
        Result<Unit, Error> text = _target.writeAll(context, fromUtf8(line))
        if text.isErr() { return Err(text.error()) }
        return _target.writeAll(context, fromUtf8("\n"))
    }

    Result<Unit, Error> writeLines(Context context, List<String> lines) {
        Int index = 0
        while index < lines.length() {
            Result<Unit, Error> result = self.writeLine(context, lines.get(index))
            if result.isErr() { return Err(result.error()) }
            index = index + 1
        }
        return Ok(unit)
    }

    Result<Int, Error> write(Context context, Bytes data) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "writer closed"))
        }
        return _target.write(context, data)
    }

    Result<Unit, Error> writeAll(Context context, Bytes data) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "writer closed"))
        }
        return _target.writeAll(context, data)
    }

    Result<Unit, Error> flush() { return _target.flush() }

    Result<Unit, Error> close() {
        _open = false
        return _target.close()
    }

    Bool isOpen() { return _open }
}
```
