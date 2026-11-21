# `BitSet`

| 项 | 值 |
| --- | --- |
| 类型 | `class BitSet` |
| 包 | `xdk.bytes` |
| 稳定性 | `preview` |
| 依赖 | `Bytes` |

---

## 1. 定位

位集合：按索引置位/清位/翻转、基数统计、位运算、序列化。

不做：稀疏超大位图、线程安全、并发位图。

---

## 2. 设计逻辑

- 底层字数组（`Long`）；按需扩展。
- 索引从 0 开始；越界 set/clear/get 是合同错误。
- `length` 是最高置位+1；`size` 是容量位数。
- `and/or/xor/andNot` 返回新位集；`intersects` 只判断。
- `toBytes/fromBytes` 使用小端字序；文档固定，不随平台端序变化。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_words` | `List<Long>` | 位字 |
| `_size` | `Int` | 容量位数 |

不变量：size ≥0；words 长度 = ceil(size/64)；未用高位为 0。

---

## 4. 生命周期

- 构造空；无 close；可增长；非线程安全。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `BitSet()` | 无 | 空 | 无 |
| `BitSet(Int size)` | size | ≥0 | 负值 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `set` | 置位 | `Int index` | `void` | 越界 → panic |
| `set(index,value)` | 置/清 | `Int index, Bool value` | `void` | 越界 → panic |
| `clear` | 清位 | `Int index` | `void` | 越界 → panic |
| `clearAll` | 全清 | 无 | `void` | 无 |
| `get` | 取位 | `Int index` | `Bool` | 越界 → panic |
| `flip` | 翻转 | `Int index` | `void` | 越界 → panic |
| `cardinality` | 置位数 | 无 | `Int` | 无 |
| `length` | 最高位+1 | 无 | `Int` | 无 |
| `size` | 容量 | 无 | `Int` | 无 |
| `isEmpty` | 是否全 0 | 无 | `Bool` | 无 |
| `nextSetBit` | 下一个 1 | `Int from` | `Int` | 无（-1 表示无） |
| `previousSetBit` | 上一个 1 | `Int from` | `Int` | 无（-1 表示无） |
| `and/or/xor/andNot` | 位运算 | `BitSet other` | `BitSet` | null → panic |
| `intersects` | 是否相交 | `BitSet other` | `Bool` | null → panic |
| `toBytes` | 序列化 | 无 | `Bytes` | 无 |
| `fromBytes` | 反序列化 | `Bytes source` | `BitSet` | 长度非 8 倍数 → panic |

---

## 8. 使用的技术

- 字数组位图；
- 位索引/掩码；
- popcount；
- 按位运算；
- 小端序列化。

---

## 9. 需要的支撑

- 语言：class、List、Long、Int、Bool、Bytes；
- 运行时：字节读写；
- 接口：`Bytes`、`Bits.popCountLong`。

---

## 10. 依赖的特性/接口/类

`Bytes`、`Bits.popCountLong`。

---

## 11. 所有权与并发

- 位运算返回新位集；不修改输入。
- `toBytes` 返回副本；`fromBytes` 复制。
- 非线程安全。

---

## 12. 示例与反例

正确：权限位图；`set(3)`/`get(3)`；`and` 求交集。  
反例：负索引；序列化长度非 8 倍数；多任务共享不加锁。

---

## 13. 测试/场景义务

空/单/跨字边界；cardinality；length/size；next/previous；位运算；序列化往返；越界。

---

## 14. XNull 伪代码

```xnull
class BitSet {
    List<Long> _words
    Int _size

    BitSet() {
        _words = []
        _size = 0
    }

    BitSet(Int size) {
        if size < 0 {
            throw "BitSet: negative size"
        }
        _size = size
        _words = []
        Int wordCount = (size + 63) / 64
        Int index = 0
        while index < wordCount {
            _words.push(0)
            index = index + 1
        }
    }

    void ensure(Int index) {
        Int neededSize = index + 1
        if neededSize > _size {
            _size = neededSize
        }
        Int neededWords = (_size + 63) / 64
        while _words.length() < neededWords {
            _words.push(0)
        }
    }

