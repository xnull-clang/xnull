# `ByteReader`

| 项 | 值 |
| --- | --- |
| 类型 | `class ByteReader` |
| 包 | `xdk.bytes` |
| 稳定性 | `stable` |
| 依赖 | `Bytes`、`Endian` |

---

## 1. 定位

带游标的字节读取器：顺序/随机读、checked 读、mark/reset、skip、readExact。

不做：文件/网络流、线程安全、零拷贝视图。

---

## 2. 设计逻辑

- 游标不变量 `0 ≤ position ≤ limit ≤ source.length`。
- unchecked 读取越界 panic；checked `try*` 返回 `Result`，失败位置不变。
- `readBytes` 钳制；`readExact` 严格。
- `peek` 不前进；`mark/reset` 支持回退。
- 读取期间源不得修改。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_source` | `Bytes` | 借用源 |
| `_position` | `Int` | 当前游标 |
| `_limit` | `Int` | 读取上限 |
| `_mark` | `Int` | 标记；-1 无 |

不变量：0 ≤ mark ≤ position ≤ limit ≤ source.length；失败不移动位置。

---

## 4. 生命周期

- 构造后使用；无 close；需要重置时 seek/mark/reset 或新建。
- 非线程安全。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ByteReader(Bytes source)` | source | 非 null | null → panic |

初始 position=0，limit=source.length，mark=-1。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `position` | 当前游标 | 无 | `Int` | 无 |
| `limit` | 上限 | 无 | `Int` | 无 |
| `remaining` | 剩余 | 无 | `Int` | 无 |
| `hasRemaining` | 是否剩余 | 无 | `Bool` | 无 |
| `seek` | 设置游标 | `Int offset` | `Result<Unit, Error>` | `InvalidArgument` |
| `skip` | 前进 | `Int count` | `Result<Unit, Error>` | `InvalidArgument` |
| `mark` | 标记 | 无 | `void` | 无 |
| `reset` | 回标记 | 无 | `Result<Unit, Error>` | 无标记 → `InvalidArgument` |
| `peek` | 看下一字节 | 无 | `Int` | EOF → panic |
| `readU8` | 读 1 | 无 | `Int` | EOF → panic |
| `tryReadU8` | checked 1 | 无 | `Result<Int, Error>` | `DataCorrupted` |
| `readU16BE/LE` | 读 2 | 无 | `Int` | 不足 → panic |
| `readI16BE/LE` | 读 2 有符号 | 无 | `Int` | 不足 → panic |
| `readU32BE/LE` | 读 4 无符号 | 无 | `Long` | 不足 → panic |
| `readI32BE/LE` | 读 4 有符号 | 无 | `Int` | 不足 → panic |
| `readU64BE/LE` | 读 8 无符号 | 无 | `Long` | 不足 → panic |
| `readI64BE/LE` | 读 8 | 无 | `Long` | 不足 → panic |
| `readF32BE/LE` | 读 float | 无 | `Double` | 不足 → panic |
| `readF64BE/LE` | 读 double | 无 | `Double` | 不足 → panic |
| `readBytes` | 钳制读 | `Int count` | `Bytes` | 负值 → panic |
| `readExact` | 恰好读 | `Int count` | `Result<Bytes, Error>` | `DataCorrupted` |
| `readAll` | 读到 limit | 无 | `Bytes` | 无 |
| `readLine` | 读到换行 | 无 | `String` | 无 |
| `readUntil` | 读到分隔 | `Int delimiter` | `String` | 无 |
| `readInto` | 读入目标 | `Bytes target` | `Int` | 无 |
| `readUtf8` | 读文本 | `Int count` | `String` | 无 |
| `readHex` | 读 hex | `Int count` | `String` | 无 |
| `tryReadU16/U32/U64` | checked | 无 | `Result<...>` | `DataCorrupted` |

---

## 8. 使用的技术

- 游标；
- 端序读；
- 钳制/严格；
- mark/reset；
- checked 失败位置不变。

---

## 9. 需要的支撑

