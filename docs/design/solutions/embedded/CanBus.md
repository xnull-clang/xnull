# `CanBus`

| 项 | 值 |
| --- | --- |
| 类型 | `class CanBus`（控制句柄） |
| 包 | `xdk.embedded` |
| 层 |  |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error`、`Bytes`、`BoardPin`、`PinCapability` |

---

## 1. 定位

已打开的**经典 CAN 控制器句柄**：绑定 CAN TX/RX 引脚与复用功能，设置位率、启动/停止、添加/删除接收过滤器、发送/接收经典 CAN 帧、查询总线关闭与错误计数、总线恢复、关闭。

不做：CAN FD、ISO-TP、CANopen、J1939、时间触发 CAN、CAN 网关/路由、自动波特率、错误帧注入、裸寄存器/`ioctl`。协议栈与诊断层归 ecosystem。

---

## 2. 设计逻辑

- 为什么是 class：持有不透明句柄、启动状态与位率配置，生命周期需要显式 `close`；不是值对象。
- 由静态 `CanBus.open(context, transmitPin, receivePin, transmitFunction, receiveFunction, bitrateBitsPerSecond)` 创建；构造器主要供宿主/测试使用。
- TX 引脚必须具备 `PinCapability.CanTransmit`；RX 引脚必须具备 `PinCapability.CanReceive`；功能名必须精确存在于对应引脚（如 `CAN1_TX`/`CAN1_RX`）。
- 打开后控制器处于**停止**状态；必须显式 `start` 才参与总线。这样调用方可以先配置位率/过滤器，再启动。
- `setBitrate` 只允许在停止状态调用；已启动返回 `Busy`。位率单位 bit/s，`Long`，`>0`；采样点/时段参数不在基线，适配器使用合理默认或返回 `Unsupported`。
- `addFilter`/`removeFilter` 使用经典 CAN 标识符与掩码：匹配规则 `(receivedIdentifier & mask) == (identifier & mask)`；`isExtended` 决定 11 位/29 位域。过滤器 ID 由适配器分配，`>=0`，仅在当前句柄生命周期内有效。
- `send` 是经典 CAN 数据帧或远程请求帧：标准标识符 `0..0x7FF`，扩展标识符 `0..0x1FFFFFFF`，数据长度码 `0..8`，载荷 `0..8` 字节。数据帧要求 `dataLengthCode == payload.length()`；远程请求帧要求 `payload` 为空，`dataLengthCode` 表示请求的 DLC。`timeoutMillis` 0 = 非阻塞入队（无邮箱 `Busy`），正数 = 有界等待（`Timeout`）。
- `receive` 读取一帧到调用方缓冲区，返回**紧凑帧头** `[identifier, flags, payloadLength]`：
  - 索引 0 = 标识符；
  - 索引 1 = 标志位：位 0 = 扩展帧，位 1 = 远程请求帧；
  - 索引 2 = 载荷长度 `0..8`。
  空列表表示在 `timeoutMillis` 内没有帧（不是错误）；列表长度不是 0 或 3 视为适配器内部错误（`Internal`）。`payloadBuffer` 至少 8 字节；成功时前 `payloadLength` 字节有效，其余字节不承诺。
- 为什么用紧凑帧头而不是新增帧类型： embedded 基线的公开类型集固定；`List<Int>` 帧头足以表达经典 CAN 元数据，且不引入半成品帧对象。帧对象、CAN FD 元数据是 X。
- `busOff`/`receiveErrorCount`/`transmitErrorCount` 是诊断查询，可能触发硬件读取；首参 `Context`，失败 `Io`/`Unavailable`。
- 打开受 OS/适配器能力/权限门控：无 CAN `Unsupported`，无权限 `PermissionDenied`，引脚/控制器被占用 `Busy`，I/O `Io`。
- `close()` 幂等；若已启动，先尽力 `stop`，再释放句柄；`close` 不隐式保留过滤器。关闭后纯读取器与 `close` 可用，其余返回 `Unavailable`。
- 非线程安全；同一句柄的 `start`/`stop`/`setBitrate`/`addFilter`/`removeFilter`/`send`/`receive`/`recover`/`close` 必须由调用方串行化。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_handle` | `Long` | final | `>0`；不透明句柄 |
| `_transmitPin` | `BoardPin` | final | 非 null；具备 `CanTransmit` |
| `_receivePin` | `BoardPin` | final | 非 null；具备 `CanReceive` |
| `_transmitFunction` | `String` | final | 非空；精确复用功能名 |
| `_receiveFunction` | `String` | final | 非空；精确复用功能名 |
| `_bitrateBitsPerSecond` | `Long` | 内部 | `>0`；当前配置位率 |
| `_started` | `Bool` | 内部 | 控制器是否已启动 |
| `_open` | `Bool` | 内部 | 是否打开 |

