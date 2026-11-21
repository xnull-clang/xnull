# `ChainReader`

| 项 | 值 |
| --- | --- |
| 类型 | `class ChainReader implements Reader, Closer` |
| 包 | `xdk.io` |
| 稳定性 | `preview` |
| 依赖 | `Reader` |

---

## 1. 定位

串联多个 Reader：前一个 EOF 后自动切到下一个。

不做：并行、线程安全、重新排序。

---

## 2. 设计逻辑

- 字段 `_sources: List<Reader>`、`_index`、`_open`。
- `read` 当前源 EOF 则前进；全部 EOF 返回 0。
- `close` 关闭全部源；幂等。
- 单 reader；非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_sources` | `List<Reader>` | 源列表 |
| `_index` | `Int` | 当前源 |
| `_open` | `Bool` | 可用 |

不变量：0 ≤ index ≤ sources.length。

---

## 4. 生命周期

构造后使用；close 关闭全部。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ChainReader(List<Reader> sources)` | sources | 非 null；元素非 null | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `read` | 读 | `Context, Bytes buffer` | `Result<Int, Error>` | `Io`/`Unavailable` |
| `readExact` | 读满 | `Context, Bytes buffer` | `Result<Unit, Error>` | `DataCorrupted` |
| `close` | 关闭全部 | 无 | `Result<Unit, Error>` | `Io` |
| `isOpen` | 可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 源列表；
- EOF 前进；
- 关闭传播。

---

## 9. 需要的支撑

- 语言：class、List、Int、Bool、Result；
- 运行时：底层 Reader；
- 接口：`Reader`、`Closer`。

---

## 10. 依赖的特性/接口/类

`Reader`、`Closer`、`List`。

---

## 11. 所有权与并发

持有源引用；close 全部；单 reader。

---

## 12. 示例与反例

正确：拼接多个文件流。  
反例：空源列表期望错误（应返回 EOF）；close 后读；多任务共享。

---

## 13. 测试/场景义务

空/单/多源；跨源读；EOF；close 传播；readExact。

---

## 14. XNull 伪代码

```xnull
class ChainReader implements Reader, Closer {
    List<Reader> _sources
    Int _index
    Bool _open

    ChainReader(List<Reader> sources) {
        if sources == null { throw "ChainReader: null sources" }
        _sources = []
        Int index = 0
        while index < sources.length() {
            if sources.get(index) == null { throw "ChainReader: null source" }
            _sources.push(sources.get(index))
            index = index + 1
        }
        _index = 0
        _open = true
    }

    Result<Int, Error> read(Context context, Bytes buffer) {
        if !_open {
            return Err(new BasicError(ErrorKind.Unavailable, "reader closed"))
        }
        while _index < _sources.length() {
            Result<Int, Error> read = _sources.get(_index).read(context, buffer)
            if read.isErr() { return Err(read.error()) }
            if read.value() > 0 { return read }
            _index = _index + 1
        }
        return Ok(0)
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

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        Int index = 0
        while index < _sources.length() {
            Result<Unit, Error> closed = _sources.get(index).close()
            if closed.isErr() { return closed }
            index = index + 1
        }
        return Ok(unit)
    }

    Bool isOpen() { return _open }
}
```
