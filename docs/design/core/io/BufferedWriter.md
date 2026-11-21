# `BufferedWriter`

| 项 | 值 |
| --- | --- |
| 类型 | `class BufferedWriter implements Writer, Closer` |
| 包 | `xdk.io` |
| 稳定性 | `preview` |
| 依赖 | `Writer`、`Bytes` |

---

## 1. 定位

带缓冲的 Writer 包装器；减少底层写入次数。

不做：异步、线程安全、格式化。

---

## 2. 设计逻辑

- 字段 `_target`、`_buffer`、`_length`、`_open`。
- `write` 小数据进缓冲；满则 flush；大数据直接写目标。
- `flush` 写缓冲并刷新目标。
- `close` flush 后关闭目标；幂等。
- 单 writer；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_target` | `Writer` | 底层 |
| `_buffer` | `Bytes` | 缓冲 |
| `_length` | `Int` | 已缓冲 |
| `_open` | `Bool` | 可用 |

不变量：0 ≤ length ≤ buffer.length。

---

## 4. 生命周期

构造后使用；close flush + 关闭目标。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `BufferedWriter(Writer target, Int capacity)` | target/capacity | target 非 null；capacity >0 | null/≤0 → panic |

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
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io` |
| `isOpen` | 可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 写缓冲；
- 批量 flush；
- 大块直写；
- close 传递。

---

## 9. 需要的支撑

- 语言：class、Bytes、Int、Bool、Result；
- 运行时：底层 Writer；
- 接口：`Writer`、`Closer`。

---

## 10. 依赖的特性/接口/类

`Writer`、`Closer`、`Bytes`。

---

## 11. 所有权与并发

包装目标；close 传递；单 writer；非线程安全。

---

## 12. 示例与反例

正确：多次 write 后 flush/close。  
反例：不 flush 期望立即落盘；close 后写；多任务共享。

---

## 13. 测试/场景义务

小/大块；flush；close 幂等；写入失败；缓冲边界；取消。

---

## 14. XNull 伪代码

```xnull
class BufferedWriter implements Writer, Closer {
    Writer _target
    Bytes _buffer
    Int _length
    Bool _open

    BufferedWriter(Writer target, Int capacity) {
        if target == null || capacity <= 0 {
            throw "BufferedWriter: invalid argument"
        }
        _target = target
        _buffer = Bytes.alloc(capacity)
        _length = 0
        _open = true
    }

    Result<Unit, Error> flush(Context context) {
        if _length > 0 {
            Bytes data = slice(_buffer, 0, _length)
            Result<Unit, Error> write = _target.writeAll(context, data)
            if write.isErr() { return Err(write.error()) }
            _length = 0
        }
        return _target.flush()
    }

    Result<Int, Error> write(Context context, Bytes data) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "writer closed"))
        }
        if data.length() >= _buffer.length() {
            Result<Unit, Error> flushed = self.flush(context)
            if flushed.isErr() { return Err(flushed.error()) }
            Result<Unit, Error> written = _target.writeAll(context, data)
            if written.isErr() { return Err(written.error()) }
            return Ok(data.length())
        }
        if _length + data.length() > _buffer.length() {
            Result<Unit, Error> flushed = self.flush(context)
            if flushed.isErr() { return Err(flushed.error()) }
        }
        Int index = 0
        while index < data.length() {
            _buffer.set(_length + index, data.get(index))
            index = index + 1
        }
        _length = _length + data.length()
        return Ok(data.length())
    }

    Result<Unit, Error> writeAll(Context context, Bytes data) {
        Result<Int, Error> written = self.write(context, data)
        if written.isErr() { return Err(written.error()) }
        return Ok(unit)
    }

    Result<Unit, Error> flush() { return self.flush(null) }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        Result<Unit, Error> flushed = self.flush(null)
        _open = false
        Result<Unit, Error> closed = _target.close()
        if flushed.isErr() { return flushed }
        return closed
    }

    Bool isOpen() { return _open }
}
```