不变量：

- `_handle > 0`；两个引脚非 null 且方向能力正确；两个功能名非空且分别存在于对应引脚。
- `_bitrateBitsPerSecond > 0`；构造后 `_started = false`、`_open = true`。
- `start` 成功后 `_started = true`；`stop` 成功后 `_started = false`；`close` 后 `_started = false`、`_open = false`。
- `close` 幂等；关闭后不再调用原生 CAN 原语；`_handle` 不复用、不持久化、不跨进程。
- `setBitrate` 只在 `_started = false` 时成功；`send`/`receive` 只在 `_open && _started` 时执行。
- 过滤器 ID 只在本句柄生命周期内有效；`close` 后全部失效。

---

## 4. 生命周期

由 `CanBus.open` 创建，初始停止；调用方配置位率/过滤器后 `start`；调用方 `stop`/`close`；无 `deinit`/finalizer 依赖。关闭后对象终止，不提供重新打开；需要新位率/引脚/会话时重新 `open`。关闭后只允许纯读取器与 `close`；`start`/`stop`/`setBitrate`/`addFilter`/`removeFilter`/`send`/`receive`/`recover`/诊断查询返回 `Unavailable`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `CanBus(Long handle, BoardPin transmitPin, BoardPin receivePin, String transmitFunction, String receiveFunction, Long bitrateBitsPerSecond)` | handle、两个引脚、两个功能名、位率 | handle>0；引脚非 null 且方向能力正确；功能名非空且存在于对应引脚；位率>0 | 非法 → panic |
| `CanBus.open(Context context, BoardPin transmitPin, BoardPin receivePin, String transmitFunction, String receiveFunction, Long bitrateBitsPerSecond)` | context、两个引脚、两个功能名、位率 | 同构造；适配器可拒绝硬件不支持的位率/引脚组合 | null → panic；空功能名/位率≤0 → `InvalidArgument`；能力/功能不匹配 → `Unsupported`/`InvalidArgument`；适配器失败透传 |

`open` 成功后返回停止状态的控制器；适配器返回句柄 `<=0` 视为内部错误，返回 `Internal`，不构造对象。

---

## 6. 字段表

