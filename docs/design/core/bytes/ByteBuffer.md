# `ByteBuffer`

| 项 | 值 |
| --- | --- |
| 类型 | `class ByteBuffer` |
| 包 | `xdk.bytes` |
| 稳定性 | `preview` |
| 依赖 | `Bytes`、`ByteOrder` |

---

## 1. 定位

带 `position/limit/capacity` 的定位缓冲，支持读写切换、mark/reset、flip/compact、端序读写和视图。

不做：文件/网络、线程安全、裸内存映射。

---

## 2. 设计逻辑

- 采用 Java NIO 式状态：`0 ≤ mark ≤ position ≤ limit ≤ capacity`。
- `flip` 切读：limit=position，position=0。
- `compact` 把未读数据移到开头，position=remaining，limit=capacity。
- 视图 `slice/duplicate` 共享数据；`asReadOnly` 禁止写。
- 端序是缓冲属性，默认大端。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_data` | `Bytes` | 底层数据 |
| `_capacity` | `Int` | 总容量 |
| `_position` | `Int` | 当前读写位置 |
| `_limit` | `Int` | 读写上限 |
| `_mark` | `Int` | 标记位置；-1 无标记 |
| `_order` | `ByteOrder` | 端序 |
| `_readOnly` | `Bool` | 是否只读 |

不变量：0 ≤ mark ≤ position ≤ limit ≤ capacity；readOnly 时写操作 panic。

---

## 4. 生命周期

- 构造空缓冲；无 close；视图共享底层数据，生命周期由引用管理。
- 非线程安全。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ByteBuffer()` | 无 | 容量 0 | 无 |
| `ByteBuffer(Int capacity)` | capacity | ≥0 | 负值 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

### 7.1 状态

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `capacity` | 总容量 | 无 | `Int` | 无 |
| `position` | 当前位 | 无 | `Int` | 无 |
| `position(newPosition)` | 设置位 | `Int` | `ByteBuffer` | 越界 → panic |
| `limit` | 上限 | 无 | `Int` | 无 |
| `limit(newLimit)` | 设置上限 | `Int` | `ByteBuffer` | 越界 → panic |
| `remaining` | 剩余 | 无 | `Int` | 无 |
| `hasRemaining` | 是否剩余 | 无 | `Bool` | 无 |
| `mark` | 标记 | 无 | `ByteBuffer` | 无 |
| `reset` | 回标记 | 无 | `ByteBuffer` | 无标记 → panic |
| `clear` | 清空 | 无 | `ByteBuffer` | 无 |
| `flip` | 切读 | 无 | `ByteBuffer` | 无 |
| `rewind` | 回开头 | 无 | `ByteBuffer` | 无 |
| `compact` | 压缩未读 | 无 | `ByteBuffer` | 只读 → panic |
| `order` | 端序 | 无 | `ByteOrder` | 无 |
| `order(newOrder)` | 设置端序 | `ByteOrder` | `ByteBuffer` | 无 |

### 7.2 读

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `get` | 读 1 字节 | 无 | `Int` | 不足 → panic |
| `get(index)` | 定位读 | `Int index` | `Int` | 越界 → panic |
| `getU8/I8` | 1 字节 | 无 | `Int` | 不足 → panic |
| `getU16/I16` | 2 字节 | 无 | `Int` | 不足 → panic |
| `getU32/I32` | 4 字节 | 无 | `Long`/`Int` | 不足 → panic |
| `getU64/I64` | 8 字节 | 无 | `Long` | 不足 → panic |
| `getF32/F64` | 浮点 | 无 | `Double` | 不足 → panic |
| `getBytes` | 读字节块 | `Int count` | `Bytes` | 不足 → panic |

### 7.3 写

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `put` | 写 1 字节 | `Int value` | `ByteBuffer` | 满/只读 → panic |
| `put(index,value)` | 定位写 | `Int index, Int value` | `ByteBuffer` | 越界/只读 → panic |
| `putU8/I8/U16/I16/U32/I32/U64/I64/F32/F64` | 定长写 | 值 | `ByteBuffer` | 满/只读 → panic |
| `putBytes` | 写字节块 | `Bytes value` | `ByteBuffer` | 满/只读 → panic |

### 7.4 视图

`slice()`、`duplicate()`、`asReadOnly()`、`array()`、`hasArray()`。

---

## 8. 使用的技术

- NIO 状态机；
- 端序读写；
- 共享视图；
- 只读标记；
- 位模式浮点。

---

## 9. 需要的支撑

- 语言：class、Bytes、Int、Long、Double、Bool；
- 运行时：字节分配/读写；
- 接口：`Bytes`、`ByteOrder`。

---

## 10. 依赖的特性/接口/类

`Bytes`、`ByteOrder`、`Endian` 读写函数。

---

## 11. 所有权与并发

