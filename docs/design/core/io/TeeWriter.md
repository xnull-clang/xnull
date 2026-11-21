# `TeeWriter`

| 项 | 值 |
| --- | --- |
| 类型 | `class TeeWriter implements Writer, Closer` |
| 包 | `xdk.io` |
| 稳定性 | `preview` |
| 依赖 | `Writer` |

---

## 1. 定位

双写：同一数据写两个 Writer。

不做：分流/过滤、异步、缓冲。

---

## 2. 设计逻辑

- 字段 `_first: Writer`、`_second: Writer`、`_open`。
- `write/writeAll` 先写 first，再写 second；任一失败传播。
- `flush/close` 两者都做；close 幂等。
- 单 writer；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_first` | `Writer` | 第一目标 |
| `_second` | `Writer` | 第二目标 |
| `_open` | `Bool` | 可用 |

不变量：两目标都收到同一数据。

---

## 4. 生命周期

构造后使用；close 两者。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TeeWriter(Writer first, Writer second)` | first/second | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `write` | 写 | `Context, Bytes data` | `Result<Int, Error>` | `Io`/`Unavailable` |
| `writeAll` | 写全 | 同上 | `Result<Unit, Error>` | 同上 |
| `flush` | 刷新 | 无 | `Result<Unit, Error>` | `Io` |
| `close` | 关闭两者 | 无 | `Result<Unit, Error>` | `Io` |
| `isOpen` | 可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 双写；
- 失败短路；
- 关闭传播。

---

## 9. 需要的支撑

- 语言：class、Bytes、Int、Bool、Result；
- 运行时：Writer；
- 接口：`Writer`、`Closer`。

---

## 10. 依赖的特性/接口/类

`Writer`、`Closer`、`Bytes`。

---

## 11. 所有权与并发

持有两个 writer；close 两者；单 writer。

---

## 12. 示例与反例

正确：同时写 stdout 和文件。  
反例：first 失败后继续写 second 期望一致；多任务共享。

---

## 13. 测试/场景义务

双写一致；first/second 失败；flush/close；writeAll；空数据。

---

## 14. XNull 伪代码

```xnull
class TeeWriter implements Writer, Closer {
    Writer _first
    Writer _second
    Bool _open

    TeeWriter(Writer first, Writer second) {
        if first == null || second == null { throw "TeeWriter: null writer" }
        _first = first
        _second = second
        _open = true
    }

    Result<Int, Error> write(Context context, Bytes data) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "writer closed"))
        }
        Result<Unit, Error> first = _first.writeAll(context, data)
        if first.isErr() { return Err(first.error()) }
        Result<Unit, Error> second = _second.writeAll(context, data)
        if second.isErr() { return Err(second.error()) }
        return Ok(data.length())
    }

    Result<Unit, Error> writeAll(Context context, Bytes data) {
        Result<Int, Error> result = self.write(context, data)
        if result.isErr() { return Err(result.error()) }
        return Ok(unit)
    }

    Result<Unit, Error> flush() {
        Result<Unit, Error> first = _first.flush()
        Result<Unit, Error> second = _second.flush()
        if first.isErr() { return first }
        return second
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        Result<Unit, Error> first = _first.close()
        Result<Unit, Error> second = _second.close()
        if first.isErr() { return first }
        return second
    }

    Bool isOpen() { return _open }
}
```
