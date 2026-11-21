# `Bytes`

| 项 | 值 |
| --- | --- |
| 类型 | 运行时库类型 |
| 包 | `xdk.bytes` |
| 稳定性 | `stable` |
| 依赖 | 无（checked 函数由 `xdk.bytes` 顶层提供） |

---

## 1. 定位

可变、引用语义的字节序列。只暴露最小成员：`length/get/set/push`；转换、比较、切片由顶层函数提供。

不做：UTF-8/hex 语义、文件/网络 I/O、线程安全、零拷贝视图。

---

## 2. 设计逻辑

- 字节序列是运行时原语；XDK 不在类上加领域算法，避免运行时依赖 errors。
- 越界是合同错误（panic）；外部索引用 `tryGetByte`/`trySetByte`。
- `==` 是引用身份；值比较用顶层 `equals`/`compare`。
- 切片是副本；`BytesView` 才是视图（X）。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_storage` | 运行时字节缓冲 | 连续字节；长度可变 |
| `_length` | `Int` | 当前字节数 |

不变量：0 ≤ length；索引合法域 `[0, length-1]`；写入取低 8 位；无 OS 资源。

---

## 4. 生命周期

- 由 `Bytes.empty/alloc/fromString/fromUtf8` 创建；无 close；GC 管理内存。
- 可变；非线程安全；跨任务共享需外部同步。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Bytes.empty()` | 无 | 长度 0 | 无 |
| `Bytes.alloc(length)` | length | ≥0；创建 length 个零字节 | 负值 → panic |
| `Bytes.fromString(text)` | text | 任意 String | 无 |
| `Bytes.fromUtf8(text)` | text | 任意 String | 无 |

---

## 6. 字段表

见 §3；字段由运行时内部管理，不暴露裸指针。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `length` | 字节数 | 无 | `Int` | 无 |
| `get` | 读字节 | `Int index` | `Int` 0..255 | 越界 → panic |
| `set` | 写字节 | `Int index, Int value` | `void` | 越界 → panic |
| `push` | 追加 | `Int value` | `void` | 无 |
| `isEmpty` | 是否为空 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 连续字节缓冲；
- 摊还增长；
- 低 8 位截断；
- 引用语义。

---

## 9. 需要的支撑

- 语言：class/运行时类型、Int、Bool；
- 运行时：字节分配、扩容、索引访问；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无 XDK 类依赖；checked/转换函数是 `xdk.bytes` 顶层函数。

---

## 11. 所有权与并发

- 函数参数默认借用；返回 `Bytes` 明确新副本（`copy`/`slice`）。
- `ByteReader/ByteWriter` 借用或转移由各自文档定义。
- 非线程安全；禁止一边读一边写。

---

## 12. 示例与反例

正确：`Bytes bytes = fromUtf8("AB")`；`bytes.get(0)`；`copy(bytes)`。  
反例：把 `Bytes` 当值类型用 `==` 比较；越界 `get` 期望返回 0；读取期间修改源。

---

## 13. 测试/场景义务

空/单字节/多字节；越界 get/set；push 扩容；低 8 位；引用相等；副本独立。

---

## 14. XNull 伪代码

```xnull
class Bytes {
    Int _length
    ByteStorage _storage

    static Bytes empty() {
        Bytes result = new Bytes()
        result._length = 0
        result._storage = allocateStorage(0)
        return result
    }

    static Bytes alloc(Int length) {
        if length < 0 {
            throw "Bytes.alloc: negative length"
        }
        Bytes result = new Bytes()
        result._length = length
        result._storage = allocateStorage(length)
        Int index = 0
        while index < length {
            writeStorage(result._storage, index, 0)
            index = index + 1
        }
        return result
    }

    static Bytes fromString(String text) {
        Bytes result = Bytes.empty()
        Int index = 0
        while index < text.length() {
            result.push(text.charAt(index) as Int)
            index = index + 1
        }
        return result
    }

    Int length() { return _length }

    Bool isEmpty() { return _length == 0 }

    Int get(Int index) {
        if index < 0 || index >= _length {
            throw "Bytes.get: out of range"
        }
        return readStorage(_storage, index)
    }

    void set(Int index, Int value) {
        if index < 0 || index >= _length {
            throw "Bytes.set: out of range"
        }
        writeStorage(_storage, index, value % 256)
    }

    void push(Int value) {
        if _length == storageCapacity(_storage) {
            _storage = growStorage(_storage, _length + 1)
        }
        writeStorage(_storage, _length, value % 256)
        _length = _length + 1
    }
}
```

> `ByteStorage`、`allocateStorage`、`readStorage`、`writeStorage`、`growStorage` 是运行时字节原语，不是 XDK 公共类型。
