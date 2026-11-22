# `xdk.bytes` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.bytes` |
| 层 | `xdk.core` / L2 |
| 依赖 | `xdk.errors` |
| 被依赖 | `text`、`io`、`fs`、`sys`、`log`、`net` |
| 稳定性 | 基础 `stable`；Builder/Buffer/BitSet `preview` |
| 文档原则 | 包级说明在本 README；每个类一个 PascalCase 文件 |

---

## 1. 包定位

`xdk.bytes` 处理原始字节：

- 可变字节序列、构建器、定位缓冲；
- 顺序读/写、游标、checked 读取；
- UTF-8/hex 转换、切片、比较；
- 端序读写；
- 位操作、位集合。

不做：Base64/压缩/加密（utils）、文件/网络 I/O（io/fs/net）、零拷贝裸指针。

---

## 2. 设计原则

| 原则 | 输出 |
| --- | --- |
| 越界是合同错误 | unchecked `get/set/read*` panic；checked 返回 `Result` |
| 不返回哨兵 | checked 读取不返回 0/空表示失败；用 `Result` |
| 切片是副本 | `slice` 返回新序列；`BytesView` 才是视图（X） |
| 写入取低 8 位 | `push/set/writeU8` 统一 |
| 不隐式端序 | 必须显式 BE/LE |
| 32 位无符号用 Long | `u32/readInt` 返回 `Long` |
| 非线程安全 | 跨任务共享需外部同步 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `Bytes` | 运行时库类型 | 可变字节序列 | [`Bytes.md`](Bytes.md) |
| `BytesBuilder` | class | 可增长构建器 | [`BytesBuilder.md`](BytesBuilder.md) |
| `ByteBuffer` | class | position/limit/capacity 缓冲 | [`ByteBuffer.md`](ByteBuffer.md) |
| `ByteReader` | class | 顺序/随机读 | [`ByteReader.md`](ByteReader.md) |
| `ByteWriter` | class | 顺序写 | [`ByteWriter.md`](ByteWriter.md) |
| `BitSet` | class | 位集合 | [`BitSet.md`](BitSet.md) |
| `ByteOrder` | enum | 大端/小端 | [`ByteOrder.md`](ByteOrder.md) |

---

## 4. 顶层函数：Bytes 转换/比较

### 4.1 方法面

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `fromUtf8` | UTF-8 编码 | `String text` | `Bytes` | 无 |
| `toUtf8` | UTF-8 解码 | `Bytes source` | `String` | 无（非法字节替换 U+FFFD） |
| `fromHex` | 严格 hex 解码 | `String hexadecimal` | `Bytes` | 非法/奇数长度 → panic |
| `tryFromHex` | checked hex | `String hexadecimal` | `Result<Bytes, Error>` | `InvalidArgument` |
| `toHex` | 小写 hex | `Bytes source` | `String` | 无 |
| `byteLength` | 字节数 | `Bytes source` | `Int` | 无 |
| `isEmptyBytes` | 是否为空 | `Bytes source` | `Bool` | 无 |
| `concatBytes` | 拼接副本 | `Bytes first, Bytes second` | `Bytes` | 无 |
| `copy` | 独立副本 | `Bytes source` | `Bytes` | 无 |
| `equals` | 逐字节相等 | `Bytes left, Bytes right` | `Bool` | 无 |
| `compare` | 字典序 | `Bytes left, Bytes right` | `Int` | 无 |
| `slice` | 钳制切片 | `Bytes source, Int startIndex, Int endIndex` | `Bytes` | 无 |
| `sliceChecked` | 严格切片 | 同上 | `Result<Bytes, Error>` | `InvalidArgument` |
| `tryGetByte` | checked 读 | `Bytes source, Int index` | `Result<Int, Error>` | `InvalidArgument` |
| `trySetByte` | checked 写 | `Bytes target, Int index, Int value` | `Result<Unit, Error>` | `InvalidArgument` |

### 4.2 使用的技术

- UTF-8 编解码；
- hex 双字符解码；
- 字典序比较；
- 钳制/严格两种切片；
- 副本语义。

### 4.3 需要的支撑

- 语言：String、Int、Bool、List；
- 运行时：字节序列、UTF-8 编解码原语；
- 接口：`Error`、`BasicError`、`ErrorKind`。

### 4.4 依赖的特性/接口/类

`Bytes`、`Error`、`BasicError`、`ErrorKind`。

### 4.5 XNull 伪代码

