# xdk.bytes —— T0 核心包详细设计 v1.2

> 本版按 S1 §2.2 固定数值宽度：`Int` 32 位、`Long` 64 位。所有
> `Int32/Int64/UInt64` 别名从公开签名移除；32 位无符号值用 `Long` 承载，
> 64 位值按 `Long` 位模式解释。所有“读不够返回 0”的宽松语义删除：
> unchecked 读取越界是合同错误（panic），checked 读取返回 `Result`。

| 项 | 值 |
| --- | --- |
| 包 | `xdk.bytes` |
| 层级 | T0 |
| 稳定性 | 核心 `stable`（T0-K）；扩展 `preview`（T0-X） |
| 依赖 | `xdk.errors` |
| 被依赖 | text、io、fs、sys、log |
| 对应源码 | `src/xdk/core/bytes/Bytes.x`（当前单文件；按能力拆分是内部实现） |
| 阶段 | T0-04（一个包一个验收门；实现可分内部提交） |

---

## 1. 能力声明

| 能力 | 说明 | 承载 | 层级 |
| --- | --- | --- | --- |
| CAP-1 字节序列 | 可变、按索引访问的字节序列 | `Bytes` | K |
| CAP-2 编码转换 | UTF-8 / hex 与文本互转 | `fromUtf8`、`toUtf8`、`fromHex`、`toHex` | K |
| CAP-3 切片与比较 | 子序列、字典序比较、相等 | `slice`、`compare`、`equals` | K |
| CAP-4 顺序读 | 带游标的严格读取 | `ByteReader` | K |
| CAP-5 顺序写 | 追加写、定长整数写 | `ByteWriter` | K |
| CAP-6 端序 | u16/u32/u64 与大小端读写 | `Endian` | K |
| CAP-7 位操作 | 32 位与 64 位位运算、计数 | `Bits` | K |
| CAP-8 可增长缓冲 | 随机定位读写、预留容量 | `ByteBuffer` | X |

**非目标**：

- 不做 base64/压缩/加密（T1 codec/crypto）；
- 不做文件/网络 I/O；
- 不暴露零拷贝 FFI 裸指针；
- 不做线程安全容器；
- 不提供 `BytesBuilder`、`Cursor`；它们与 `ByteWriter`/`ByteReader.seek`
  重叠且没有场景，移出 T0。

---

## 2. 分层与文件

### 2.1 `Bytes` 的分层

`Bytes` 是库类型，存储由运行时提供；公开 API 分两层：

| 层 | 内容 | 说明 |
| --- | --- | --- |
| 语言/运行时原语 | `length()`、`get(Int index)`、`set(Int index, Int value)`、`push(Int value)` | 只做字节访问；越界是合同错误（panic） |
| XDK 公开函数 | 转换、比较、切片、checked 访问 | 由 `xdk.bytes` 提供；checked 版本返回 `Result` |

运行时不得依赖 `xdk.errors`；因此 checked 访问是 XDK 顶层函数，
不是 `Bytes` 的运行时成员：

```text
Result<Int, Error> tryGetByte(Bytes source, Int index)
Result<Unit, Error> trySetByte(Bytes target, Int index, Int value)
```

### 2.2 文件

| 文件 | 类型/函数 | 层级 |
| --- | --- | --- |
| `Bytes.x` | `Bytes` 顶层函数、`tryGetByte/trySetByte`、`equals`、`copy` | K |
| `ByteReader.x` | `ByteReader` | K |
| `ByteWriter.x` | `ByteWriter` | K |
| `Endian.x` | u16/u32/u64、read/write at offset | K |
| `Bits.x` | 32/64 位运算、popCount、前导/末尾零 | K |
| `ByteBuffer.x` | `ByteBuffer`、`byteBufferFrom` | X |

文件拆分是内部组织，不改变符号名；不以“文件已拆分”作为阶段完成条件。

---

## 3. `Bytes`（库类型）

### 3.1 表示与不变量

- `Bytes` 是可变、引用语义的字节序列；`length()` 以字节计。
- 任意时刻 `0 <= length`；索引合法域 `[0, length-1]`。
- `Bytes` 不持有 OS 资源，无 `close()`。
- `Bytes` 的 `==` 是引用身份，不是字节相等；值比较用
  `equals(Bytes left, Bytes right)` 或 `compare(Bytes left, Bytes right) == 0`。

### 3.2 所有权与别名