见 §3；字段私有。`BoardPin` 是不可变值，复制引用；`_bitrateBitsPerSecond`/`_started`/`_open` 是句柄状态，不作为值对象共享。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `open`（static） | 打开 CAN 控制器 | `Context context, BoardPin transmitPin, BoardPin receivePin, String transmitFunction, String receiveFunction, Long bitrateBitsPerSecond` | `Result<CanBus, Error>` | null → panic；`InvalidArgument`/`Unsupported`/`PermissionDenied`/`Busy`/`Io`/`Cancelled`/`Timeout` |
| `transmitPin` | TX 引脚 | 无 | `BoardPin` | 无 |
| `receivePin` | RX 引脚 | 无 | `BoardPin` | 无 |
| `transmitFunction` | TX 复用功能 | 无 | `String` | 无 |
| `receiveFunction` | RX 复用功能 | 无 | `String` | 无 |
| `bitrateBitsPerSecond` | 当前位率 | 无 | `Long` | 无 |
| `isStarted` | 是否已启动 | 无 | `Bool` | 无 |
| `isOpen` | 是否打开 | 无 | `Bool` | 无 |
| `start` | 启动控制器 | `Context context` | `Result<Unit, Error>` | null → panic；关闭 → `Unavailable`；`Unsupported`/`Busy`/`Io`/`Cancelled`/`Timeout` |
| `stop` | 停止控制器 | `Context context` | `Result<Unit, Error>` | null → panic；关闭 → `Unavailable`；`Unsupported`/`Io`/`Cancelled`/`Timeout` |
| `setBitrate` | 设置位率 | `Context context, Long bitrateBitsPerSecond` | `Result<Unit, Error>` | null → panic；关闭/已启动 → `Unavailable`/`Busy`；位率≤0 → `InvalidArgument`；`Unsupported`/`Io`/`Cancelled`/`Timeout` |
| `addFilter` | 添加接收过滤器 | `Context context, Int identifier, Int mask, Bool isExtended` | `Result<Int, Error>` | null → panic；关闭 → `Unavailable`；标识符/掩码越界 → `InvalidArgument`；`Busy`/`Unsupported`/`Io` |
| `removeFilter` | 删除接收过滤器 | `Context context, Int filterIdentifier` | `Result<Unit, Error>` | null → panic；关闭 → `Unavailable`；负 ID → `InvalidArgument`；未知 ID → `NotFound`；`Io` |
| `send` | 发送经典帧 | `Context context, Int identifier, Bool isExtended, Bool isRemoteRequest, Int dataLengthCode, Bytes payload, Long timeoutMillis` | `Result<Unit, Error>` | null → panic；关闭/未启动 → `Unavailable`；标识符/载荷/DLC/超时非法 → `InvalidArgument`；`Busy`/`Timeout`/`Cancelled`/`Io` |
| `receive` | 接收一帧 | `Context context, Long timeoutMillis, Bytes payloadBuffer` | `Result<List<Int>, Error>` | null → panic；关闭/未启动 → `Unavailable`；缓冲区<8/超时<0 → `InvalidArgument`；`Cancelled`/`Io`/`DataCorrupted` |
| `busOff` | 是否总线关闭 | `Context context` | `Result<Bool, Error>` | null → panic；关闭 → `Unavailable`；`Unsupported`/`Io`/`Cancelled` |
| `receiveErrorCount` | 接收错误计数 | `Context context` | `Result<Int, Error>` | null → panic；关闭 → `Unavailable`；`Unsupported`/`Io`/`Cancelled` |
| `transmitErrorCount` | 发送错误计数 | `Context context` | `Result<Int, Error>` | null → panic；关闭 → `Unavailable`；`Unsupported`/`Io`/`Cancelled` |
| `recover` | 从总线关闭恢复 | `Context context` | `Result<Unit, Error>` | null → panic；关闭 → `Unavailable`；`Unsupported`/`Busy`/`Io`/`Cancelled`/`Timeout` |
| `close` | 停止并关闭 | 无 | `Result<Unit, Error>` | `Io`/`Unsupported`（诊断） |

说明：

