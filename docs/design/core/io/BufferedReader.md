# `BufferedReader`

| 项 | 值 |
| --- | --- |
| 类型 | `class BufferedReader implements Reader, Closer` |
| 包 | `xdk.io` |
| 稳定性 | `preview` |
| 依赖 | `Reader`、`Bytes` |

---

## 1. 定位

带缓冲的 Reader 包装器；减少底层读取次数。

不做：异步、线程安全、行解析（LineReader）。

---

## 2. 设计逻辑

- 字段 `_source`、`_buffer`、`_position`、`_limit`、`_open`。
- 缓冲空时从源读一块；`read` 先从缓冲复制。
- `close` 关闭源；关闭后读 `Unavailable`。
- 单 reader；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_source` | `Reader` | 底层 |
| `_buffer` | `Bytes` | 缓冲 |
| `_position` | `Int` | 已消费 |
| `_limit` | `Int` | 有效末尾 |
| `_open` | `Bool` | 可用 |

不变量：0 ≤ position ≤ limit ≤ buffer.length。

---

## 4. 生命周期

构造后使用；close 关闭源；无其他资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `BufferedReader(Reader source, Int capacity)` | source/capacity | source 非 null；capacity >0 | null/≤0 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `read` | 读 | `Context, Bytes buffer` | `Result<Int, Error>` | `Io`/`Unavailable` |
| `readExact` | 读满 | `Context, Bytes buffer` | `Result<Unit, Error>` | `DataCorrupted` |
| `readLine` | 读行 | `Context` | `Result<String?, Error>` | `Io` |
| `peek` | 预读 | `Context, Int count` | `Result<Bytes, Error>` | `Io`/`Cancelled` |
| `skip` | 跳过 | `Context, Long count` | `Result<Long, Error>` | `Io`/`Cancelled` |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io` |
| `isOpen` | 可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 双缓冲；
- 批量填充；
- 行切分。

---

## 9. 需要的支撑

- 语言：class、Bytes、Int、Long、Result；
- 运行时：底层 Reader；
- 接口：`Reader`、`Closer`。

---

## 10. 依赖的特性/接口/类

`Reader`、`Closer`、`Bytes`。

---

## 11. 所有权与并发

包装源；close 传递；单 reader；非线程安全。

---

## 12. 示例与反例

正确：包装 File/ByteArrayReader；读小块。  
反例：多任务共享；close 后读；缓冲容量 0。

---

## 13. 测试/场景义务

空/单/多；EOF；readExact；readLine；peek；skip；close 传递。

---

## 14. XNull 伪代码

```xnull
class BufferedReader implements Reader, Closer {
    Reader _source
    Bytes _buffer
    Int _position
    Int _limit
    Bool _open

    BufferedReader(Reader source, Int capacity) {
        if source == null || capacity <= 0 {
            throw "BufferedReader: invalid argument"
        }
        _source = source
        _buffer = Bytes.alloc(capacity)
        _position = 0
        _limit = 0
        _open = true
    }

    Result<Unit, Error> fill(Context context) {
        if _position < _limit { return Ok(unit) }
        Result<Int, Error> read = _source.read(context, _buffer)
        if read.isErr() { return Err(read.error()) }
        _position = 0
        _limit = read.value()
        return Ok(unit)
    }

    Result<Int, Error> read(Context context, Bytes buffer) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "reader closed"))
        }
        Result<Unit, Error> filled = self.fill(context)
        if filled.isErr() { return Err(filled.error()) }
        if _limit == 0 { return Ok(0) }
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

    Result<Unit, Error> readExact(Context context, Bytes buffer) {
        Int total = 0
        while total < buffer.length() {
            Bytes part = Bytes.alloc(buffer.length() - total)
            Result<Int, Error> read = self.read(context, part)
            if read.isErr() { return Err(read.error()) }
            if read.value() == 0 {
                return Err(new BasicError(ErrorKind.DataCorrupted, "unexpected EOF"))
            }
            Int index = 0
            while index < read.value() {
                buffer.set(total + index, part.get(index))
                index = index + 1
            }
            total = total + read.value()
        }
        return Ok(unit)
    }

    Result<String?, Error> readLine(Context context) {
        Bytes line = Bytes.empty()
        Bytes one = Bytes.alloc(1)
        while true {
            Result<Int, Error> read = self.read(context, one)
            if read.isErr() { return Err(read.error()) }
            if read.value() == 0 {
                if line.isEmpty() { return Ok(null) }
                return Ok(toUtf8(line))
            }
            if one.get(0) == 10 { return Ok(toUtf8(line)) }
            if one.get(0) != 13 { line.push(one.get(0)) }
        }
    }

    Result<Bytes, Error> peek(Context context, Int count) {
        if count < 0 { throw "BufferedReader.peek: negative" }
        Result<Unit, Error> filled = self.fill(context)
        if filled.isErr() { return Err(filled.error()) }
        Int available = _limit - _position
        if count > available { count = available }
        return Ok(slice(_buffer, _position, _position + count))
    }

    Result<Long, Error> skip(Context context, Long count) {
        if count < 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "negative skip"))
        }
        Long skipped = 0
        while skipped < count {
            Result<Unit, Error> filled = self.fill(context)
            if filled.isErr() { return Err(filled.error()) }
            if _limit == 0 { break }
            Int available = _limit - _position
            Int step = count - skipped
            if available < step { step = available }
            _position = _position + step
            skipped = skipped + step
        }
        return Ok(skipped)
    }

    Result<Unit, Error> close() {
        _open = false
        return _source.close()
    }

    Bool isOpen() { return _open }
}
```
