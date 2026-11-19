# xdk.bytes —— T0 核心包详细设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.bytes` |
| 层级 | T0 |
| 稳定性 | 核心 `stable`（T0-K）；扩展 `preview`（T0-X） |
| 依赖 | `xdk.errors` |
| 被依赖 | text、io、fs、sys、log |
| 对应源码 | `src/xdk/core/bytes/Bytes.x`（当前单文件；目标拆分见 §2） |
| 阶段 | T0-04（B1–B4） |

---

## 1. 能力声明

| 能力 | 说明 | 承载 |
| --- | --- | --- |
| C1 字节序列 | 可变、按索引访问的字节数组 | `Bytes` |
| C2 编码转换 | UTF-8 / hex 与文本互转 | `fromUtf8`、`toUtf8`、`fromHex`、`toHex` |
| C3 切片与比较 | 子序列、字典序比较、相等 | `slice`、`compare`、`equals` |
| C4 顺序读 | 带游标的读取与越界检查 | `ByteReader` |
| C5 顺序写 | 追加写、定长整数写 | `ByteWriter` |
| C6 可增长缓冲 | 构造/拼接/清空 | `ByteBuffer`、`BytesBuilder`（X） |
| C7 位操作 | 与/或/异或/移位/位计数 | `Bits` |
| C8 端序 | u16/u32/u64 与大小端读写 | `Endian` |

**非目标**：不做 base64/压缩/加密（T1 codec/crypto）、不做文件/网络 I/O、
不做零拷贝 FFI 裸指针暴露、不做线程安全容器。

---

## 2. 文件与类型

| 文件 | 类型/函数 | 层级 |
| --- | --- | --- |
| `Bytes.x` | `Bytes` 顶层函数、`equals`、`copy` | K |
| `ByteReader.x` | `ByteReader` | K |
| `ByteWriter.x` | `ByteWriter` | K |
| `Endian.x` | u16/u32/u64、read/write at offset | K |
| `Bits.x` | 位运算、popCount 等 | K |
| `ByteBuffer.x` | `ByteBuffer` | X |
| `Cursor.x` | `Cursor`（只读定位） | X |
| `BytesBuilder.x` | `BytesBuilder`（批量构建） | X |

> 迁移：当前所有类型在 `Bytes.x`；T0-04 先拆分文件，再补契约，不改符号名。

---

## 3. `Bytes`（内建字节序列）

### 3.1 表示与不变量

- `Bytes` 是**可变、引用语义**的字节序列；`length()` 以字节计。
- 任意时刻 `0 <= length`；索引合法域 `[0, length-1]`。
- `Bytes` 不持有 OS 资源，无 `close()`。
- `Bytes` 的 `==` 不定义为字节相等；值比较必须用 `equals(a,b)` 或
  `compare(a,b)==0`（避免与引用相等混淆）。

### 3.2 所有权与别名

| 场景 | 契约 |
| --- | --- |
| 函数参数 `Bytes` | 默认**借用**；函数不得保留引用，除非名称/文档声明 |
| 返回 `Bytes` | 返回新序列（`returnOwned`）；调用方拥有 |
| `slice` | 返回**副本**（不是视图）；修改副本不影响原序列 |
| `ByteReader(Bytes)` | 读取器持有借用；读取期间调用方不得修改源 |
| `ByteWriter.toBytes()` | 返回副本；`takeBytes()` 转移内部序列（X） |
| 跨任务共享 | 非线程安全；需外部同步，且禁止一边读一边写 |

### 3.3 顶层函数契约

| 函数 | 签名 | 前置 | 后置 | 失败 | 复杂度 |
| --- | --- | --- | --- | --- | --- |
| `fromUtf8` | `Bytes fromUtf8(String)` | 无 | UTF-8 编码；非法码点按语言规则替换 | 无 | O(n) |
| `toUtf8` | `String toUtf8(Bytes)` | 无 | 非法字节替换为 U+FFFD（固定） | 无 | O(n) |
| `fromHex` | `Bytes fromHex(String)` | 无 | 小写/大写 hex；奇数长度丢弃末尾半字节 | 无 | O(n) |
| `fromHexChecked` | `Result<Bytes, Error> fromHexChecked(String)` | 无 | 严格：非法字符/奇数长度 → `InvalidArgument` | `InvalidArgument` | O(n) |
| `toHex` | `String toHex(Bytes)` | 无 | 小写 hex，长度 = 2×字节数 | 无 | O(n) |
| `byteLength` | `Int byteLength(Bytes)` | 无 | 返回字节数 | 无 | O(1) |
| `isEmpty` | `Bool isEmpty(Bytes)` | 无 | length == 0 | 无 | O(1) |
| `concatBytes` | `Bytes concatBytes(Bytes, Bytes)` | 无 | 新序列 = a + b；不修改入参 | 无 | O(a+b) |
| `copy` | `Bytes copy(Bytes)` | 无 | 返回独立副本 | 无 | O(n) |
| `slice` | `Bytes slice(Bytes, Int start, Int end)` | 无 | 钳制到 `[0,len]`；`start>end` 归一为空 | 无 | O(n) |
| `sliceChecked` | `Result<Bytes, Error> sliceChecked(Bytes, Int start, Int end)` | 无 | 严格范围检查 | `InvalidArgument` | O(n) |
| `equals` | `Bool equals(Bytes a, Bytes b)` | 无 | 长度与逐字节相等 | 无 | O(n) |
| `compare` | `Int compare(Bytes a, Bytes b)` | 无 | 字典序：<0/0/>0 | 无 | O(n) |