| 场景 | 契约 |
| --- | --- |
| 函数参数 `Bytes` | 借用；函数不得保留引用，除非名称/文档声明 |
| 返回 `Bytes` | 返回新序列（`returnOwned`）；调用方拥有 |
| `slice` | 返回副本（不是视图）；修改副本不影响原序列 |
| `ByteReader(Bytes source)` | 读取器复制源引用；读取期间调用方不得修改源 |
| `ByteWriter.toBytes()` | 返回副本 |
| `ByteWriter.takeBytes()` | 转移内部序列；writer 清空 |
| 跨任务共享 | 非线程安全；需外部同步，禁止一边读一边写 |

### 3.3 顶层函数契约

| 函数 | 签名 | 前置 | 后置 | 失败 | 复杂度 |
| --- | --- | --- | --- | --- | --- |
| `fromUtf8` | `Bytes fromUtf8(String text)` | `String` 是合法 UTF-8 | UTF-8 编码 | 无 | O(n) |
| `toUtf8` | `String toUtf8(Bytes source)` | 无 | 非法字节替换为 U+FFFD | 无 | O(n) |
| `fromHex` | `Bytes fromHex(String hexadecimal)` | 仅大小写 hex，长度偶数 | 解码 | 非法字符/奇数长度为合同错误（panic） | O(n) |
| `tryFromHex` | `Result<Bytes, Error> tryFromHex(String hexadecimal)` | 无 | 合法解码；非法 `InvalidArgument` | `InvalidArgument` | O(n) |
| `toHex` | `String toHex(Bytes source)` | 无 | 小写 hex，长度 = 2×字节数 | 无 | O(n) |
| `byteLength` | `Int byteLength(Bytes source)` | 无 | 字节数 | 无 | O(1) |
| `isEmpty` | `Bool isEmpty(Bytes source)` | 无 | `length == 0` | 无 | O(1) |
| `concatBytes` | `Bytes concatBytes(Bytes first, Bytes second)` | 无 | 新序列 = first + second；不修改入参 | 无 | O(a+b) |
| `copy` | `Bytes copy(Bytes source)` | 无 | 返回独立副本 | 无 | O(n) |
| `equals` | `Bool equals(Bytes left, Bytes right)` | 无 | 长度与逐字节相等 | 无 | O(n) |
| `compare` | `Int compare(Bytes left, Bytes right)` | 无 | 字典序：<0/0/>0 | 无 | O(n) |
| `slice` | `Bytes slice(Bytes source, Int startIndex, Int endIndex)` | 无 | 钳制到 `[0,length]`；`startIndex > endIndex` 归一为空 | 无 | O(n) |
| `sliceChecked` | `Result<Bytes, Error> sliceChecked(Bytes source, Int startIndex, Int endIndex)` | 无 | 严格范围检查；成功返回副本 | `InvalidArgument` | O(n) |
| `tryGetByte` | `Result<Int, Error> tryGetByte(Bytes source, Int index)` | 无 | 合法返回 0..255；越界 `InvalidArgument` | `InvalidArgument` | O(1) |
| `trySetByte` | `Result<Unit, Error> trySetByte(Bytes target, Int index, Int value)` | 无 | 合法写入低 8 位；越界 `InvalidArgument` | `InvalidArgument` | O(1) |

**冻结说明**：

- `fromHex` 是严格函数：非法字符或奇数长度直接 panic；外部输入必须用
  `tryFromHex`，不再保留“奇数长度丢半字节”的宽松语义。
- `fromHex` 接受小写和大写 A-F。
- `slice` 的钳制语义保留，但只用于已知范围；外部范围用 `sliceChecked`。
- `tryGetByte/trySetByte` 是 XDK 函数，不是运行时成员，避免运行时依赖
  `xdk.errors`。

### 3.4 运行时原语契约

| 方法 | 签名 | 前置 | 后置 | 越界行为 |
| --- | --- | --- | --- | --- |
| `length` | `Int length()` | 无 | 字节数 | 无 |
| `get` | `Int get(Int index)` | `0 <= index < length` | 返回 0..255 | 合同错误（panic） |
| `set` | `Void set(Int index, Int value)` | `0 <= index < length`；value 取低 8 位 | 修改该字节 | 合同错误（panic） |
| `push` | `Void push(Int value)` | 无 | 追加低 8 位；容量按摊还增长 | 无 |

### 3.5 示例与反例

