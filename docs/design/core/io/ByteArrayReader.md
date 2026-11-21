# `ByteArrayReader`

| 项 | 值 |
| --- | --- |
| 类型 | `class ByteArrayReader implements Reader, Seekable, Closer` |
| 包 | `xdk.io` |
| 稳定性 | `stable` |
| 依赖 | `Bytes`、`SeekOrigin` |

---

## 1. 定位

内存字节读流；支持顺序读和 seek。

不做：文件/网络、线程安全、写。

---

## 2. 设计逻辑

- 字段 `_data: Bytes`、`_position: Long`。
- 读取复制到调用方缓冲；0=EOF。
- seek 失败位置不变；close no-op。
- 单 reader；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_data` | `Bytes` | 源 |
| `_position` | `Long` | 当前偏移 |

不变量：0 ≤ position ≤ data.length；不可越界。

---

## 4. 生命周期

构造后使用；无资源；close no-op。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ByteArrayReader(Bytes data)` | data | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `read` | 读 | `Context, Bytes buffer` | `Result<Int, Error>` | `Unavailable` |
| `seek` | 定位 | `Long offset, SeekOrigin origin` | `Result<Long, Error>` | `InvalidArgument` |
| `position` | 当前 | 无 | `Long` | 无 |
| `size` | 大小 | 无 | `Result<Long, Error>` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | 无 |
| `isOpen` | 可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 字节切片；
- 64 位偏移；
- EOF=0。

---

## 9. 需要的支撑

- 语言：class、Bytes、Long、Int、Result；
- 运行时：字节切片；
- 接口：`Reader`、`Seekable`、`Closer`、`SeekOrigin`。

---

## 10. 依赖的特性/接口/类

`Reader`、`Seekable`、`Closer`、`SeekOrigin`、`Bytes`。

---

## 11. 所有权与并发

借用 `_data`；read 返回副本；close no-op；非线程安全。

---

## 12. 示例与反例

正确：读 10 字节；seek 到末尾；size。  
反例：负偏移；读越界；多任务共享。

---

## 13. 测试/场景义务

空/单/多；EOF；seek 三种 origin；越界；close；size。

---

## 14. XNull 伪代码

```xnull
class ByteArrayReader implements Reader, Seekable, Closer {
    Bytes _data
    Long _position
    Bool _open

    ByteArrayReader(Bytes data) {
        if data == null { throw "ByteArrayReader: null data" }
        _data = data
        _position = 0
        _open = true
    }

    Result<Int, Error> read(Context context, Bytes buffer) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "reader closed"))
        }
        if buffer.length() == 0 { return Ok(0) }
        if _position >= _data.length() as Long { return Ok(0) }
        Long available = (_data.length() as Long) - _position
        Int count = buffer.length()
        if available < count as Long { count = available as Int }
        Int index = 0
        while index < count {
            buffer.set(index, _data.get((_position + index as Long) as Int))
            index = index + 1
        }
        _position = _position + count as Long
        return Ok(count)
    }

    Result<Long, Error> seek(Long offset, SeekOrigin origin) {
        Long base = 0
        if origin == SeekOrigin.Current { base = _position }
        if origin == SeekOrigin.End { base = _data.length() as Long }
        Long target = base + offset
        if target < 0 || target > _data.length() as Long {
            return Err(new BasicError(ErrorKind.InvalidArgument, "seek out of range"))
        }
        _position = target
        return Ok(target)
    }

    Long position() { return _position }
    Result<Long, Error> size() { return Ok(_data.length() as Long) }
    Result<Unit, Error> close() { _open = false; return Ok(unit) }
    Bool isOpen() { return _open }
}
```