### 3.4 内建方法契约（语言/runtime 提供）

| 方法 | 签名 | 前置 | 后置 | 越界行为 |
| --- | --- | --- | --- | --- |
| `length` | `Int length()` | 无 | 字节数 | 无 |
| `get` | `Int get(Int i)` | `0 <= i < len` | 返回 0..255 | 合同错误（fatal）；严格用 `tryGet` |
| `set` | `Void set(Int i, Int v)` | `0 <= i < len`；v 取低 8 位 | 修改该字节 | 合同错误 |
| `push` | `Void push(Int v)` | 无 | 追加低 8 位；容量按摊还增长 | 无 |
| `tryGet` | `Result<Int, Error> tryGet(Int i)` | 无 | 越界 → `InvalidArgument` | 返回 Err |
| `trySet` | `Result<Unit, Error> trySet(Int i, Int v)` | 无 | 越界 → `InvalidArgument` | 返回 Err |

> 设计原则：索引越界是调用方 bug，内建 `get/set` 可以 fatal；但只要输入来自
> 外部/不可信数据，必须使用 `tryGet/trySet` 或先检查 `length`。

### 3.5 示例与反例

```text
Bytes b = Bytes.fromUtf8("AB")
print(b.length())          // 2
b.set(0, 65)
print(toUtf8(b))           // AB
Bytes c = slice(b, 0, 1)   // 副本
c.set(0, 67)
print(toUtf8(b))           // AB（原序列未变）
```

反例：

- 把 `Bytes` 当值类型直接 `==` 比较；
- `ByteReader` 读取期间对源 `Bytes` 做 `set/push`；
- 用 `fromHex` 解析外部输入而不检查错误（应使用 `fromHexChecked`）。

---

## 4. `ByteReader`（class）

### 4.1 能力与表示

顺序读取一个 `Bytes`，维护只前进的游标；用于协议解析。

```text
class ByteReader {
    Bytes data        // 借用
    Int position
    ByteReader(Bytes source)
    Int remaining()
    Bool hasRemaining()
    Int position()
    Result<Unit, Error> seek(Int offset)
    Int readU8()
    Result<Int, Error> readU8Checked()
    Int shortBE() / shortLE()
    Int intBE() / intLE()
    Long longBE() / longLE()
    Bytes readBytes(Int count)
    Result<Bytes, Error> readExact(Int count)
    Result<List<Int>, Error> readU8s(Int count)   // X
}
```

### 4.2 不变量与所有权

- `0 <= position <= data.length()`。
- 读取器持有 `data` 借用；调用方在读取期间不得修改源。
- 读取器无资源，无 `close()`；不复位，需要重置则新建。
- 线程安全：否。

### 4.3 方法契约

| 方法 | 前置 | 后置 | 失败 | 复杂度 |
| --- | --- | --- | --- | --- |
| `remaining` | 无 | `len - position` | 无 | O(1) |
| `hasRemaining` | 无 | position < len | 无 | O(1) |
| `seek(offset)` | 无 | `offset` 钳制到 `[0,len]`？**不**：严格，越界 Err | `InvalidArgument` | O(1) |
| `readU8` | 无 | 有字节则返回并前进；否则返回 0 且不前进 | 无（宽松） | O(1) |
| `readU8Checked` | 无 | 无字节 → Err | `DataCorrupted` | O(1) |
| `shortBE/LE` | 至少 2 字节 | 读 2 字节并前进 2 | 不足时宽松返回 0 或按实现；**严格版 `readShort` 待加** | O(1) |
| `intBE/LE` | 至少 4 字节 | 读 4 字节并前进 4 | 同上 | O(1) |
| `longBE/LE` | 至少 8 字节 | 读 8 字节并前进 8 | 同上 | O(1) |
| `readBytes(count)` | count ≥ 0 | 读到末尾；返回副本；前进实际读取数 | count<0 → 空 | O(count) |
| `readExact(count)` | count ≥ 0 | 恰好 count 字节；不足 → Err 且 position 不变 | `DataCorrupted` | O(count) |