```text
Bytes bytes = fromUtf8("AB")
print(bytes.length())                  // 2
bytes.set(0, 65)
print(toUtf8(bytes))                   // AB
Bytes copiedBytes = slice(bytes, 0, 1) // 副本
copiedBytes.set(0, 67)
print(toUtf8(bytes))                   // AB（原序列未变）

Result<Bytes, Error> parsed = tryFromHex("4a4B")
print(parsed.isOk())                   // true
print(toHex(parsed.value()))           // 4a4b
```

反例：

- 把 `Bytes` 当值类型直接 `==` 比较；
- `ByteReader` 读取期间对源 `Bytes` 做 `set/push`；
- 用 `fromHex` 解析外部输入而不先校验；
- 把 `slice` 当视图，修改副本期望影响原序列。

---

## 4. `ByteReader`（class，T0-K）

### 4.1 表示与不变量

```text
class ByteReader {
    Bytes _source
    Int _position

    ByteReader(Bytes source)
    Int position()
    Int remaining()
    Bool hasRemaining()
    Result<Unit, Error> seek(Int offset)

    Int readU8()
    Result<Int, Error> tryReadU8()

    Int shortBE()
    Int shortLE()
    Result<Int, Error> tryShortBE()
    Result<Int, Error> tryShortLE()

    Long intBE()
    Long intLE()
    Result<Long, Error> tryIntBE()
    Result<Long, Error> tryIntLE()

    Long longBE()
    Long longLE()
    Result<Long, Error> tryLongBE()
    Result<Long, Error> tryLongLE()

    Bytes readBytes(Int count)
    Result<Bytes, Error> readExact(Int count)
}
```

- `0 <= _position <= _source.length()` 是不变量；任何读取都不会让位置越过末尾。
- 读取器持有 `source` 引用；调用方在读取期间不得修改源。
- 读取器无资源，无 `close()`；需要重置时新建。
- 线程安全：否。

### 4.2 方法契约

| 方法 | 前置 | 后置 | 失败 | 复杂度 |
| --- | --- | --- | --- | --- |
| `position()` | 无 | 当前游标 | 无 | O(1) |
| `remaining()` | 无 | `length - position` | 无 | O(1) |
| `hasRemaining()` | 无 | `position < length` | 无 | O(1) |
| `seek(offset)` | `0 <= offset <= length` | 成功则 position = offset | 越界 `InvalidArgument`，位置不变 | O(1) |
| `readU8()` | `hasRemaining()` | 返回 0..255 并前进 1 | 无剩余为合同错误（panic） | O(1) |
| `tryReadU8()` | 无 | 成功前进 1；失败位置不变 | `DataCorrupted` | O(1) |
| `shortBE()`/`shortLE()` | `remaining >= 2` | 读 2 字节并前进 2；返回 0..65535 | 不足为合同错误（panic） | O(1) |
| `tryShortBE()`/`tryShortLE()` | 无 | 成功前进 2；失败位置不变 | `DataCorrupted` | O(1) |
| `intBE()`/`intLE()` | `remaining >= 4` | 读 4 字节并前进 4；按无符号返回 0..4294967295 | 不足为合同错误（panic） | O(1) |
| `tryIntBE()`/`tryIntLE()` | 无 | 成功前进 4；失败位置不变 | `DataCorrupted` | O(1) |
| `longBE()`/`longLE()` | `remaining >= 8` | 读 8 字节并前进 8；按 64 位位模式返回 | 不足为合同错误（panic） | O(1) |
| `tryLongBE()`/`tryLongLE()` | 无 | 成功前进 8；失败位置不变 | `DataCorrupted` | O(1) |
| `readBytes(count)` | `count >= 0` | 读取 `min(count, remaining)` 字节；返回副本；前进实际读取数 | `count < 0` 为合同错误（panic） | O(count) |
| `readExact(count)` | `count >= 0` | 恰好读 `count` 字节；成功前进 count | 不足 `DataCorrupted`，位置不变；`count < 0` 为合同错误（panic） | O(count) |

**冻结说明**：

- 删除“读不够返回 0”的宽松语义；`readU8/shortBE/intBE/longBE` 越界直接 panic。
- `intBE/intLE` 返回 `Long`，因为 32 位无符号值 `0..4294967295` 不能放进
  32 位有符号 `Int`。
- `readBytes` 是钳制读取；需要“恰好”语义时用 `readExact`。
- `try*` 失败时位置不变，调用方可以重试或走其他分支。

