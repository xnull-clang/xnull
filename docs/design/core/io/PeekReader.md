# `PeekReader`

| 项 | 值 |
| --- | --- |
| 类型 | `class PeekReader implements Reader, Closer` |
| 包 | `xdk.io` |
| 稳定性 | `preview` |
| 依赖 | `Reader`、`Bytes` |

---

## 1. 定位

预读包装器：`peek(count)` 看不消费；后续 `read` 先读预读缓冲。

不做：任意 seek、线程安全、异步。

---

## 2. 设计逻辑

- 字段 `_source`、`_buffer: Bytes`、`_position`、`_limit`、`_open`。
- `peek` 填充 buffer 到 count（不超过容量），不移动 position。
- `read` 先从 buffer 消费，再读源。
- close 关闭源。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_source` | `Reader` | 源 |
| `_buffer` | `Bytes` | 预读 |
| `_position` | `Int` | 已消费 |
| `_limit` | `Int` | 有效末尾 |

不变量：0 ≤ position ≤ limit ≤ buffer.length。

---

## 4. 生命周期

构造后使用；close 关闭源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `PeekReader(Reader source, Int capacity)` | source/capacity | source 非 null；capacity >0 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `peek` | 预读 | `Context, Int count` | `Result<Bytes, Error>` | 负值 → panic；`Io`/`Cancelled` |
| `read` | 读 | `Context, Bytes buffer` | `Result<Int, Error>` | `Io`/`Unavailable` |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io` |
| `isOpen` | 可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 预读缓冲；
- 位置/限制；
- 源回退。

---

## 9. 需要的支撑

- 语言：class、Bytes、Int、Bool、Result；
- 运行时：底层 Reader；
- 接口：`Reader`、`Closer`。

---

## 10. 依赖的特性/接口/类

`Reader`、`Closer`、`Bytes`。

---

## 11. 所有权与并发

包装源；close 传递；单 reader。

---

## 12. 示例与反例

正确：peek 头部再 read 完整帧。  
反例：peek 后修改返回 Bytes 期望源变化；close 后 peek；多任务共享。

---

## 13. 测试/场景义务

peek 0/小于/大于可用；peek 不消费；read 先缓冲；EOF；close。

---

## 14. XNull 伪代码

```xnull
class PeekReader implements Reader, Closer {
    Reader _source
    Bytes _buffer
    Int _position
    Int _limit
    Bool _open

    PeekReader(Reader source, Int capacity) {
        if source == null || capacity <= 0 {
            throw "PeekReader: invalid argument"
        }
        _source = source
        _buffer = Bytes.alloc(capacity)
        _position = 0
        _limit = 0
        _open = true
    }

    Result<Bytes, Error> peek(Context context, Int count) {
        if count < 0 { throw "PeekReader.peek: negative" }
        if count > _buffer.length() { count = _buffer.length() }
        while _limit < count && _limit < _buffer.length() {
            Bytes target = Bytes.alloc(_buffer.length() - _limit)
            Result<Int, Error> read = _source.read(context, target)
            if read.isErr() { return Err(read.error()) }
            if read.value() == 0 { break }
            Int index = 0
            while index < read.value() {
                _buffer.set(_limit + index, target.get(index))
                index = index + 1
            }
            _limit = _limit + read.value()
        }
        return Ok(slice(_buffer, _position, _position + count))
    }

    Result<Int, Error> read(Context context, Bytes buffer) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "reader closed"))
        }
        if _position < _limit {
            Int available = _limit - _position
            Int count = buffer.length()
            if available < count { count = available }
            Int index = 0
            while index < count {
                buffer.set(index, _buffer.get(_position + index))
                index = index + 1
            }
            _position = _position + count
            return Ok(count)
        }
        return _source.read(context, buffer)
    }

    Result<Unit, Error> close() { _open = false; return _source.close() }
    Bool isOpen() { return _open }
}
```