> 宽松方法保留是为了兼容现有场景；**新协议解析代码必须使用 `Checked/Exact`**。
> 严格版在 T0-04 补齐后，宽松版标为 legacy 兼容。

### 4.4 示例

```text
Bytes frame = Bytes.fromHex("00010203")
ByteReader r = new ByteReader(frame)
Int magic = r.shortBE()
Result<Bytes, Error> body = r.readExact(2)
if body.isErr() { ... }
```

---

## 5. `ByteWriter`（class）

### 5.1 能力与表示

构建字节序列；内部拥有一个 `Bytes`，写入只追加。

```text
class ByteWriter {
    Bytes data
    ByteWriter()
    Int length()
    Bytes toBytes()          // 副本
    Bytes takeBytes()        // X：转移内部序列，writer 清空
    Void writeU8(Int)
    Void writeBytes(Bytes)
    Void writeU16BE/LE(Int)
    Void writeU32BE/LE(Int)
    Void writeU64BE/LE(Long) // X
    Void clear()
}
```

### 5.2 契约

| 方法 | 前置 | 后置 | 失败 | 复杂度 |
| --- | --- | --- | --- | --- |
| `writeU8(v)` | 无 | 追加 `v & 0xFF`；负数按二补码低 8 位 | 无 | 摊还 O(1) |
| `writeBytes(b)` | b 非 null | 追加副本；不保留 b 引用 | 无 | O(n) |
| `writeU16/32/64` | 无 | 按指定端序追加 | 无 | O(1) |
| `toBytes()` | 无 | 返回当前内容副本 | 无 | O(n) |
| `takeBytes()` | 无 | 返回内部序列所有权；writer 长度归零 | 无 | O(1) |
| `clear()` | 无 | 长度归零；容量保留 | 无 | O(1) |

- 线程安全：否。
- 所有权：`writeBytes` 借用；`toBytes` 返回新副本；`takeBytes` 转移。

---

## 6. `ByteBuffer`（class，T0-X）

### 6.1 能力

可增长缓冲，支持追加与（X）定位读写；对齐 Java NIO/Go `bytes.Buffer` 的
常用子集，但不暴露裸内存。

```text
class ByteBuffer {
    ByteBuffer()
    ByteBuffer(Bytes initial)
    Int length()
    Int capacity()
    Bytes toBytes()          // 副本
    Void push(Int)
    Void append(Bytes)
    Result<Unit, Error> put(Int index, Int value)
    Result<Int, Error> get(Int index)
    Void clear()
    Void reserve(Int minCapacity)
}
```

### 6.2 契约

| 方法 | 前置 | 后置 | 失败 | 复杂度 |
| --- | --- | --- | --- | --- |
| `push(v)` | 无 | 追加低 8 位 | 无 | 摊还 O(1) |
| `append(b)` | b 非 null | 追加副本 | 无 | O(n) |
| `put(i,v)` | 无 | 越界 → Err；合法则写入 | `InvalidArgument` | O(1) |
| `get(i)` | 无 | 越界 → Err | `InvalidArgument` | O(1) |
| `reserve(n)` | n ≥ 0 | 容量至少 n；不清空内容 | `InvalidArgument` | O(n) |
| `clear()` | 无 | 长度 0；容量保留 | 无 | O(1) |

> `position/limit/flip/compact` 是 T0-X 的后续扩展；在加入前不承诺 NIO 全套语义。

---

## 7. `Bits`（函数）

| 函数 | 签名 | 前置 | 后置 | 失败 |
| --- | --- | --- | --- | --- |
| `bitAnd` | `Int bitAnd(Int,Int)` | 无 | 按位与 | 无 |
| `bitOr` | `Int bitOr(Int,Int)` | 无 | 按位或 | 无 |
| `bitXor` | `Int bitXor(Int,Int)` | 无 | 按位异或 | 无 |
| `bitNot` | `Int bitNot(Int)` | 无 | 按位取反 | 无 |
| `shiftLeft` | `Int shiftLeft(Int,Int)` | `0 <= bits < 64` | 左移；越界为合同错误 | fatal/`InvalidArgument`（严格版） |
| `shiftRight` | `Int shiftRight(Int,Int)` | 同上 | 算术右移 | 同上 |
| `popCount` | `Int popCount(Int)` | 无 | 1 的个数 | 无 |
| `leadingZeros` | `Int leadingZeros(Int)` | 无 | 前导 0 数；0 → 64 | 无 |
| `trailingZeros` | `Int trailingZeros(Int)` | 无 | 末尾 0 数；0 → 64 | 无 |

