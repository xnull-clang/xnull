# `FlashRegion`

| 项 | 值 |
| --- | --- |
| 类型 | `class FlashRegion`（控制句柄） |
| 包 | `xdk.embedded` |
| 层 |  |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error`、`Bytes`、`Board` |

---

## 1. 定位

已打开的**有界 Flash 区域句柄**：按相对区域偏移读取、擦除、写入、检查是否已擦除、关闭、是否打开。

不做：文件系统、磨损均衡、OTA、安全启动、密钥存储、分区表、Flash 控制器寄存器、写保护熔丝、坏块管理、隐式擦除、后台写回。文件系统/OTA 归 ecosystem；本类型只提供最底层、显式、可审计的区域操作。

---

## 2. 设计逻辑

- 为什么是 class：Flash 是有状态、危险、可能被独占的硬件资源；需要显式打开/关闭与区域边界；不是值对象。
- 由静态 `FlashRegion.open(context, board, regionName, offsetBytes, lengthBytes)` 创建；构造器主要供宿主/测试使用。
- `board.flashBytes()` 给出标称 Flash 容量；打开时校验 `lengthBytes > 0`、`lengthBytes <= board.flashBytes()`、`offsetBytes <= board.flashBytes() - lengthBytes`（先减后比，避免 `offset + length` 溢出）。
- `regionName` 是审计标签（如 `"bootloader"`、`"config"`、`"app-a"`），非空；不用于寻址、不做自动分区查找。调用方必须在板上自行规划区域，避免与其它区域重叠。
- 打开时由适配器返回几何：`pageSizeBytes`、`eraseSizeBytes`、`writeSizeBytes`。三者 `>0`；区域 `offsetBytes` 与 `lengthBytes` 必须按 `eraseSizeBytes` 对齐（否则 `InvalidArgument`），避免擦除半个页/越过区域边界。
- `read` 可从任意字节偏移开始，长度由调用方缓冲区决定；`write` 只接受按写粒度对齐的偏移/长度；`erase` 只接受按擦除粒度对齐的偏移/长度。
- `write` **不隐式擦除**。Flash 通常只能把 1 写成 0；要写入任意数据必须先 `erase`，或用 `isErased` 验证目标已擦除。隐式擦除会让“写一个配置字段”意外清空整页，因此被明确禁止。
- `isErased` 逐块读取并比较 `0xFF`；它是辅助验证，不是原子保证；基线只支持 `0xFF` 擦除值的 NOR Flash，其它介质适配器应返回 `Unsupported`。检查与写入之间仍可能被其它写者改变（本类型不提供跨进程锁）。
- `erase`/`write` 是危险操作：适配器必须在执行前写审计日志（区域名、相对偏移、长度、操作类型），不得记录写入内容中的密钥/凭据；日志失败不应静默继续（适配器可返回 `Io`）。
- 取消：`read`/`isErased` 可在块间检查 `Context`；`erase` 一旦开始可能无法安全中断，若返回 `Cancelled`，区域内容未定义，调用方必须重新擦除/校验。`write` 同理，部分写后失败的区域内容未定义。
- 打开受 OS/适配器能力/权限门控：无 Flash `Unsupported`，写保护 `PermissionDenied`，控制器忙 `Busy`，I/O `Io`。
- `close()` 幂等；关闭后 `name`/`offsetBytes`/`lengthBytes`/`pageSizeBytes`/`eraseSizeBytes`/`writeSizeBytes`/`isOpen`/`close`/`describe` 可用；`read`/`write`/`erase`/`isErased` 返回 `Unavailable`。
- 非线程安全；同一句柄的 `read`/`write`/`erase`/`isErased`/`close` 必须由调用方串行化。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_handle` | `Long` | final | `>0`；不透明句柄 |
| `_name` | `String` | final | 非空；审计标签 |
| `_offsetBytes` | `Long` | final | `>=0`；相对整片 Flash 的起始 |
| `_lengthBytes` | `Long` | final | `>0`；区域长度 |
| `_pageSizeBytes` | `Long` | final | `>0`；页大小 |
| `_eraseSizeBytes` | `Long` | final | `>0`；擦除粒度 |
| `_writeSizeBytes` | `Long` | final | `>0`；写粒度 |
| `_open` | `Bool` | 内部 | 是否打开 |