```xnull
Bytes fromUtf8(String text) {
    return Bytes.fromString(text)
}

String toUtf8(Bytes source) {
    return source.toString()
}

Result<Bytes, Error> tryFromHex(String hexadecimal) {
    if hexadecimal.length() % 2 != 0 {
        return Err(new BasicError(ErrorKind.InvalidArgument, "odd hex length"))
    }
    Bytes result = Bytes.alloc(hexadecimal.length() / 2)
    Int index = 0
    while index < hexadecimal.length() {
        Int high = hexValueOrNegative(hexadecimal.substring(index, 1))
        Int low = hexValueOrNegative(hexadecimal.substring(index + 1, 1))
        if high < 0 || low < 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid hex"))
        }
        result.push(high * 16 + low)
        index = index + 2
    }
    return Ok(result)
}

Bytes fromHex(String hexadecimal) {
    Result<Bytes, Error> result = tryFromHex(hexadecimal)
    if result.isErr() {
        throw result.error().describe()
    }
    return result.value()
}

String toHex(Bytes source) {
    String result = ""
    Int index = 0
    while index < source.length() {
        Int value = source.get(index)
        result = result + hexDigit(value / 16) + hexDigit(value % 16)
        index = index + 1
    }
    return result
}

Bytes slice(Bytes source, Int startIndex, Int endIndex) {
    Int start = startIndex
    Int end = endIndex
    if start < 0 { start = 0 }
    if end > source.length() { end = source.length() }
    if start > end { start = end }
    Bytes result = Bytes.alloc(end - start)
    Int index = start
    while index < end {
        result.push(source.get(index))
        index = index + 1
    }
    return result
}

Result<Bytes, Error> sliceChecked(Bytes source, Int startIndex, Int endIndex) {
    if startIndex < 0 || endIndex > source.length() || startIndex > endIndex {
        return Err(new BasicError(ErrorKind.InvalidArgument, "slice out of range"))
    }
    return Ok(slice(source, startIndex, endIndex))
}

Bool equals(Bytes left, Bytes right) {
    if left.length() != right.length() {
        return false
    }
    Int index = 0
    while index < left.length() {
        if left.get(index) != right.get(index) {
            return false
        }
        index = index + 1
    }
    return true
}

Int compare(Bytes left, Bytes right) {
    Int limit = left.length()
    if right.length() < limit { limit = right.length() }
    Int index = 0
    while index < limit {
        Int leftByte = left.get(index)
        Int rightByte = right.get(index)
        if leftByte < rightByte { return -1 }
        if leftByte > rightByte { return 1 }
        index = index + 1
    }
    if left.length() < right.length() { return -1 }
    if left.length() > right.length() { return 1 }
    return 0
}
```

---

## 5. 顶层函数：端序

### 5.1 方法面

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `u16BE/LE` | 写 2 字节 | `Int value` 0..65535 | `Bytes` | 越界 → panic |
| `u32BE/LE` | 写 4 字节 | `Long value` 0..4294967295 | `Bytes` | 越界 → panic |
| `u64BE/LE` | 写 8 字节 | `Long value` | `Bytes` | 无 |
| `readShortBE/LE` | 读 2 字节 | `Bytes source, Int offset` | `Int` | 越界 → panic |
| `readIntBE/LE` | 读 4 字节无符号 | `Bytes source, Int offset` | `Long` | 越界 → panic |
| `readLongBE/LE` | 读 8 字节 | `Bytes source, Int offset` | `Long` | 越界 → panic |
| `tryReadShort/Int/Long` | checked 读 | 同上 | `Result<...>` | `InvalidArgument` |

### 5.2 技术/支撑/依赖

- 技术：位移/掩码、BE/LE、无符号 32 位用 Long；
- 支撑：`Bytes`、Int、Long；
- 依赖：`Error`、`BasicError`、`ErrorKind`。

### 5.3 XNull 伪代码

```xnull
Bytes u16BE(Int value) {
    if value < 0 || value > 65535 {
        throw "u16BE: out of range"
    }
    Bytes result = Bytes.alloc(2)
    result.push((value / 256) % 256)
    result.push(value % 256)
    return result
}

Bytes u16LE(Int value) {
    if value < 0 || value > 65535 {
        throw "u16LE: out of range"
    }
    Bytes result = Bytes.alloc(2)
    result.push(value % 256)
    result.push((value / 256) % 256)
    return result
}

Bytes u32BE(Long value) {
    if value < 0 || value > 4294967295 {
        throw "u32BE: out of range"
    }
    Bytes result = Bytes.alloc(4)
    result.push((value / 16777216) % 256)
    result.push((value / 65536) % 256)
    result.push((value / 256) % 256)
    result.push(value % 256)
    return result
}

Bytes u32LE(Long value) {
    if value < 0 || value > 4294967295 {
        throw "u32LE: out of range"
    }
    Bytes result = Bytes.alloc(4)
    result.push(value % 256)
    result.push((value / 256) % 256)
    result.push((value / 65536) % 256)
    result.push((value / 16777216) % 256)
    return result
}

Int readShortBE(Bytes source, Int offset) {
    if offset < 0 || offset + 2 > source.length() {
        throw "readShortBE: out of range"
    }
    return source.get(offset) * 256 + source.get(offset + 1)
}

Int readShortLE(Bytes source, Int offset) {
    if offset < 0 || offset + 2 > source.length() {
        throw "readShortLE: out of range"
    }
    return source.get(offset) + source.get(offset + 1) * 256
}

Long readIntBE(Bytes source, Int offset) {
    if offset < 0 || offset + 4 > source.length() {
        throw "readIntBE: out of range"
    }
    Long result = 0
    Int index = 0
    while index < 4 {
        result = result * 256 + source.get(offset + index)
        index = index + 1
    }
    return result
}
```

