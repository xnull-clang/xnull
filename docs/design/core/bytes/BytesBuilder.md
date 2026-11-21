# `BytesBuilder`

| 项 | 值 |
| --- | --- |
| 类型 | `class BytesBuilder` |
| 包 | `xdk.bytes` |
| 稳定性 | `preview` |
| 依赖 | `Bytes` |

---

## 1. 定位

可增长字节构建器：追加字节/字节块/UTF-8/hex/整数/浮点/布尔，最后 `build` 或 `take`。

不做：定位写（用 `ByteBuffer`）、文件/网络、线程安全。

---

## 2. 设计逻辑

- 只追加，语义简单；`build` 返回副本，`take` 转移内部序列并清空。
- 容量只增不减；`clear` 长度归零，容量保留。
- 整数写入统一大端；需要小端用 `ByteWriter`/`Endian`。
- 负 count/非法容量是合同错误。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_buffer` | `Bytes` | 当前内容 |
| `_capacity` | `Int` | 预留容量 ≥ length |

不变量：capacity ≥ length；内容连续；写入只追加；非线程安全。

---

## 4. 生命周期

- 构造空；无 close；`build`/`take` 后仍可继续追加（`take` 清空）。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `BytesBuilder()` | 无 | 初始容量 0 | 无 |
| `BytesBuilder(Int initialCapacity)` | initialCapacity | ≥0 | 负值 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `appendByte` | 追加 1 字节 | `Int value` | `BytesBuilder` | 无 |
| `append` | 追加字节块 | `Bytes value` | `BytesBuilder` | null → panic |
| `appendUtf8` | 追加 UTF-8 | `String text` | `BytesBuilder` | 无 |
| `appendHex` | 追加 hex | `String hexadecimal` | `BytesBuilder` | 非法/奇数 → panic |
| `appendInt` | 追加 4 字节 BE | `Int value` | `BytesBuilder` | 无 |
| `appendLong` | 追加 8 字节 BE | `Long value` | `BytesBuilder` | 无 |
| `appendDouble` | 追加 8 字节位模式 | `Double value` | `BytesBuilder` | 无 |
| `appendBool` | 追加 0/1 | `Bool value` | `BytesBuilder` | 无 |
| `insert` | 定位插入 | `Int index, Bytes value` | `BytesBuilder` | 越界 → panic |
| `length` | 当前长度 | 无 | `Int` | 无 |
| `capacity` | 容量 | 无 | `Int` | 无 |
| `reserve` | 预留 | `Int minimumCapacity` | `void` | 负值 → panic |
| `clear` | 清空 | 无 | `void` | 无 |
| `build` | 内容副本 | 无 | `Bytes` | 无 |
| `take` | 转移并清空 | 无 | `Bytes` | 无 |

---

## 8. 使用的技术

- 可增长缓冲；
- UTF-8/hex 编码；
- 大端整数；
- 浮点位模式；
- 副本/转移。

---

## 9. 需要的支撑

- 语言：class、Bytes、String、Int、Long、Double、Bool；
- 运行时：字节分配/扩容；
- 接口：`fromUtf8`、`fromHex`、`copy`、`slice`。

---

## 10. 依赖的特性/接口/类

`Bytes`、`fromUtf8`、`fromHex`、`copy`、`slice`。

---

## 11. 所有权与并发

- `append` 借用输入；不保留引用。
- `build` 返回副本；`take` 转移内部序列。
- 非线程安全。

---

## 12. 示例与反例

正确：`new BytesBuilder().appendHex("00ff").appendInt(7).build()`。  
反例：负容量；`take` 后继续使用旧引用期待内容；跨任务共享不加锁。

---

## 13. 测试/场景义务

空/追加/扩容；UTF-8/hex；Int/Long/Double/Bool；insert 越界；build 副本；take 转移；clear 容量。

---

## 14. XNull 伪代码

```xnull
class BytesBuilder {
    Bytes _buffer
    Int _capacity

    BytesBuilder() {
        _buffer = Bytes.alloc(0)
        _capacity = 0
    }

    BytesBuilder(Int initialCapacity) {
        if initialCapacity < 0 {
            throw "BytesBuilder: negative capacity"
        }
        _buffer = Bytes.alloc(0)
        _capacity = initialCapacity
        self.reserve(initialCapacity)
    }

    BytesBuilder appendByte(Int value) {
        _buffer.push(value)
        return self
    }

    BytesBuilder append(Bytes value) {
        if value == null {
            throw "BytesBuilder.append: null"
        }
        Int index = 0
        while index < value.length() {
            _buffer.push(value.get(index))
            index = index + 1
        }
        return self
    }

    BytesBuilder appendUtf8(String text) {
        return self.append(fromUtf8(text))
    }

    BytesBuilder appendHex(String hexadecimal) {
        return self.append(fromHex(hexadecimal))
    }

    BytesBuilder appendInt(Int value) {
        self.appendByte((value / 16777216) % 256)
        self.appendByte((value / 65536) % 256)
        self.appendByte((value / 256) % 256)
        self.appendByte(value % 256)
        return self
    }

    BytesBuilder appendLong(Long value) {
        Int shift = 56
        while shift >= 0 {
            self.appendByte(((value >> shift) % 256) as Int)
            shift = shift - 8
        }
        return self
    }

    BytesBuilder appendDouble(Double value) {
        return self.appendLong(doubleToBits(value))
    }

    BytesBuilder appendBool(Bool value) {
        if value {
            self.appendByte(1)
        } else {
            self.appendByte(0)
        }
        return self
    }

    BytesBuilder insert(Int index, Bytes value) {
        if index < 0 || index > _buffer.length() {
            throw "BytesBuilder.insert: out of range"
        }
        Bytes result = Bytes.empty()
        Int position = 0
        while position < index {
            result.push(_buffer.get(position))
            position = position + 1
        }
        position = 0
        while position < value.length() {
            result.push(value.get(position))
            position = position + 1
        }
        position = index
        while position < _buffer.length() {
            result.push(_buffer.get(position))
            position = position + 1
        }
        _buffer = result
        return self
    }

    Int length() { return _buffer.length() }

    Int capacity() {
        if _buffer.length() > _capacity {
            return _buffer.length()
        }
        return _capacity
    }

    void reserve(Int minimumCapacity) {
        if minimumCapacity < 0 {
            throw "BytesBuilder.reserve: negative"
        }
        if minimumCapacity > _capacity {
            _capacity = minimumCapacity
        }
    }

    void clear() {
        _buffer = Bytes.alloc(0)
    }

    Bytes build() {
        return copy(_buffer)
    }

    Bytes take() {
        Bytes result = _buffer
        _buffer = Bytes.alloc(0)
        return result
    }
}
```
