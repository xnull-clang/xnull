# `StringReader`

| 项 | 值 |
| --- | --- |
| 类型 | `class StringReader implements Reader, Seekable, Closer` |
| 包 | `xdk.io` |
| 稳定性 | `preview` |
| 依赖 | `Bytes`、`fromUtf8`、`SeekOrigin` |

---

## 1. 定位

内存字符串读流；按 UTF-8 字节读取；支持 seek。

不做：文件/网络、码点游标、线程安全。

---

## 2. 设计逻辑

- 构造时 `_bytes = fromUtf8(text)`；`_position: Long`。
- `read` 复制字节；0=EOF；close no-op。
- `seek` 按字节偏移；调用方需保证 UTF-8 边界。
- 非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_bytes` | `Bytes` | UTF-8 字节 |
| `_position` | `Long` | 字节偏移 |
| `_open` | `Bool` | 可用 |

不变量：0 ≤ position ≤ bytes.length。

---

## 4. 生命周期

构造后使用；无资源；close no-op。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `StringReader(String text)` | text | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `read` | 读字节 | `Context, Bytes buffer` | `Result<Int, Error>` | `Unavailable` |
| `seek` | 定位 | `Long, SeekOrigin` | `Result<Long, Error>` | `InvalidArgument` |
| `position` | 当前 | 无 | `Long` | 无 |
| `size` | 大小 | 无 | `Result<Long, Error>` | 无 |
| `readAllText` | 读剩余文本 | 无 | `String` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | 无 |
| `isOpen` | 可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- UTF-8 编码；
- 字节游标；
- 切片。

---

## 9. 需要的支撑

- 语言：class、String、Bytes、Long、Int、Result；
- 运行时：UTF-8 编码；
- 接口：`Reader`、`Seekable`、`Closer`、`SeekOrigin`、`fromUtf8`。

---

## 10. 依赖的特性/接口/类

`Reader`、`Seekable`、`Closer`、`SeekOrigin`、`Bytes`、`fromUtf8`。

---

## 11. 所有权与并发

持有 `_bytes`；read 副本；非线程安全。

---

## 12. 示例与反例

正确：read 3 字节；seek 0。  
反例：seek 到 UTF-8 中间；用字符索引当字节索引；多任务共享。

---

## 13. 测试/场景义务

ASCII/多字节；EOF；seek；readAllText；close；非法边界。

---

## 14. XNull 伪代码

```xnull
class StringReader implements Reader, Seekable, Closer {
    Bytes _bytes
    Long _position
    Bool _open

    StringReader(String text) {
        if text == null { throw "StringReader: null text" }
        _bytes = fromUtf8(text)
        _position = 0
        _open = true
    }

    Result<Int, Error> read(Context context, Bytes buffer) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "reader closed"))
        }
        if _position >= _bytes.length() as Long { return Ok(0) }
        Long available = (_bytes.length() as Long) - _position
        Int count = buffer.length()
        if available < count as Long { count = available as Int }
        Int index = 0
        while index < count {
            buffer.set(index, _bytes.get((_position + index as Long) as Int))
            index = index + 1
        }
        _position = _position + count as Long
        return Ok(count)
    }

    Result<Long, Error> seek(Long offset, SeekOrigin origin) {
        Long base = 0
        if origin == SeekOrigin.Current { base = _position }
        if origin == SeekOrigin.End { base = _bytes.length() as Long }
        Long target = base + offset
        if target < 0 || target > _bytes.length() as Long {
            return Err(new BasicError(ErrorKind.InvalidArgument, "seek out of range"))
        }
        _position = target
        return Ok(target)
    }

    Long position() { return _position }
    Result<Long, Error> size() { return Ok(_bytes.length() as Long) }

    String readAllText() {
        return toUtf8(slice(_bytes, _position as Int, _bytes.length()))
    }

    Result<Unit, Error> close() { _open = false; return Ok(unit) }
    Bool isOpen() { return _open }
}
```