不变量：

- `_handle > 0`；`_name` 非空；`_offsetBytes >= 0`；`_lengthBytes > 0`。
- `_pageSizeBytes > 0`；`_eraseSizeBytes > 0`；`_writeSizeBytes > 0`。
- `_offsetBytes % _eraseSizeBytes == 0`；`_lengthBytes % _eraseSizeBytes == 0`。
- 构造后 `_open = true`；`close` 后 `_open = false`；`close` 幂等。
- 关闭后不再调用原生读/写/擦除/关闭原语；`_handle` 不复用、不持久化、不跨进程。
- 所有相对偏移/长度操作必须满足 `0 <= offsetBytes` 且 `lengthBytes <= _lengthBytes - offsetBytes`；先减后比，避免溢出。
- `_name` 不含秘密；日志只用区域名/偏移/长度，不输出写入内容。

---

## 4. 生命周期

由 `FlashRegion.open` 创建；构造器主要供宿主/测试使用。调用方持有；调用方 `close()` 释放句柄；无 `deinit`/finalizer 依赖。关闭后对象终止，不提供重新打开；需要新区域/新几何时重新 `open`。关闭前应确保没有未完成的写/擦除；本类型的方法是同步的，但取消后的部分写/擦除仍需调用方校验。关闭后只允许纯读取器、`describe` 与 `close`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `FlashRegion(Long handle, String name, Long offsetBytes, Long lengthBytes, Long pageSizeBytes, Long eraseSizeBytes, Long writeSizeBytes)` | handle、name、区域、几何 | handle>0；name 非空；offset≥0；length>0；三个 size>0；offset/length 按 eraseSize 对齐 | 非法 → panic |
| `FlashRegion.open(Context context, Board board, String regionName, Long offsetBytes, Long lengthBytes)` | context、board、regionName、区域 | context/board/regionName 非 null；regionName 非空；offset≥0；length>0；区域不越界；几何合法；区域按 eraseSize 对齐 | null → panic；越界/未对齐 → `InvalidArgument`；无 Flash → `Unsupported`；适配器失败透传 |

`open` 成功后返回打开对象；适配器返回 `[handle, pageSizeBytes, eraseSizeBytes, writeSizeBytes]`；列表长度不是 4、句柄 `<=0`、任一 size `<=0` 视为内部错误（`Internal`），并尽力关闭已打开的句柄。

---

## 6. 字段表