- `open`：`context == null`/任一引脚 null/任一功能名 null/`bitrateBitsPerSecond == null` panic；功能名空串/位率≤0 → `InvalidArgument`；TX 引脚无 `CanTransmit` 或 RX 引脚无 `CanReceive` → `Unsupported`；功能名不在对应引脚 → `InvalidArgument`；两个功能不属于同一 CAN 控制器由适配器返回 `InvalidArgument`/`Unsupported`。
- `start`：关闭后 `Unavailable`；已启动返回 `Ok(unit)`（幂等）；成功后 `_started = true`；可阻塞，取消/超时透传。
- `stop`：关闭后 `Unavailable`；未启动返回 `Ok(unit)`；成功后 `_started = false`；停止会丢弃未发送帧/未读帧，由适配器决定；不清理过滤器配置（下次 `start` 仍生效），`close` 才清理。
- `setBitrate`：关闭后 `Unavailable`；已启动 `Busy`；位率≤0 `InvalidArgument`；成功后更新缓存；不自动重启。
- `addFilter`：关闭后 `Unavailable`；`identifier` 与 `mask` 必须在范围内：`isExtended` 为 `true` 时 `0..0x1FFFFFFF`，否则 `0..0x7FF`；`mask` 为 0 表示匹配所有；适配器可因过滤器槽位耗尽返回 `Busy`；成功返回 `>=0` 的过滤器 ID；`addFilter` 可在启动前或启动后调用。
- `removeFilter`：关闭后 `Unavailable`；负 ID `InvalidArgument`；未知 ID `NotFound`；删除后该 ID 不再有效。
- `send`：关闭/未启动 `Unavailable`；标识符越界、`dataLengthCode` 不在 `0..8`、数据帧载荷长度与 DLC 不一致、远程请求带载荷、超时<0 → `InvalidArgument`；`timeoutMillis == 0` 且无发送邮箱 → `Busy`；正超时无进展 → `Timeout`；取消 → `Cancelled`；不提供 CAN FD 标志。
- `receive`：关闭/未启动 `Unavailable`；`payloadBuffer.length() < 8` 或 `timeoutMillis < 0` → `InvalidArgument`；`timeoutMillis == 0` 为非阻塞，返回空列表表示无帧；正超时无帧返回空列表（不是 `Timeout`，与 `SerialPort.read` 的 `Ok(0)` 语义对齐）；取消 → `Cancelled`；帧头长度异常 → `Internal`；载荷/帧头不一致 → `DataCorrupted`；远程请求帧的 `payloadLength` 表示请求长度，`payloadBuffer` 不写入载荷。
- `busOff`/错误计数：关闭后 `Unavailable`；适配器不支持错误计数返回 `Unsupported`；计数是瞬时诊断值，不用于安全联锁。
- `recover`：关闭后 `Unavailable`；未处于总线关闭时返回 `Ok(unit)`（幂等）；需要等待硬件恢复时正超时，超时 `Timeout`；适配器可返回 `Unsupported`。
- `close`：第一次标记关闭；若已启动先调用原生 `canStopOnCloseRaw`（尽力），再 `canCloseRaw`；`stop` 失败仍继续关闭，返回第一个错误（可能是 `Io`/`Unsupported`）；后续 `Ok(unit)`；关闭失败返回 `Io`/`Unsupported`，状态仍视为关闭。
- 纯读取器关闭后仍返回最后配置值；关闭后不得再发送/接收。

---

## 8. 使用的技术

- 不透明 `Long` 句柄；
- 引脚方向/复用功能名双重校验；
- 经典 CAN 标识符/掩码过滤；
- 紧凑帧头（`List<Int>`）；
- 位率配置与启动/停止状态；
- 部分 I/O 超时与取消；
- `Context`/`Result`；
- 幂等关闭；
- 非线程安全句柄。

---

## 9. 需要的支撑

- 语言：class、final/内部字段、Long、Int、Bool、String、Bytes、List、Result；
- 运行时/适配器：
  - `canOpenRaw(Context context, BoardPin transmitPin, BoardPin receivePin, String transmitFunction, String receiveFunction, Long bitrateBitsPerSecond) -> Result<Long, Error>`；
  - `canStartRaw(Context context, Long handle) -> Result<Unit, Error>`；
  - `canStopRaw(Context context, Long handle) -> Result<Unit, Error>`；
  - `canStopOnCloseRaw(Long handle) -> Result<Unit, Error>`；`close` 专用、无 `Context`、不得阻塞；
  - `canSetBitrateRaw(Context context, Long handle, Long bitrateBitsPerSecond) -> Result<Unit, Error>`；
  - `canAddFilterRaw(Context context, Long handle, Int identifier, Int mask, Bool isExtended) -> Result<Int, Error>`；
  - `canRemoveFilterRaw(Context context, Long handle, Int filterIdentifier) -> Result<Unit, Error>`；
  - `canSendRaw(Context context, Long handle, Int identifier, Bool isExtended, Bool isRemoteRequest, Int dataLengthCode, Bytes payload, Long timeoutMillis) -> Result<Unit, Error>`；
  - `canReceiveRaw(Context context, Long handle, Long timeoutMillis, Bytes payloadBuffer) -> Result<List<Int>, Error>`；返回 `[identifier, flags, payloadLength]` 或空列表；成功时把载荷写入 `payloadBuffer` 前 `payloadLength` 字节；
  - `canBusOffRaw(Context context, Long handle) -> Result<Bool, Error>`；
  - `canErrorCountsRaw(Context context, Long handle) -> Result<List<Int>, Error>`；返回 `[receiveErrorCount, transmitErrorCount]`；
  - `canRecoverRaw(Context context, Long handle) -> Result<Unit, Error>`；
  - `canCloseRaw(Long handle) -> Result<Unit, Error>`；