### 4.3 示例

```text
Bytes frame = fromHex("00010203")
ByteReader reader = new ByteReader(frame)
Int magicNumber = reader.shortBE()
print(magicNumber)                       // 1
Result<Bytes, Error> payload = reader.readExact(2)
print(payload.isOk())                    // true
print(toHex(payload.value()))            // 0203
```

---

## 5. `ByteWriter`（class，T0-K）

### 5.1 表示与不变量

```text
class ByteWriter {
    Bytes _buffer

    ByteWriter()
    Int length()
    Bytes toBytes()
    Bytes takeBytes()
    Void writeU8(Int value)
    Void writeBytes(Bytes source)
    Void writeU16BE(Int value)
    Void writeU16LE(Int value)
    Void writeU32BE(Long value)
    Void writeU32LE(Long value)
    Void writeU64BE(Long value)
    Void writeU64LE(Long value)
    Void clear()
}
```

- 内部只追加；`toBytes()` 返回副本，`takeBytes()` 转移内部序列并清空 writer。
- 线程安全：否。

### 5.2 契约

| 方法 | 前置 | 后置 | 失败 | 复杂度 |
| --- | --- | --- | --- | --- |
| `writeU8(value)` | 无 | 追加 `value & 0xFF` | 无 | 摊还 O(1) |
| `writeBytes(source)` | source 非 null | 追加副本；不保留 source 引用 | 无 | O(n) |
| `writeU16BE/LE(value)` | `0 <= value <= 0xFFFF` | 按指定端序追加 2 字节 | 越界为合同错误（panic） | O(1) |
| `writeU32BE/LE(value)` | `0 <= value <= 0xFFFFFFFF` | 按指定端序追加 4 字节 | 越界为合同错误（panic） | O(1) |
| `writeU64BE/LE(value)` | 无 | 按 64 位位模式追加 8 字节 | 无 | O(1) |
| `toBytes()` | 无 | 返回当前内容副本 | 无 | O(n) |
| `takeBytes()` | 无 | 返回内部序列；writer 长度归零 | 无 | O(1) |
| `clear()` | 无 | 长度归零；容量保留 | 无 | O(1) |

- `writeU32BE/LE` 使用 `Long`，因为 `Int` 只有 32 位有符号，无法表示
  `0xFFFFFFFF`。
- `writeU64BE/LE` 接受 `Long` 位模式；无符号解释由调用方负责。

---

## 6. `ByteBuffer`（class，T0-X）

### 6.1 能力

可增长缓冲，支持追加与定位读写；不暴露裸内存。

```text
ByteBuffer byteBufferFrom(Bytes initialContent)

class ByteBuffer {
    ByteBuffer()
    Int length()
    Int capacity()
    Bytes toBytes()
    Void push(Int value)
    Void append(Bytes source)
    Result<Unit, Error> put(Int index, Int value)
    Result<Int, Error> get(Int index)
    Void clear()
    Void reserve(Int minimumCapacity)
}
```

### 6.2 契约

| 方法 | 前置 | 后置 | 失败 | 复杂度 |
| --- | --- | --- | --- | --- |
| `byteBufferFrom(initialContent)` | 非 null | 返回新缓冲；复制内容，不保留入参引用 | 无 | O(n) |
| `push(value)` | 无 | 追加低 8 位 | 无 | 摊还 O(1) |
| `append(source)` | source 非 null | 追加副本 | 无 | O(n) |
| `put(index, value)` | 无 | 合法写入；越界 `InvalidArgument` | `InvalidArgument` | O(1) |
| `get(index)` | 无 | 合法返回 0..255；越界 `InvalidArgument` | `InvalidArgument` | O(1) |
| `reserve(minimumCapacity)` | 无 | 容量至少 `minimumCapacity`；不清空 | `minimumCapacity < 0` → 合同错误（panic） | O(n) |
| `clear()` | 无 | 长度 0；容量保留 | 无 | O(1) |

- `position/limit/flip/compact` 不在 T0-X 承诺；需要时另立设计。
- `ByteBuffer` 与 `ByteWriter` 的分工：`ByteWriter` 只追加；`ByteBuffer`
  支持定位读写和容量预留。

---

## 7. `Bits`（函数，T0-K）

### 7.1 32 位（`Int`）