见 §3；字段私有。`Board` 只在 `open` 时借用，不长期持有；`_name` 是审计标签，不是路径/分区 ID。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `open`（static） | 打开 Flash 区域 | `Context context, Board board, String regionName, Long offsetBytes, Long lengthBytes` | `Result<FlashRegion, Error>` | null → panic；`InvalidArgument`/`Unsupported`/`PermissionDenied`/`Busy`/`Io`/`Cancelled`/`Timeout` |
| `name` | 审计标签 | 无 | `String` | 无 |
| `offsetBytes` | 区域起始 | 无 | `Long` | 无 |
| `lengthBytes` | 区域长度 | 无 | `Long` | 无 |
| `pageSizeBytes` | 页大小 | 无 | `Long` | 无 |
| `eraseSizeBytes` | 擦除粒度 | 无 | `Long` | 无 |
| `writeSizeBytes` | 写粒度 | 无 | `Long` | 无 |
| `read` | 读取区域 | `Context context, Long offsetBytes, Bytes buffer` | `Result<Int, Error>` | null → panic；关闭 → `Unavailable`；越界 → `InvalidArgument`；`PermissionDenied`/`Io`/`Cancelled`/`Timeout` |
| `write` | 写入区域 | `Context context, Long offsetBytes, Bytes payload` | `Result<Unit, Error>` | null → panic；关闭 → `Unavailable`；越界/未对齐 → `InvalidArgument`；未擦除 → `Io`/`InvalidArgument`；`PermissionDenied`/`Unsupported`/`Busy`/`Cancelled`/`Timeout` |
| `erase` | 擦除区域 | `Context context, Long offsetBytes, Long lengthBytes` | `Result<Unit, Error>` | null → panic；关闭 → `Unavailable`；越界/未对齐/长度≤0 → `InvalidArgument`；`PermissionDenied`/`Busy`/`Unsupported`/`Cancelled`/`Timeout` |
| `isErased` | 是否全为 0xFF | `Context context, Long offsetBytes, Long lengthBytes` | `Result<Bool, Error>` | null → panic；关闭 → `Unavailable`；越界 → `InvalidArgument`；`PermissionDenied`/`Unsupported`/`Io`/`Cancelled`/`Timeout` |
| `isOpen` | 是否打开 | 无 | `Bool` | 无 |
| `describe` | 单行审计摘要 | 无 | `String` | 无 |
| `close` | 关闭区域 | 无 | `Result<Unit, Error>` | `Io`（诊断） |

说明：

- `open`：`context == null`/`board == null`/`regionName == null` panic；`regionName` 空串、`offsetBytes <0`、`lengthBytes <=0`、`lengthBytes > board.flashBytes()`、`offsetBytes > board.flashBytes() - lengthBytes` → `InvalidArgument`；`board.flashBytes() == 0` → `Unsupported`；几何非法/区域未按擦除粒度对齐 → `InvalidArgument`；写保护 → `PermissionDenied`；控制器忙 → `Busy`。
- `read`：`buffer == null` panic；空 buffer 返回 `Ok(0)` 且不调用原生层；偏移/长度必须在区域内；返回实际读取字节数（成功时为 `buffer.length()`）；可阻塞，取消/超时透传；错误时 `buffer` 内容未定义。
- `write`：`payload == null` panic；空 payload 返回 `Ok(unit)`；偏移必须按 `writeSizeBytes` 对齐，长度必须是 `writeSizeBytes` 的整数倍；不得越过区域；不自动擦除；目标未擦除时适配器返回 `Io`/`InvalidArgument`；部分写后失败的区域内容未定义。
- `erase`：`lengthBytes <=0` → `InvalidArgument`；偏移/长度必须按 `eraseSizeBytes` 对齐；不得越过区域；成功后区域内容为 `0xFF`（基线 NOR Flash）；其它介质由适配器映射或返回 `Unsupported`；取消后内容未定义。
- `isErased`：偏移/长度必须在区域内；`lengthBytes == 0` 返回 `Ok(true)`；逐块读取比较 `0xFF`；发现非 `0xFF` 立即返回 `Ok(false)`；可取消；结果是瞬时观察，不是锁。
- `close`：第一次 `_open = false` 并调用原生关闭；后续 `Ok(unit)`；关闭失败返回 `Io`，状态仍视为关闭。
- 纯读取器关闭后仍可读；`describe` 返回包含区域名、起始、长度、页/擦除/写粒度的单行摘要，不含写入内容。
- 不提供 `writeErased`/`eraseAndWrite`/`flush`/`sync`/`partition`/`lock`：隐式组合/并发控制是 X 或 ecosystem。
- 不提供 `equals`/`copy`：区域是资源，不是值对象。

---

## 8. 使用的技术

- 不透明 `Long` 句柄；
- 有界区域与溢出安全边界检查；
- 擦除/写粒度对齐；
- 显式擦除与显式写；
- `isErased` 逐块验证；
- 审计标签；
- `Context`/`Result`；
- 幂等关闭；
- 非线程安全句柄。

---

## 9. 需要的支撑