- 适配器负责：
  - 把引脚 + 复用功能名映射到 MCU CAN 控制器；
  - 校验两个功能属于同一控制器；
  - 应用位率，拒绝不支持的位率；
  - 过滤器槽位管理与 ID 分配；
  - 经典 CAN 帧格式、远程请求、超时/邮箱/总线关闭语义；
  - 帧头长度/载荷长度校验，异常转 `Internal`/`DataCorrupted`；
- 原生句柄必须 `>0`；`0`/负数在 `open` 中转为 `Internal`，构造器 panic；
- 接口：`Context`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`、`Bytes`、`BoardPin`、`PinCapability`。

---

## 10. 依赖的特性/接口/类

`Context`、`Error`、`Bytes`、`BoardPin`、`PinCapability`、`Board`、`Embedded`。

相关但不同层：`xdk.device.GpioPin`（CAN 收发器使能/待机引脚）、`xdk.device.SpiBus`（外部 CAN 控制器，如 MCP2515）。本类型不复制 SPI 控制 API；外部 CAN 控制器通过 SPI 由 ecosystem 驱动，或由适配器封装为 `CanBus`。

---

## 11. 所有权与并发

引用语义；控制器由调用方持有并关闭；无全局注册表；无循环引用。`BoardPin` 是借用/共享的不可变值。
非线程安全：`start`/`stop`/`setBitrate`/`addFilter`/`removeFilter`/`send`/`receive`/`recover`/诊断查询/`close` 不得并发；调用方需串行化，或确保关闭时没有其它调用。`close` 幂等指重复调用安全，不承诺并发 close 安全。
`Bytes` 归调用方；`send` 不保留载荷引用；`receive` 写入调用方缓冲区，返回的帧头列表归调用方。
无 `equals`/`copy`；不推荐作 `Map` 键；关闭后不得再用控制器。

---

## 12. 示例与反例

正确：

```xnull
Result<CanBus, Error> opened = CanBus.open(
    context, board.findPin("PA11"), board.findPin("PA12"),
    "CAN1_TX", "CAN1_RX", 500000)