- 语言：class、Bytes、Int、Long、Double、String、Bool、Result；
- 运行时：字节访问；
- 接口：`Endian` 读函数、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Bytes`、`Endian`、`BasicError`、`ErrorKind`、`Result`。

---

## 11. 所有权与并发

- 借用 `source`；不复制，不保留可变引用。
- `readBytes/readExact/readAll` 返回副本。
- 非线程安全；读取期间源不得修改。

---

## 12. 示例与反例

正确：`readExact` 解析帧；失败位置不变；`readBytes` 钳制。  
反例：EOF 期望 readU8 返回 0；读取期间 push 源；把 readBytes 当严格读。

---

## 13. 测试/场景义务

空/边界；seek/skip/mark/reset；各宽度 BE/LE；checked 失败位置；readExact 不足；readLine/readUntil；并发外部同步。

---

## 14. XNull 伪代码

```xnull
class ByteReader {
    Bytes _source
    Int _position
    Int _limit
    Int _mark

    ByteReader(Bytes source) {
        if source == null {
            throw "ByteReader: null source"
        }
        _source = source
        _position = 0
        _limit = source.length()
        _mark = -1
    }

    Int position() { return _position }
    Int limit() { return _limit }
    Int remaining() { return _limit - _position }
    Bool hasRemaining() { return _position < _limit }

    Result<Unit, Error> seek(Int offset) {
        if offset < 0 || offset > _limit {
            return Err(new BasicError(ErrorKind.InvalidArgument, "seek out of range"))
        }
        _position = offset
        return Ok(unit)
    }

    Result<Unit, Error> skip(Int count) {
        if count < 0 || _position + count > _limit {
            return Err(new BasicError(ErrorKind.InvalidArgument, "skip out of range"))
        }
        _position = _position + count
        return Ok(unit)
    }

    void mark() {
        _mark = _position
    }

    Result<Unit, Error> reset() {
        if _mark < 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "no mark"))
        }
        _position = _mark
        return Ok(unit)
    }

    Int peek() {
        if _position >= _limit {
            throw "ByteReader.peek: end of input"
        }
        return _source.get(_position)
    }

    Int readU8() {
        if _position >= _limit {
            throw "ByteReader.readU8: end of input"
        }
        Int value = _source.get(_position)
        _position = _position + 1
        return value
    }

    Result<Int, Error> tryReadU8() {
        if _position >= _limit {
            return Err(new BasicError(ErrorKind.DataCorrupted, "end of input"))
        }
        return Ok(self.readU8())
    }

    Int readU16BE() {
        if _position + 2 > _limit {
            throw "ByteReader.readU16BE: end of input"
        }
        Int value = readShortBE(_source, _position)
        _position = _position + 2
        return value
    }

    Int readU16LE() {
        if _position + 2 > _limit {
            throw "ByteReader.readU16LE: end of input"
        }
        Int value = readShortLE(_source, _position)
        _position = _position + 2
        return value
    }

    Long readU32BE() {
        if _position + 4 > _limit {
            throw "ByteReader.readU32BE: end of input"
        }
        Long value = readIntBE(_source, _position)
        _position = _position + 4
        return value
    }

    Long readU32LE() {
        if _position + 4 > _limit {
            throw "ByteReader.readU32LE: end of input"
        }
        Long value = readIntLE(_source, _position)
        _position = _position + 4
        return value
    }

    Bytes readBytes(Int count) {
        if count < 0 {
            throw "ByteReader.readBytes: negative count"
        }
        Int end = _position + count
        if end > _limit {
            end = _limit
        }
        Bytes value = slice(_source, _position, end)
        _position = end
        return value
    }

    Result<Bytes, Error> readExact(Int count) {
        if count < 0 {
            throw "ByteReader.readExact: negative count"
        }
        if self.remaining() < count {
            return Err(new BasicError(ErrorKind.DataCorrupted, "end of input"))
        }
        Bytes value = slice(_source, _position, _position + count)
        _position = _position + count
        return Ok(value)
    }

    Bytes readAll() {
        return self.readBytes(self.remaining())
    }
}
```

> `readI16/readI32/readU64/readI64/readF32/readF64/readLine/readUntil/readInto/readUtf8/readHex/tryRead*` 复用上述原语：按宽度检查剩余、调用 `Endian`/编码函数、成功再前进，失败位置不变。