> `u64BE/LE`、`readLongBE/LE` 用 64 位位模式；`tryRead*` 复用 unchecked 逻辑但先检查范围。

---

## 6. 顶层函数：位操作

### 6.1 方法面

| 组 | 函数 | 返回 |
| --- | --- | --- |
| 32 位 | `bitAnd/bitOr/bitXor/bitNot` | `Int` |
| 移位 | `shiftLeft/shiftRight`（0≤count<32） | `Int` |
| 计数 | `popCount/leadingZeros/trailingZeros` | `Int` |
| 旋转/反转 | `rotateLeft/rotateRight/reverseBits/byteSwap` | `Int` |
| 2 的幂 | `isPowerOfTwo/nextPowerOfTwo` | `Bool`/`Int` |
| 掩码 | `mask/extract/insert` | `Int` |
| 64 位 | `shiftLeftLong/shiftRightLong/popCountLong/leadingZerosLong/trailingZerosLong` | `Long`/`Int` |

### 6.2 技术/支撑/依赖

- 技术：位运算、移位、popcount、位反转；
- 支撑：Int/Long；
- 依赖：无错误依赖；非法 shift → panic。

### 6.3 XNull 伪代码

```xnull
Int shiftLeft(Int value, Int bitCount) {
    if bitCount < 0 || bitCount >= 32 {
        throw "shiftLeft: bit count out of range"
    }
    return value * powerOfTwo(bitCount)
}

Int shiftRight(Int value, Int bitCount) {
    if bitCount < 0 || bitCount >= 32 {
        throw "shiftRight: bit count out of range"
    }
    if value >= 0 {
        return value / powerOfTwo(bitCount)
    }
    return (value - powerOfTwo(32 - bitCount) + 1) / powerOfTwo(bitCount)
}

Int popCount(Int value) {
    Int count = 0
    Long current = value as Long
    if current < 0 {
        current = current + 4294967296
    }
    while current > 0 {
        count = count + (current % 2) as Int
        current = current / 2
    }
    return count
}

Bool isPowerOfTwo(Int value) {
    if value <= 0 {
        return false
    }
    return (value & (value - 1)) == 0
}
```

---

## 7. 场景

### B1：协议帧解析

`ByteReader.readExact` + `readU16BE/readU32BE` + `readBytes`；半包/截断 → `DataCorrupted`；位置不变。

### B2：二进制组帧

`ByteWriter.writeU16BE/writeU32BE/writeBytes`；`toBytes` 副本；`takeBytes` 转移。

### B3：hex 调试

`tryFromHex` 解析外部输入；`toHex` 输出；非法输入 `InvalidArgument`。

### B4：位标志

`BitSet`/`Bits` 处理权限/标志；越界/非法 shift panic。

### B5：缓冲复用

`ByteBuffer` position/limit/flip/compact 处理读/写切换；`ByteWriter` 只追加。

---

## 8. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 零拷贝视图 | `BytesView` 为 X； 切片是副本 |
| `Bytes.fromString` | 运行时构造器；公共 UTF-8 用 `fromUtf8` |
| `readBytes` 钳制 | 保留；严格用 `readExact` |
| `readU8` EOF | panic；checked 用 `tryReadU8` |
| 位集底层 | `List<Long>` 或 `Bytes` 由实现决定；API 不变 |
| 端序默认 | 无默认；必须显式 BE/LE |
| 线程安全 | 全部非线程安全；外部同步 |
| 大文件 | `ByteBuffer` 不是文件映射；文件用 `fs.File` |

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | 无领域注解 |
| 本包消费 | `@Data`、`@Value`、`@Builder`、`@Copy` |
| 处理器 | 标准 A8 |
| 生成物 | 字节容器/构建器派生成员与复制 |
| 状态 | 无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Bytes`/`BytesBuilder`/`BitSet` | `@Data` | 数据类成员/复制 |
| `ByteOrder` | — | enum，无派生 |
| `ByteBuffer` | `@Builder` | 选项构造 |

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