| 函数 | 签名 | 前置 | 后置 | 失败 |
| --- | --- | --- | --- | --- |
| `bitAnd` | `Int bitAnd(Int left, Int right)` | 无 | 按位与 | 无 |
| `bitOr` | `Int bitOr(Int left, Int right)` | 无 | 按位或 | 无 |
| `bitXor` | `Int bitXor(Int left, Int right)` | 无 | 按位异或 | 无 |
| `bitNot` | `Int bitNot(Int value)` | 无 | 按位取反 | 无 |
| `shiftLeft` | `Int shiftLeft(Int value, Int bitCount)` | `0 <= bitCount < 32` | 左移；溢出按 32 位回绕 | 越界为合同错误（panic） |
| `shiftRight` | `Int shiftRight(Int value, Int bitCount)` | 同上 | 算术右移 | 同上 |
| `popCount` | `Int popCount(Int value)` | 无 | 1 的个数（0..32） | 无 |
| `leadingZeros` | `Int leadingZeros(Int value)` | 无 | 前导 0 数；0 → 32 | 无 |
| `trailingZeros` | `Int trailingZeros(Int value)` | 无 | 末尾 0 数；0 → 32 | 无 |

### 7.2 64 位（`Long`）

| 函数 | 签名 | 前置 | 后置 | 失败 |
| --- | --- | --- | --- | --- |
| `shiftLeftLong` | `Long shiftLeftLong(Long value, Int bitCount)` | `0 <= bitCount < 64` | 左移；溢出按 64 位回绕 | 越界为合同错误（panic） |
| `shiftRightLong` | `Long shiftRightLong(Long value, Int bitCount)` | 同上 | 算术右移 | 同上 |
| `popCountLong` | `Int popCountLong(Long value)` | 无 | 1 的个数（0..64） | 无 |
| `leadingZerosLong` | `Int leadingZerosLong(Long value)` | 无 | 前导 0 数；0 → 64 | 无 |
| `trailingZerosLong` | `Int trailingZerosLong(Long value)` | 无 | 末尾 0 数；0 → 64 | 无 |

- 位操作不隐式提升：`Int` 与 `Long` 必须显式选择对应函数。
- 移位量来自外部时，调用方必须先校验；越界直接 panic。

---

## 8. `Endian`（函数，T0-K）

| 函数 | 签名 | 前置 | 后置 |
| --- | --- | --- | --- |
| `u16BE` | `Bytes u16BE(Int value)` | `0 <= value <= 0xFFFF` | 2 字节 |
| `u16LE` | `Bytes u16LE(Int value)` | 同上 | 2 字节 |
| `u32BE` | `Bytes u32BE(Long value)` | `0 <= value <= 0xFFFFFFFF` | 4 字节 |
| `u32LE` | `Bytes u32LE(Long value)` | 同上 | 4 字节 |
| `u64BE` | `Bytes u64BE(Long value)` | 无 | 8 字节位模式 |
| `u64LE` | `Bytes u64LE(Long value)` | 无 | 8 字节位模式 |
| `readShortBE` | `Int readShortBE(Bytes source, Int offset)` | `offset + 2 <= length` | 0..65535 |
| `readShortLE` | `Int readShortLE(Bytes source, Int offset)` | 同上 | 0..65535 |
| `readIntBE` | `Long readIntBE(Bytes source, Int offset)` | `offset + 4 <= length` | 0..4294967295 |
| `readIntLE` | `Long readIntLE(Bytes source, Int offset)` | 同上 | 0..4294967295 |
| `readLongBE` | `Long readLongBE(Bytes source, Int offset)` | `offset + 8 <= length` | 64 位位模式 |
| `readLongLE` | `Long readLongLE(Bytes source, Int offset)` | 同上 | 64 位位模式 |
| `tryReadShortBE` / `tryReadShortLE` | `Result<Int, Error> tryReadShortBE(Bytes source, Int offset)` | 无 | 越界 `InvalidArgument` |
| `tryReadIntBE` / `tryReadIntLE` | `Result<Long, Error> tryReadIntBE(Bytes source, Int offset)` | 无 | 越界 `InvalidArgument` |
| `tryReadLongBE` / `tryReadLongLE` | `Result<Long, Error> tryReadLongBE(Bytes source, Int offset)` | 无 | 越界 `InvalidArgument` |