- 语言：class、final/内部字段、Long、Int、Bool、String、Bytes、List、Result；
- 运行时/适配器：
  - `flashOpenRaw(Context context, Board board, String regionName, Long offsetBytes, Long lengthBytes) -> Result<List<Long>, Error>`；返回 `[handle, pageSizeBytes, eraseSizeBytes, writeSizeBytes]`；
  - `flashReadRaw(Context context, Long handle, Long offsetBytes, Bytes buffer) -> Result<Int, Error>`；
  - `flashWriteRaw(Context context, Long handle, Long offsetBytes, Bytes payload) -> Result<Unit, Error>`；
  - `flashEraseRaw(Context context, Long handle, Long offsetBytes, Long lengthBytes) -> Result<Unit, Error>`；
  - `flashCloseRaw(Long handle) -> Result<Unit, Error>`；
- 适配器负责：
  - 把区域映射到真实 Flash 地址；
  - 返回页/擦除/写粒度；
  - 校验对齐、写保护、控制器忙；
  - 执行前写审计日志（区域名、偏移、长度、操作类型），不记录内容；
  - 不隐式擦除；不把部分写/擦除失败伪装成成功；
  - 取消后的部分操作状态必须可诊断；
- 原生句柄必须 `>0`；`0`/负数在 `open` 中转为 `Internal`，构造器 panic；
- 接口：`Context`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`、`Bytes`、`Board`。

---

## 10. 依赖的特性/接口/类

`Context`、`Error`、`Bytes`、`Board`、`Embedded`。

相关但不同层：`xdk.fs`（文件/目录）、`xdk.io`（流）、`xdk.log`（审计/诊断）。本类型不提供文件系统/OTA/分区表；也不复制 `xdk.fs` 的路径/文件 API。

---

## 11. 所有权与并发

引用语义；区域由调用方持有并关闭；无全局注册表；无循环引用。`Board` 只在 `open` 时借用，不长期持有。
非线程安全：`read`/`write`/`erase`/`isErased`/`close` 不得并发；调用方需串行化，或确保关闭时没有其它调用。`close` 幂等指重复调用安全，不承诺并发 close 安全。
`Bytes` 归调用方；`read` 写入调用方缓冲区；`write` 不保留 payload 引用；返回的 `Int` 是计数。
无 `equals`/`copy`；不推荐作 `Map` 键；关闭后不得再读写擦除。

---

## 12. 示例与反例

正确：

```xnull
Result<FlashRegion, Error> opened = FlashRegion.open(
    context, board, "config", 0x08010000, 0x10000)
