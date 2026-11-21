# `LimitReader`

| 项 | 值 |
| --- | --- |
| 类型 | `class LimitReader implements Reader, Closer` |
| 包 | `xdk.io` |
| 稳定性 | `preview` |
| 依赖 | `Reader` |

---

## 1. 定位

限制最多读取 N 字节；用于协议帧/安全上限。

不做：定位、写、缓冲。

---

## 2. 设计逻辑

- 字段 `_source: Reader`、`_remaining: Long`、`_open`。
- `read` 取 `min(buffer.length, remaining)`；remaining 0 返回 EOF。
- 成功读取后递减 remaining。
- `close` 关闭源；幂等。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_source` | `Reader` | 源 |
| `_remaining` | `Long` | 剩余可读 |
| `_open` | `Bool` | 可用 |

不变量：remaining ≥0。

---

## 4. 生命周期

构造后使用；close 关闭源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `LimitReader(Reader source, Long limit)` | source/limit | source 非 null；limit ≥0 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `read` | 限读 | `Context, Bytes buffer` | `Result<Int, Error>` | `Io`/`Unavailable` |
| `remaining` | 剩余 | 无 | `Long` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io` |
| `isOpen` | 可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 剩余计数；
- 最小读取；
- 关闭传播。

---

## 9. 需要的支撑

- 语言：class、Bytes、Long、Int、Bool、Result；
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

正确：帧体最多 1MB。  
反例：超限期望继续读；remaining 0 读非 0；多任务共享。

---

## 13. 测试/场景义务

limit 0；小于缓冲；大于缓冲；EOF；close；remaining。

---

## 14. XNull 伪代码

```xnull
class LimitReader implements Reader, Closer {
    Reader _source
    Long _remaining
    Bool _open

    LimitReader(Reader source, Long limit) {
        if source == null || limit < 0 {
            throw "LimitReader: invalid argument"
        }
        _source = source
        _remaining = limit
        _open = true
    }

    Result<Int, Error> read(Context context, Bytes buffer) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "reader closed"))
        }
        if _remaining == 0 { return Ok(0) }
        Long maximum = _remaining
        if maximum > buffer.length() as Long { maximum = buffer.length() as Long }
        Bytes part = Bytes.alloc(maximum as Int)
        Result<Int, Error> read = _source.read(context, part)
        if read.isErr() { return Err(read.error()) }
        Int index = 0
        while index < read.value() {
            buffer.set(index, part.get(index))
            index = index + 1
        }
        _remaining = _remaining - read.value() as Long
        return read
    }

    Long remaining() { return _remaining }

    Result<Unit, Error> close() {
        _open = false
        return _source.close()
    }

    Bool isOpen() { return _open }
}
```