- `slice/duplicate` 共享底层数据；修改互相可见。
- `getBytes` 返回副本；`slice()` 返回共享数据的缓冲视图。
- 非线程安全；视图共享需外部同步。

---

## 12. 示例与反例

正确：写后 `flip` 再读；`compact` 保留未读；`slice` 共享数据。  
反例：写满继续 put；只读缓冲写；`reset` 前未 mark；把 `getBytes` 当视图。

---

## 13. 测试/场景义务

状态边界；flip/clear/rewind/compact；读写各宽度；端序；视图共享；只读；越界。

---

## 14. XNull 伪代码

```xnull
class ByteBuffer {
    Bytes _data
    Int _capacity
    Int _position
    Int _limit
    Int _mark
    ByteOrder _order
    Bool _readOnly

    ByteBuffer() {
        _data = Bytes.alloc(0)
        _capacity = 0
        _position = 0
        _limit = 0
        _mark = -1
        _order = ByteOrder.BigEndian
        _readOnly = false
    }

    ByteBuffer(Int capacity) {
        if capacity < 0 {
            throw "ByteBuffer: negative capacity"
        }
        _data = Bytes.alloc(capacity)
        _capacity = capacity
        _position = 0
        _limit = capacity
        _mark = -1
        _order = ByteOrder.BigEndian
        _readOnly = false
    }

    Int capacity() { return _capacity }
    Int position() { return _position }
    Int limit() { return _limit }
    Int remaining() { return _limit - _position }
    Bool hasRemaining() { return _position < _limit }
    ByteOrder order() { return _order }

    ByteBuffer position(Int newPosition) {
        if newPosition < 0 || newPosition > _limit {
            throw "ByteBuffer.position: out of range"
        }
        _position = newPosition
        if _mark > _position {
            _mark = -1
        }
        return self
    }

    ByteBuffer limit(Int newLimit) {
        if newLimit < 0 || newLimit > _capacity {
            throw "ByteBuffer.limit: out of range"
        }
        _limit = newLimit
        if _position > _limit {
            _position = _limit
        }
        if _mark > _limit {
            _mark = -1
        }
        return self
    }

    ByteBuffer mark() {
        _mark = _position
        return self
    }

    ByteBuffer reset() {
        if _mark < 0 {
            throw "ByteBuffer.reset: no mark"
        }
        _position = _mark
        return self
    }

    ByteBuffer clear() {
        _position = 0
        _limit = _capacity
        _mark = -1
        return self
    }

    ByteBuffer flip() {
        _limit = _position
        _position = 0
        _mark = -1
        return self
    }

    ByteBuffer rewind() {
        _position = 0
        _mark = -1
        return self
    }

    ByteBuffer compact() {
        if _readOnly {
            throw "ByteBuffer.compact: read only"
        }
        Int remaining = self.remaining()
        Int index = 0
        while index < remaining {
            _data.set(index, _data.get(_position + index))
            index = index + 1
        }
        _position = remaining
        _limit = _capacity
        _mark = -1
        return self
    }

    ByteBuffer order(ByteOrder newOrder) {
        _order = newOrder
        return self
    }

    Int get() {
        if _position >= _limit {
            throw "ByteBuffer.get: underflow"
        }
        Int value = _data.get(_position)
        _position = _position + 1
        return value
    }

    ByteBuffer put(Int value) {
        if _readOnly {
            throw "ByteBuffer.put: read only"
        }
        if _position >= _limit {
            throw "ByteBuffer.put: overflow"
        }
        _data.set(_position, value)
        _position = _position + 1
        return self
    }

    Bytes getBytes(Int count) {
        if count < 0 || self.remaining() < count {
            throw "ByteBuffer.getBytes: underflow"
        }
        Bytes result = slice(_data, _position, _position + count)
        _position = _position + count
        return result
    }

    ByteBuffer putBytes(Bytes value) {
        if _readOnly {
            throw "ByteBuffer.putBytes: read only"
        }
        if self.remaining() < value.length() {
            throw "ByteBuffer.putBytes: overflow"
        }
        Int index = 0
        while index < value.length() {
            self.put(value.get(index))
            index = index + 1
        }
        return self
    }

    ByteBuffer slice() {
        ByteBuffer result = new ByteBuffer(0)
        result._data = _data
        result._capacity = _capacity
        result._position = _position
        result._limit = _limit
        result._mark = _mark
        result._order = _order
        result._readOnly = _readOnly
        return result
    }

    ByteBuffer duplicate() {
        return self.slice()
    }

    ByteBuffer asReadOnly() {
        ByteBuffer result = self.slice()
        result._readOnly = true
        return result
    }

    Bool hasArray() { return true }
    Bytes array() { return _data }
}
```

> `getU16/I16/getU32/...` 复用 `getBytes` + `Endian` 读函数；`putU16/...` 复用 `Endian` 写函数 + `putBytes`。端序由 `_order` 决定。