    void set(Int index) {
        if index < 0 {
            throw "BitSet.set: negative index"
        }
        self.ensure(index)
        Int wordIndex = index / 64
        Long bit = 1 << (index % 64)
        _words.set(wordIndex, _words.get(wordIndex) | bit)
    }

    void set(Int index, Bool value) {
        if value {
            self.set(index)
        } else {
            self.clear(index)
        }
    }

    void clear(Int index) {
        if index < 0 {
            throw "BitSet.clear: negative index"
        }
        if index >= _size {
            return
        }
        Int wordIndex = index / 64
        Long bit = 1 << (index % 64)
        _words.set(wordIndex, _words.get(wordIndex) & (0xFFFFFFFFFFFFFFFF - bit))
    }

    void clearAll() {
        Int index = 0
        while index < _words.length() {
            _words.set(index, 0)
            index = index + 1
        }
    }

    Bool get(Int index) {
        if index < 0 || index >= _size {
            throw "BitSet.get: out of range"
        }
        Int wordIndex = index / 64
        Long bit = 1 << (index % 64)
        return (_words.get(wordIndex) & bit) != 0
    }

    void flip(Int index) {
        if index < 0 {
            throw "BitSet.flip: negative index"
        }
        self.ensure(index)
        Int wordIndex = index / 64
        Long bit = 1 << (index % 64)
        _words.set(wordIndex, _words.get(wordIndex) ^ bit)
    }

    Int cardinality() {
        Int count = 0
        Int index = 0
        while index < _words.length() {
            count = count + popCountLong(_words.get(index))
            index = index + 1
        }
        return count
    }

    Int length() {
        Int index = _words.length() - 1
        while index >= 0 {
            Long word = _words.get(index)
            if word != 0 {
                return index * 64 + 64 - leadingZerosLong(word)
            }
            index = index - 1
        }
        return 0
    }

    Int size() { return _size }
    Bool isEmpty() { return self.cardinality() == 0 }

    Int nextSetBit(Int from) {
        Int index = from
        while index < _size {
            if self.get(index) {
                return index
            }
            index = index + 1
        }
        return -1
    }

    Int previousSetBit(Int from) {
        Int index = from
        while index >= 0 {
            if self.get(index) {
                return index
            }
            index = index - 1
        }
        return -1
    }

    BitSet and(BitSet other) {
        if other == null {
            throw "BitSet.and: null"
        }
        Int size = _size
        if other._size < size { size = other._size }
        BitSet result = new BitSet(size)
        Int index = 0
        while index < result._words.length() {
            result._words.set(index, _words.get(index) & other._words.get(index))
            index = index + 1
        }
        return result
    }

    BitSet or(BitSet other) {
        if other == null {
            throw "BitSet.or: null"
        }
        Int size = _size
        if other._size > size { size = other._size }
        BitSet result = new BitSet(size)
        Int index = 0
        while index < result._words.length() {
            Long left = 0
            Long right = 0
            if index < _words.length() { left = _words.get(index) }
            if index < other._words.length() { right = other._words.get(index) }
            result._words.set(index, left | right)
            index = index + 1
        }
        return result
    }

    Bool intersects(BitSet other) {
        if other == null {
            throw "BitSet.intersects: null"
        }
        Int limit = _words.length()
        if other._words.length() < limit { limit = other._words.length() }
        Int index = 0
        while index < limit {
            if (_words.get(index) & other._words.get(index)) != 0 {
                return true
            }
            index = index + 1
        }
        return false
    }

    Bytes toBytes() {
        Bytes result = Bytes.empty()
        Int index = 0
        while index < _words.length() {
            Long word = _words.get(index)
            Int shift = 0
            while shift <= 56 {
                result.push(((word >> shift) % 256) as Int)
                shift = shift + 8
            }
            index = index + 1
        }
        return result
    }

    static BitSet fromBytes(Bytes source) {
        if source.length() % 8 != 0 {
            throw "BitSet.fromBytes: length not multiple of 8"
        }
        BitSet result = new BitSet(source.length() * 8)
        Int index = 0
        while index < source.length() / 8 {
            Long word = 0
            Int shift = 0
            while shift <= 56 {
                word = word | ((source.get(index * 8 + shift / 8) as Long) << shift)
                shift = shift + 8
            }
            result._words.set(index, word)
            index = index + 1
        }
        return result
    }
}
```