- 位操作只对 64 位有符号 `Int` 定义；不隐式提升到 `Long`。
- 移位量来自外部时，调用方必须先校验；严格版返回 `Result`。

---

## 8. `Endian`（函数）

| 函数 | 签名 | 前置 | 后置 |
| --- | --- | --- | --- |
| `u16BE/LE` | `Bytes u16BE(Int v)` | `0 <= v <= 0xFFFF` | 2 字节 |
| `u32BE/LE` | `Bytes u32BE(Int v)` | `0 <= v <= 0xFFFFFFFF` | 4 字节 |
| `u64BE/LE` | `Bytes u64BE(Long v)` | 无 | 8 字节 |
| `readShortBE/LE` | `Int readShortBE(Bytes, Int off)` | `off+2 <= len` | 返回无符号 16 位 |
| `readIntBE/LE` | `Int readIntBE(Bytes, Int off)` | `off+4 <= len` | 返回无符号 32 位 |
| `readLongBE/LE` | `Long readLongBE(Bytes, Int off)` | `off+8 <= len` | 返回 64 位 |

- 越界是合同错误；严格版 `tryReadShort` 等返回 `Result`（X）。
- 不提供“宿主端序”隐式默认；必须显式选择 BE/LE。

---

## 9. 错误、所有权与并发总结

| 项 | 契约 |
| --- | --- |
| 错误分类 | 越界/非法 hex → `InvalidArgument`；截断帧 → `DataCorrupted` |
| 资源 | 无句柄，无 close |
| 所有权 | `Bytes` 借用；`toBytes` 副本；`takeBytes` 转移 |
| 别名 | `slice` 副本；`ByteReader` 借用源；读取期间禁止改源 |
| 线程安全 | 全部非线程安全；跨任务共享需外部同步 |
| 取消 | 纯内存操作，不接受 `Context` |

---

## 10. 示例、反例与测试义务

### 10.1 示例

```text
Bytes payload = Bytes.fromUtf8("hi")
ByteWriter w = new ByteWriter()
w.writeU16BE(2)
w.writeBytes(payload)
Bytes frame = w.toBytes()
ByteReader r = new ByteReader(frame)
Int n = r.shortBE()
Result<Bytes, Error> body = r.readExact(n)
```

### 10.2 反例

- 用 `readU8()` 解析不可信协议，越界静默返回 0；
- 把 `slice` 当视图，修改副本期望影响原序列；
- `fromHex` 解析用户输入不检查奇数长度；
- 在 `ByteReader` 读取期间 `push` 源序列。

### 10.3 测试义务

| 类别 | 断言 |
| --- | --- |
| 转换 | UTF-8 往返、非法字节替换、hex 大小写/奇数长度 |
| 切片 | 钳制 vs 严格；副本独立性 |
| 比较 | 长度不同/前缀/空序列 |
| 游标 | 宽松/严格读取；position 不变性 |
| 端序 | 已知向量（0x1234 → 12 34 / 34 12） |
| 位 | popCount/leadingZeros/trailingZeros 边界（0、-1、MIN） |
| 反例 | 越界、截断、别名修改 |
| 差分 | mini + legacy `xdk_bytes*.x` |

---

## 11. 阶段切片（T0-04）

| 切片 | 交付 | 出口 |
| --- | --- | --- |
| B1 | 文件拆分；`Bytes` 顶层函数与 `tryGet/trySet` | 现有 bytes 场景不回归 |
| B2 | `ByteReader` 严格读取、`ByteWriter` 端序补全 | 协议解析场景 |
| B3 | `Bits` 计数、`ByteBuffer` 扩展 | 位/缓冲场景 |
| B4 | `Cursor`、`BytesBuilder`、严格端序读取 | T0-X 完成 |

---

## 12. 开放问题

1. `Bytes` 的 `==` 语义：当前不是值相等；是否引入 `Equals` 协议由语言层决定。
2. `slice` 是否提供零拷贝视图：首版不做，避免别名与生命周期问题。
3. `ByteBuffer` 是否采用 NIO 的 position/limit：T0-X 再定，先保持追加模型。
4. `readU8` 宽松语义是否保留：保留一个发布周期，随后标记 deprecated。
5. `u64` 依赖 `Long`/`UInt64` 的编译器支持；若缺失，B2 暂停并记录。
