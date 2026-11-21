# `ByteWriter`

| 项 | 值 |
| --- | --- |
| 类型 | `class ByteWriter` |
| 包 | `xdk.bytes` |
| 稳定性 | `stable` |
| 依赖 | `Bytes`、`Endian` |

---

## 1. 定位

顺序字节写入器：追加字节/字节块/定长整数/浮点/文本/hex/零填充，最后 `toBytes` 或 `takeBytes`。

不做：定位写（用 `ByteBuffer`）、文件/网络、线程安全。

---

## 2. 设计逻辑

- 只追加；`toBytes` 返回副本，`takeBytes` 转移并清空。
- 定长整数默认大端；需要小端用 `writeU16LE` 等显式方法。
- 写入取低 8 位；越宽度的值按位模式写入。
- `flush` 对内存 writer 是 no-op。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_buffer` | `Bytes` | 当前内容 |

不变量：长度 = 已写字节数；只追加；非线程安全。

---

## 4. 生命周期

- 构造空；无 close；`takeBytes` 后 writer 清空，可继续写。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ByteWriter()` | 无 | 初始空 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `length` | 当前长度 | 无 | `Int` | 无 |
| `capacity` | 容量 | 无 | `Int` | 无 |
| `writeU8` | 写 1 字节 | `Int value` | `void` | 无 |
| `writeI8` | 写 1 有符号 | `Int value` | `void` | 无 |
| `writeU16BE/LE` | 写 2 | `Int value` | `void` | 越界 → panic |
| `writeI16BE/LE` | 写 2 有符号 | `Int value` | `void` | 越界 → panic |
| `writeU32BE/LE` | 写 4 | `Long value` | `void` | 越界 → panic |
| `writeI32BE/LE` | 写 4 有符号 | `Int value` | `void` | 无 |
| `writeU64BE/LE` | 写 8 | `Long value` | `void` | 无 |
| `writeI64BE/LE` | 写 8 | `Long value` | `void` | 无 |
| `writeF32BE/LE` | 写 float | `Double value` | `void` | 无 |
| `writeF64BE/LE` | 写 double | `Double value` | `void` | 无 |
| `writeBytes` | 写字节块 | `Bytes source` | `void` | null → panic |
| `writeUtf8` | 写 UTF-8 | `String text` | `void` | 无 |
| `writeHex` | 写 hex | `String hexadecimal` | `void` | 非法 → panic |
| `writeLine` | 写文本+换行 | `String text` | `void` | 无 |
| `writeZeros` | 写零 | `Int count` | `void` | 负值 → panic |
| `toBytes` | 副本 | 无 | `Bytes` | 无 |
| `takeBytes` | 转移并清空 | 无 | `Bytes` | 无 |
| `clear` | 清空 | 无 | `void` | 无 |
| `reserve` | 预留 | `Int minimumCapacity` | `void` | 负值 → panic |
| `flush` | no-op | 无 | `void` | 无 |

---

## 8. 使用的技术

- 追加缓冲；
- 端序写；
- 浮点位模式；
- 副本/转移；
- 零填充。

---

## 9. 需要的支撑

- 语言：class、Bytes、Int、Long、Double、String、Bool；
- 运行时：字节分配/追加；
- 接口：`Bytes`、`Endian`、`fromUtf8`、`fromHex`。

---

## 10. 依赖的特性/接口/类

`Bytes`、`Endian`、`fromUtf8`、`fromHex`、`copy`。

---

## 11. 所有权与并发

- `writeBytes` 借用源；不保留引用。
- `toBytes` 副本；`takeBytes` 转移。
- 非线程安全。

---

## 12. 示例与反例

正确：`writeU16BE(2)` + `writeBytes(payload)` + `toBytes()`。  
反例：`writeU16BE(65536)`；`takeBytes` 后继续用旧引用；跨任务共享不加锁。

---

## 13. 测试/场景义务

各宽度 BE/LE；边界值；文本/hex；零填充；副本/转移；clear/reserve；null。

---

## 14. XNull 伪代码

```xnull
class ByteWriter {
    Bytes _buffer

    ByteWriter() {
        _buffer = Bytes.alloc(0)
    }

    Int length() { return _buffer.length() }
    Int capacity() { return _buffer.length() }

    void writeU8(Int value) {
        _buffer.push(value % 256)
    }

    void writeI8(Int value) {
        self.writeU8(value)
    }

    void writeU16BE(Int value) {
        if value < 0 || value > 65535 {
            throw "ByteWriter.writeU16BE: out of range"
        }
        self.writeBytes(u16BE(value))
    }

    void writeU16LE(Int value) {
        if value < 0 || value > 65535 {
            throw "ByteWriter.writeU16LE: out of range"
        }
        self.writeBytes(u16LE(value))
    }

    void writeU32BE(Long value) {
        if value < 0 || value > 4294967295 {
            throw "ByteWriter.writeU32BE: out of range"
        }
        self.writeBytes(u32BE(value))
    }

    void writeU32LE(Long value) {
        if value < 0 || value > 4294967295 {
            throw "ByteWriter.writeU32LE: out of range"
        }
        self.writeBytes(u32LE(value))
    }

    void writeU64BE(Long value) {
        Int shift = 56
        while shift >= 0 {
            self.writeU8(((value >> shift) % 256) as Int)
            shift = shift - 8
        }
    }

    void writeU64LE(Long value) {
        Int shift = 0
        while shift <= 56 {
            self.writeU8(((value >> shift) % 256) as Int)
            shift = shift + 8
        }
    }

    void writeBytes(Bytes source) {
        if source == null {
            throw "ByteWriter.writeBytes: null"
        }
        Int index = 0
        while index < source.length() {
            _buffer.push(source.get(index))
            index = index + 1
        }
    }

    void writeUtf8(String text) {
        self.writeBytes(fromUtf8(text))
    }

    void writeHex(String hexadecimal) {
        self.writeBytes(fromHex(hexadecimal))
    }

    void writeLine(String text) {
        self.writeUtf8(text)
        self.writeU8(10)
    }

    void writeZeros(Int count) {
        if count < 0 {
            throw "ByteWriter.writeZeros: negative"
        }
        Int index = 0
        while index < count {
            self.writeU8(0)
            index = index + 1
        }
    }

    Bytes toBytes() {
        return copy(_buffer)
    }

    Bytes takeBytes() {
        Bytes result = _buffer
        _buffer = Bytes.alloc(0)
        return result
    }

    void clear() {
        _buffer = Bytes.alloc(0)
    }

    void reserve(Int minimumCapacity) {
        if minimumCapacity < 0 {
            throw "ByteWriter.reserve: negative"
        }
    }

    void flush() {
    }
}
```