if opened.isOk() {
    CanBus bus = opened.value()
    Result<Int, Error> filter = bus.addFilter(context, 0x123, 0x7FF, false)
    Result<Unit, Error> started = bus.start(context)
    Bytes payload = Bytes.alloc(8)
    Result<Unit, Error> sent = bus.send(
        context, 0x123, false, false, 8, payload, 100)
    Bytes receiveBuffer = Bytes.alloc(8)
    Result<List<Int>, Error> header = bus.receive(context, 100, receiveBuffer)
    if header.isOk() && header.value().length() == 3 {
        Int identifier = header.value().get(0)
        Int flags = header.value().get(1)
        Int payloadLength = header.value().get(2)
    }
    Result<Unit, Error> closed = bus.close()
}
```

正确：过滤器掩码 `0x7FF` 精确匹配标准帧；`mask = 0` 匹配所有；帧头空列表表示超时无帧；远程请求帧载荷为空且用 `dataLengthCode` 表示请求长度；数据帧 `dataLengthCode` 必须等于载荷长度。

反例：打开后不 `start` 就发送；`setBitrate` 在已启动时调用；标准帧标识符 `0x800`；扩展帧标识符超过 `0x1FFFFFFF`；`dataLengthCode` 9；数据帧 DLC 与载荷长度不一致；远程请求带载荷；把 `receive` 空列表当错误；把 `List<Int>` 帧头当长期存储格式；close 后继续发送；多任务并发收发同一控制器；用 `CanBus` 实现 CANopen/J1939；期望 CAN FD。

---

## 13. 测试场景义务

打开成功/空功能名/引脚能力不匹配/功能名不存在/功能名不同控制器/位率 `0`/负值/无权限/占用/取消/超时；`start`/`stop` 幂等/关闭后/取消；`setBitrate` 停止时成功/启动时 `Busy`/位率非法/关闭后；`addFilter` 标准/扩展/掩码 0/越界/槽位耗尽/关闭后；`removeFilter` 已存在/未知/负 ID/关闭后；`send` 标准/扩展/远程/数据帧 DLC 0..8/远程 DLC 0..8/数据帧 DLC 与载荷不匹配/载荷 9 字节/标识符边界/超时 0/正超时/取消/未启动/关闭后；`receive` 有帧/无帧/空列表/帧头长度异常/缓冲区<8/超时 0/正超时/取消/未启动/关闭后；`busOff`/错误计数/`recover` 幂等/不支持；`close` 启动时先停止/停止失败仍关闭/幂等/关闭后纯读取器；过滤器 ID 生命周期；桌面/无 CAN 平台 `Unsupported`；原生句柄 `<=0` → `Internal`；与 `BoardPin` 能力一致性。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class CanBus {
    final Long _handle
    final BoardPin _transmitPin
    final BoardPin _receivePin
    final String _transmitFunction
    final String _receiveFunction
    Long _bitrateBitsPerSecond
    Bool _started
    Bool _open

    CanBus(Long handle, BoardPin transmitPin, BoardPin receivePin,
           String transmitFunction, String receiveFunction,
           Long bitrateBitsPerSecond) {
        if handle == null || handle <= 0 {
            throw "CanBus: invalid handle"
        }
        if transmitPin == null
            || !transmitPin.supports(PinCapability.CanTransmit) {
            throw "CanBus: invalid transmit pin"
        }
        if receivePin == null
            || !receivePin.supports(PinCapability.CanReceive) {
            throw "CanBus: invalid receive pin"
        }
        if transmitFunction == null || transmitFunction.trim() == "" {
            throw "CanBus: empty transmit function"
        }
        if receiveFunction == null || receiveFunction.trim() == "" {
            throw "CanBus: empty receive function"
        }
        if !transmitPin.hasAlternateFunction(transmitFunction) {
            throw "CanBus: transmit function not on pin"
        }
        if !receivePin.hasAlternateFunction(receiveFunction) {
            throw "CanBus: receive function not on pin"
        }
        if bitrateBitsPerSecond <= 0 {
            throw "CanBus: invalid bitrate"
        }
        _handle = handle
        _transmitPin = transmitPin
        _receivePin = receivePin
        _transmitFunction = transmitFunction
        _receiveFunction = receiveFunction
        _bitrateBitsPerSecond = bitrateBitsPerSecond
        _started = false
        _open = true
    }

    static Result<CanBus, Error> open(Context context, BoardPin transmitPin,
                                      BoardPin receivePin,
                                      String transmitFunction,
                                      String receiveFunction,
                                      Long bitrateBitsPerSecond) {
        if context == null || transmitPin == null || receivePin == null
            || transmitFunction == null || receiveFunction == null
            || bitrateBitsPerSecond == null {
            throw "CanBus.open: null argument"
        }
        if transmitFunction.trim() == "" || receiveFunction.trim() == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "empty can function"))
        }
        if bitrateBitsPerSecond <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "invalid can bitrate"))
        }
        if !transmitPin.supports(PinCapability.CanTransmit) {
            return Err(new BasicError(ErrorKind.Unsupported,
                "pin has no can transmit capability"))
        }
        if !receivePin.supports(PinCapability.CanReceive) {
            return Err(new BasicError(ErrorKind.Unsupported,
                "pin has no can receive capability"))
        }
        if !transmitPin.hasAlternateFunction(transmitFunction) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "transmit function not on pin"))
        }
        if !receivePin.hasAlternateFunction(receiveFunction) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "receive function not on pin"))
        }
        Result<Long, Error> opened = canOpenRaw(context, transmitPin,
            receivePin, transmitFunction, receiveFunction,
            bitrateBitsPerSecond)
        if opened.isErr() { return Err(opened.error()) }
        if opened.value() <= 0 {
            return Err(new BasicError(ErrorKind.Internal,
                "invalid can handle"))
        }
        return Ok(new CanBus(opened.value(), transmitPin, receivePin,
            transmitFunction, receiveFunction, bitrateBitsPerSecond))
    }

    BoardPin transmitPin() { return _transmitPin }
    BoardPin receivePin() { return _receivePin }
    String transmitFunction() { return _transmitFunction }
    String receiveFunction() { return _receiveFunction }
    Long bitrateBitsPerSecond() { return _bitrateBitsPerSecond }
    Bool isStarted() { return _started }
    Bool isOpen() { return _open }

    Result<Unit, Error> start(Context context) {
        if context == null { throw "CanBus.start: null context" }
        if !_open { return Err(unavailableError("can bus")) }
        if _started { return Ok(unit) }
        Result<Unit, Error> started = canStartRaw(context, _handle)
        if started.isErr() { return Err(started.error()) }
        _started = true
        return Ok(unit)
    }

    Result<Unit, Error> stop(Context context) {
        if context == null { throw "CanBus.stop: null context" }
        if !_open { return Err(unavailableError("can bus")) }
        if !_started { return Ok(unit) }
        Result<Unit, Error> stopped = canStopRaw(context, _handle)
        if stopped.isErr() { return Err(stopped.error()) }
        _started = false
        return Ok(unit)
    }

    Result<Unit, Error> setBitrate(Context context,
                                   Long bitrateBitsPerSecond) {
        if context == null { throw "CanBus.setBitrate: null context" }
        if !_open { return Err(unavailableError("can bus")) }
        if _started {
            return Err(new BasicError(ErrorKind.Busy,
                "can bus is started"))
        }
        if bitrateBitsPerSecond <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "invalid can bitrate"))
        }
        Result<Unit, Error> changed = canSetBitrateRaw(
            context, _handle, bitrateBitsPerSecond)
        if changed.isErr() { return Err(changed.error()) }
        _bitrateBitsPerSecond = bitrateBitsPerSecond
        return Ok(unit)
    }

    Result<Int, Error> addFilter(Context context, Int identifier, Int mask,
                                 Bool isExtended) {
        if context == null { throw "CanBus.addFilter: null context" }
        if !_open { return Err(unavailableError("can bus")) }
        Long identifierValue = identifier as Long
        Long maskValue = mask as Long
        Long maximumIdentifier = 0x7FF
        if isExtended { maximumIdentifier = 0x1FFFFFFF }
        if identifierValue < 0 || identifierValue > maximumIdentifier {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "can identifier out of range"))
        }
        if maskValue < 0 || maskValue > maximumIdentifier {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "can mask out of range"))
        }
        Result<Int, Error> added = canAddFilterRaw(
            context, _handle, identifier, mask, isExtended)
        if added.isErr() { return Err(added.error()) }
        if added.value() < 0 {
            return Err(new BasicError(ErrorKind.Internal,
                "invalid can filter identifier"))
        }
        return Ok(added.value())
    }

    Result<Unit, Error> removeFilter(Context context, Int filterIdentifier) {
        if context == null { throw "CanBus.removeFilter: null context" }
        if !_open { return Err(unavailableError("can bus")) }
        if filterIdentifier < 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "negative can filter identifier"))
        }
        return canRemoveFilterRaw(context, _handle, filterIdentifier)
    }

    Result<Unit, Error> send(Context context, Int identifier,
                             Bool isExtended, Bool isRemoteRequest,
                             Int dataLengthCode, Bytes payload,
                             Long timeoutMillis) {
        if context == null || payload == null {
            throw "CanBus.send: null argument"
        }
        if !_open || !_started {
            return Err(unavailableError("can bus"))
        }
        Long identifierValue = identifier as Long
        Long maximumIdentifier = 0x7FF
        if isExtended { maximumIdentifier = 0x1FFFFFFF }
        if identifierValue < 0 || identifierValue > maximumIdentifier {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "can identifier out of range"))
        }
        if dataLengthCode < 0 || dataLengthCode > 8 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "can data length code out of range"))
        }
        if isRemoteRequest {
            if payload.length() != 0 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "remote frame with payload"))
            }
        } else {
            if payload.length() != dataLengthCode {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "can payload length does not match dlc"))
            }
        }
        if timeoutMillis < 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "negative can timeout"))
        }
        return canSendRaw(context, _handle, identifier, isExtended,
            isRemoteRequest, dataLengthCode, payload, timeoutMillis)
    }

    Result<List<Int>, Error> receive(Context context, Long timeoutMillis,
                                     Bytes payloadBuffer) {
        if context == null || payloadBuffer == null {
            throw "CanBus.receive: null argument"
        }
        if !_open || !_started {
            return Err(unavailableError("can bus"))
        }
        if timeoutMillis < 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "negative can timeout"))
        }
        if payloadBuffer.length() < 8 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "can payload buffer too small"))
        }
        Result<List<Int>, Error> received = canReceiveRaw(
            context, _handle, timeoutMillis, payloadBuffer)
        if received.isErr() { return Err(received.error()) }
        List<Int> header = received.value()
        if header.length() == 0 { return Ok([]) }
        if header.length() != 3 {
            return Err(new BasicError(ErrorKind.Internal,
                "invalid can frame header"))
        }
        Int payloadLength = header.get(2)
        Int headerIdentifier = header.get(0)
        Int headerFlags = header.get(1)
        if headerFlags < 0 || headerFlags > 3 {
            return Err(new BasicError(ErrorKind.DataCorrupted,
                "invalid can frame flags"))
        }
        Long maximumIdentifier = 0x7FF
        if (headerFlags & 1) != 0 { maximumIdentifier = 0x1FFFFFFF }
        Long headerIdentifierValue = headerIdentifier as Long
        if headerIdentifierValue < 0
            || headerIdentifierValue > maximumIdentifier {
            return Err(new BasicError(ErrorKind.DataCorrupted,
                "invalid can frame identifier"))
        }
        if payloadLength < 0 || payloadLength > 8 {
            return Err(new BasicError(ErrorKind.DataCorrupted,
                "invalid can payload length"))
        }
        return Ok(header.copy())
    }

    Result<Bool, Error> busOff(Context context) {
        if context == null { throw "CanBus.busOff: null context" }
        if !_open { return Err(unavailableError("can bus")) }
        return canBusOffRaw(context, _handle)
    }

    Result<Int, Error> receiveErrorCount(Context context) {
        if context == null {
            throw "CanBus.receiveErrorCount: null context"
        }
        if !_open { return Err(unavailableError("can bus")) }
        Result<List<Int>, Error> counts = canErrorCountsRaw(context, _handle)
        if counts.isErr() { return Err(counts.error()) }
        if counts.value().length() != 2 {
            return Err(new BasicError(ErrorKind.Internal,
                "invalid can error counts"))
        }
        return Ok(counts.value().get(0))
    }

    Result<Int, Error> transmitErrorCount(Context context) {
        if context == null {
            throw "CanBus.transmitErrorCount: null context"
        }
        if !_open { return Err(unavailableError("can bus")) }
        Result<List<Int>, Error> counts = canErrorCountsRaw(context, _handle)
        if counts.isErr() { return Err(counts.error()) }
        if counts.value().length() != 2 {
            return Err(new BasicError(ErrorKind.Internal,
                "invalid can error counts"))
        }
        return Ok(counts.value().get(1))
    }

    Result<Unit, Error> recover(Context context) {
        if context == null { throw "CanBus.recover: null context" }
        if !_open { return Err(unavailableError("can bus")) }
        return canRecoverRaw(context, _handle)
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        Bool wasStarted = _started
        _open = false
        _started = false
        Result<Unit, Error> stopResult = Ok(unit)
        if wasStarted {
            stopResult = canStopOnCloseRaw(_handle)
        }
        Result<Unit, Error> closeResult = canCloseRaw(_handle)
        if stopResult.isErr() { return stopResult }
        return closeResult
    }
}
```