if opened.isOk() {
    FlashRegion region = opened.value()
    Result<Bool, Error> erased = region.isErased(context, 0, 4096)
    if erased.isOk() && !erased.value() {
        Result<Unit, Error> cleared = region.erase(context, 0, 4096)
    }
    Bytes payload = Bytes.alloc(256)
    Result<Unit, Error> written = region.write(context, 0, payload)
    Bytes buffer = Bytes.alloc(256)
    Result<Int, Error> readCount = region.read(context, 0, buffer)
    Result<Unit, Error> closed = region.close()
}
```

正确：写前 `isErased`/`erase`；按 `writeSizeBytes` 对齐；擦除/写入前记录区域名/偏移/长度；区域边界按 `eraseSizeBytes` 对齐。

反例：`write` 前不擦除；`offsetBytes + lengthBytes` 直接相加导致溢出；区域跨越其它分区；`erase` 长度不是擦除粒度整数倍；`read` 越界；把 `regionName` 当分区自动查找键；在日志中输出写入的密钥；多任务并发擦写同一区域；`close` 后继续写；用 `FlashRegion` 实现文件系统/OTA；取消擦除后假设区域仍是旧内容。

---

## 13. 测试场景义务

打开成功/`flashBytes == 0`/区域越界（起始、尾部、长度 0、负值）/溢出边界/区域未按擦除粒度对齐/几何非法/句柄 `<=0`/size `<=0`/无权限/写保护/占用/取消/超时；`read` 空 buffer/整块/跨页/尾部/越界/关闭后/取消；`write` 空 payload/对齐/未对齐/越界/未擦除/部分写失败/关闭后/取消；`erase` 长度 0/负值/未对齐/越界/成功/不可擦除/取消后内容未定义；`isErased` 全 `0xFF`/首个非 `0xFF`/空范围/越界/跨块/取消；`close` 幂等/关闭失败仍关闭/关闭后纯读取器；`describe` 不含内容；审计日志字段；多区域独立；桌面/无 Flash 平台 `Unsupported`；与 `Board.flashBytes()` 边界一致。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class FlashRegion {
    final Long _handle
    final String _name
    final Long _offsetBytes
    final Long _lengthBytes
    final Long _pageSizeBytes
    final Long _eraseSizeBytes
    final Long _writeSizeBytes
    Bool _open

    FlashRegion(Long handle, String name, Long offsetBytes, Long lengthBytes,
                Long pageSizeBytes, Long eraseSizeBytes,
                Long writeSizeBytes) {
        if handle == null || handle <= 0 {
            throw "FlashRegion: invalid handle"
        }
        if name == null || name.trim() == "" {
            throw "FlashRegion: empty name"
        }
        if offsetBytes < 0 || lengthBytes <= 0 {
            throw "FlashRegion: invalid region"
        }
        if pageSizeBytes <= 0 || eraseSizeBytes <= 0
            || writeSizeBytes <= 0 {
            throw "FlashRegion: invalid geometry"
        }
        if offsetBytes % eraseSizeBytes != 0
            || lengthBytes % eraseSizeBytes != 0 {
            throw "FlashRegion: unaligned region"
        }
        _handle = handle
        _name = name
        _offsetBytes = offsetBytes
        _lengthBytes = lengthBytes
        _pageSizeBytes = pageSizeBytes
        _eraseSizeBytes = eraseSizeBytes
        _writeSizeBytes = writeSizeBytes
        _open = true
    }

    static Result<FlashRegion, Error> open(Context context, Board board,
                                           String regionName,
                                           Long offsetBytes,
                                           Long lengthBytes) {
        if context == null || board == null || regionName == null {
            throw "FlashRegion.open: null argument"
        }
        if regionName.trim() == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "empty flash region name"))
        }
        if offsetBytes < 0 || lengthBytes <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "invalid flash region"))
        }
        if board.flashBytes() == 0 {
            return Err(new BasicError(ErrorKind.Unsupported,
                "board has no flash"))
        }
        if lengthBytes > board.flashBytes()
            || offsetBytes > board.flashBytes() - lengthBytes {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "flash region out of bounds"))
        }
        Result<List<Long>, Error> opened = flashOpenRaw(context, board,
            regionName, offsetBytes, lengthBytes)
        if opened.isErr() { return Err(opened.error()) }
        List<Long> geometry = opened.value()
        if geometry.length() != 4 {
            return Err(new BasicError(ErrorKind.Internal,
                "invalid flash geometry"))
        }
        Long handle = geometry.get(0)
        Long pageSizeBytes = geometry.get(1)
        Long eraseSizeBytes = geometry.get(2)
        Long writeSizeBytes = geometry.get(3)
        if handle <= 0 || pageSizeBytes <= 0 || eraseSizeBytes <= 0
            || writeSizeBytes <= 0 {
            if handle > 0 { flashCloseRaw(handle) }
            return Err(new BasicError(ErrorKind.Internal,
                "invalid flash geometry"))
        }
        if offsetBytes % eraseSizeBytes != 0
            || lengthBytes % eraseSizeBytes != 0 {
            flashCloseRaw(handle)
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "flash region not erase aligned"))
        }
        return Ok(new FlashRegion(handle, regionName, offsetBytes, lengthBytes,
            pageSizeBytes, eraseSizeBytes, writeSizeBytes))
    }

    String name() { return _name }
    Long offsetBytes() { return _offsetBytes }
    Long lengthBytes() { return _lengthBytes }
    Long pageSizeBytes() { return _pageSizeBytes }
    Long eraseSizeBytes() { return _eraseSizeBytes }
    Long writeSizeBytes() { return _writeSizeBytes }
    Bool isOpen() { return _open }

    Bool _checkRange(Long offsetBytes, Long lengthBytes) {
        if offsetBytes < 0 || lengthBytes < 0 {
            return false
        }
        if offsetBytes > _lengthBytes {
            return false
        }
        if lengthBytes > _lengthBytes - offsetBytes {
            return false
        }
        return true
    }

    Result<Int, Error> read(Context context, Long offsetBytes, Bytes buffer) {
        if context == null || buffer == null {
            throw "FlashRegion.read: null argument"
        }
        if !_open { return Err(unavailableError("flash region")) }
        if buffer.length() == 0 { return Ok(0) }
        if !_checkRange(offsetBytes, buffer.length() as Long) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "flash read out of range"))
        }
        return flashReadRaw(context, _handle, _offsetBytes + offsetBytes,
            buffer)
    }

    Result<Unit, Error> write(Context context, Long offsetBytes,
                              Bytes payload) {
        if context == null || payload == null {
            throw "FlashRegion.write: null argument"
        }
        if !_open { return Err(unavailableError("flash region")) }
        if payload.length() == 0 { return Ok(unit) }
        Long payloadLength = payload.length() as Long
        if offsetBytes < 0 || offsetBytes % _writeSizeBytes != 0
            || payloadLength % _writeSizeBytes != 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "flash write not aligned"))
        }
        if !_checkRange(offsetBytes, payloadLength) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "flash write out of range"))
        }
        return flashWriteRaw(context, _handle, _offsetBytes + offsetBytes,
            payload)
    }

    Result<Unit, Error> erase(Context context, Long offsetBytes,
                              Long lengthBytes) {
        if context == null {
            throw "FlashRegion.erase: null context"
        }
        if !_open { return Err(unavailableError("flash region")) }
        if lengthBytes <= 0 || offsetBytes < 0
            || offsetBytes % _eraseSizeBytes != 0
            || lengthBytes % _eraseSizeBytes != 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "flash erase not aligned"))
        }
        if !_checkRange(offsetBytes, lengthBytes) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "flash erase out of range"))
        }
        return flashEraseRaw(context, _handle, _offsetBytes + offsetBytes,
            lengthBytes)
    }

    Result<Bool, Error> isErased(Context context, Long offsetBytes,
                                 Long lengthBytes) {
        if context == null {
            throw "FlashRegion.isErased: null context"
        }
        if !_open { return Err(unavailableError("flash region")) }
        if lengthBytes < 0 || !_checkRange(offsetBytes, lengthBytes) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "flash range out of range"))
        }
        Long position = 0
        while position < lengthBytes {
            Long remaining = lengthBytes - position
            Int chunkLength = 256
            if remaining < 256 { chunkLength = remaining as Int }
            Bytes buffer = Bytes.alloc(chunkLength)
            Result<Int, Error> readResult = flashReadRaw(
                context, _handle, _offsetBytes + offsetBytes + position,
                buffer)
            if readResult.isErr() { return Err(readResult.error()) }
            Int index = 0
            while index < chunkLength {
                if buffer.get(index) != 255 { return Ok(false) }
                index = index + 1
            }
            position = position + (chunkLength as Long)
        }
        return Ok(true)
    }

    String describe() {
        return "flash " + _name + " offset=" + str(_offsetBytes)
            + " length=" + str(_lengthBytes)
            + " page=" + str(_pageSizeBytes)
            + " erase=" + str(_eraseSizeBytes)
            + " write=" + str(_writeSizeBytes)
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return flashCloseRaw(_handle)
    }
}
```