- 越界是合同错误；checked 函数返回 `Result`，不 panic。
- 不提供“宿主端序”隐式默认；必须显式选择 BE/LE。
- `u32/readInt` 使用 `Long` 承载无符号 32 位；不把 `0xFFFFFFFF` 塞进
  32 位有符号 `Int`。

---

## 9. 错误、所有权与并发总结

| 项 | 契约 |
| --- | --- |
| 错误分类 | 越界/非法 hex → `InvalidArgument`；截断帧 → `DataCorrupted` |
| unchecked 失败 | 合同错误，直接 panic |
| checked 失败 | `Result`，失败时位置/内容不变 |
| 资源 | 无句柄，无 close |
| 所有权 | `Bytes` 借用；`toBytes` 返回副本；`takeBytes` 转移 |
| 别名 | `slice` 副本；`ByteReader` 持有源引用；读取期间禁止改源 |
| 线程安全 | 全部非线程安全；跨任务共享需外部同步 |
| 取消 | 纯内存操作，不接受 `Context` |

---

## 10. 示例、反例与测试义务

### 10.1 示例

```text
Bytes payload = fromUtf8("hi")
ByteWriter writer = new ByteWriter()
writer.writeU16BE(2)
writer.writeBytes(payload)
Bytes frame = writer.toBytes()

ByteReader reader = new ByteReader(frame)
Int payloadLength = reader.shortBE()
Result<Bytes, Error> payloadResult = reader.readExact(payloadLength)
print(payloadLength)                 // 2
print(toHex(payloadResult.value()))  // 6869
```

### 10.2 反例

- 用 `readU8()` 解析不可信协议，越界后期望返回 0；
- 把 `slice` 当视图，修改副本期望影响原序列；
- `fromHex` 解析用户输入不检查奇数长度；
- 在 `ByteReader` 读取期间 `push` 源序列；
- 把 `readIntBE` 的返回值塞进 `Int`，丢失 `0xFFFFFFFF`。

### 10.3 测试义务

| 类别 | 断言 |
| --- | --- |
| 转换 | UTF-8 往返、非法字节替换、hex 大小写/奇数长度/非法字符 |
| 切片 | 钳制 vs 严格；副本独立性 |
| 比较 | 长度不同/前缀/空序列 |
| 游标 | 严格读取、checked 读取、position 不变性 |
| 端序 | 已知向量（0x1234 → 12 34 / 34 12；0xFFFFFFFF） |
| 位 | popCount/leadingZeros/trailingZeros 边界（0、-1、MIN） |
| 反例 | 越界、截断、别名修改 |
| 差分 | mini base/full `xdk_bytes*.x` |

---

## 11. 阶段交付与验收（T0-04）

本包是一个验收门，不是一次提交。实现可以拆内部提交，但只有满足以下条件
才能标记 `xdk.bytes` 为 `complete`：

- `Bytes` 转换/切片/比较/checked 访问与契约一致；
- `ByteReader` 严格读取与 checked 读取都有测试，位置不变量成立；
- `ByteWriter` 的 `toBytes` 副本、`takeBytes` 转移、u32/u64 写入有测试；
- `Endian` 的 32 位无符号值与 64 位位模式有边界测试；
- `Bits` 的 32/64 位边界有测试；
- 场景、回归、mini base/full 通过；
- 文档、场景、回归、实现同一包交付；内部提交不单独宣称包完成。

`ByteBuffer` 属于 T0-X；未完成时包状态为 `partial`，不得用 T0-K 冒充
`complete`。

---

## 12. 后续能力（T1/backlog）

- `BytesBuilder`、`Cursor`、零拷贝 `ByteSlice` 视图；
- base64、压缩、加密；
- 流式/文件/网络字节源；
- 真正的 NIO `position/limit/flip/compact` 语义。

---

## 13. 评审结论（本包）

- 统一 `Int` 32 位、`Long` 64 位，删除 `Int32/Int64/UInt64` 公开别名；
- 修复 `u32/readInt` 无法表示 `0xFFFFFFFF` 的类型错误；
- 删除所有“读不够返回 0”的宽松语义，unchecked panic、checked `Result`；
- 修复 `fromHex` 奇数长度丢半字节和大写不识别；
- 明确 `Bytes` 运行时原语与 XDK checked 函数的分层；
- 删除 `BytesBuilder`/`Cursor` 的空头承诺；
- 满足 v1.2 的“无待定、无同名换义、无不可表达类型”要求。

下一阶段：`05-text.md`（文本算法、Builder、Format、Parse、Unicode）。
