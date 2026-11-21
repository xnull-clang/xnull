# `UartPort`

| 项 | 值 |
| --- | --- |
| 类型 | `class UartPort`（控制句柄） |
| 包 | `xdk.embedded` |
| 层 |  |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error`、`Bytes`、`BoardPin`、`PinCapability`、`SerialOptions` |

---

## 1. 定位

已打开的**板级 MCU UART 控制句柄**：绑定 TX/RX 引脚与精确复用功能，按 `SerialOptions` 读写字节、刷新输出、关闭、是否打开。

不做：OS 串口设备枚举/路径打开（用 [`SerialPort`](../../platform/serial/SerialPort.md)）、PTY、termios/DCB 原始设置、DTR/RTS/CTS/DSR 控制线、硬件/软件流控、RS-485/LIN/9 位模式、DMA、热插拔、协议解析（Modbus/GPS/NMEA）。

本类型解决“板上有 UART 外设但没有 OS 串口设备”的场景；`SerialPort` 解决“OS 已暴露 `/dev/tty*`/`COM*`”的场景。两者不互相替代，也不共享句柄。

---

## 2. 设计逻辑

- 为什么是 class：持有不透明句柄与打开状态，生命周期需要显式 `close`；不是值对象。
- 由静态 `UartPort.open(context, transmitPin, receivePin, transmitFunction, receiveFunction, options)` 创建；构造器主要供宿主/测试使用。
- `transmitPin` 必须具备 `PinCapability.UartTransmit`；`receivePin` 必须具备 `PinCapability.UartReceive`；两个复用功能名必须精确存在于对应引脚的 `alternateFunctions()` 中。
- `transmitFunction`/`receiveFunction` 是精确名称（如 `USART3_TX`/`USART3_RX`），大小写敏感；本类型不做前缀推导。适配器负责确认两个功能属于同一 UART 外设；不属于时返回 `InvalidArgument`/`Unsupported`。
- `options` 复用 `xdk.serial.SerialOptions`，不新增串口配置类型；波特率/数据位/校验/停止位/读超时/写超时语义与 `SerialPort` 一致。硬件组合是否支持由适配器判定。
- `read` 从索引 0 覆盖写入调用方缓冲区，最多 `buffer.length()` 字节；读超时返回 `Ok(0)`，不是 `Timeout`；空 buffer 返回 `Ok(0)` 且不调用原生层。
- `write` 从索引 0 读取，返回实际写入数；允许部分写；无进展超时 `Timeout`；有部分进展后超时 `Ok(writtenCount)`；空 buffer 返回 `Ok(0)`。
- `flush` 等待输出队列排空；使用 `writeTimeoutMillis`；超时 `Timeout`；不改变打开状态。
- 打开受 OS/适配器能力/权限门控：无 UART `Unsupported`，无权限 `PermissionDenied`，引脚/外设被占用 `Busy`，I/O `Io`。
- `close()` 幂等；关闭后 `transmitPin`/`receivePin`/`transmitFunction`/`receiveFunction`/`options`/`isOpen`/`close` 可用，`read`/`write`/`flush` 返回 `Unavailable`。
- 非线程安全；同一句柄的 `read`/`write`/`flush`/`close` 必须由调用方串行化。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_handle` | `Long` | final | `>0`；不透明句柄 |
| `_transmitPin` | `BoardPin` | final | 非 null；具备 `UartTransmit` |
| `_receivePin` | `BoardPin` | final | 非 null；具备 `UartReceive` |
| `_transmitFunction` | `String` | final | 非空；精确复用功能名 |
| `_receiveFunction` | `String` | final | 非空；精确复用功能名 |
| `_options` | `SerialOptions` | final | 非 null；不可变配置快照 |
| `_open` | `Bool` | 内部 | 是否打开 |

不变量：

- `_handle > 0`；两个引脚非 null 且方向能力正确；两个功能名非空且分别存在于对应引脚。
- `_options` 非 null；其字段已由 `SerialOptions` 构造器校验。
- 构造后 `_open = true`；`close` 后 `_open = false`；`close` 幂等。
- 关闭后不再调用原生读写/刷新/关闭原语；`_handle` 不复用、不持久化、不跨进程。
- `_transmitFunction`/`_receiveFunction` 属于同一 UART 外设由适配器保证；本类型不解析名称。

---

## 4. 生命周期

由 `UartPort.open` 创建；构造器主要供宿主/测试使用。调用方持有；调用方 `close()`；无 `deinit`/finalizer 依赖。关闭后对象终止，不提供重新打开；需要新波特率/引脚/复用功能时重新 `open`。关闭后只允许纯读取器与 `close`；`read`/`write`/`flush` 返回 `Unavailable`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `UartPort(Long handle, BoardPin transmitPin, BoardPin receivePin, String transmitFunction, String receiveFunction, SerialOptions options)` | handle、两个引脚、两个功能名、options | handle>0；引脚非 null 且方向能力正确；功能名非空且存在于对应引脚；options 非 null | 非法 → panic |
| `UartPort.open(Context context, BoardPin transmitPin, BoardPin receivePin, String transmitFunction, String receiveFunction, SerialOptions options)` | context、两个引脚、两个功能名、options | 同构造；适配器可拒绝硬件不支持的组合/同外设校验 | null → panic；空功能名 → `InvalidArgument`；能力/功能不匹配 → `Unsupported`/`InvalidArgument`；适配器失败透传 |

`open` 成功后返回打开对象；适配器返回句柄 `<=0` 视为内部错误，返回 `Internal`，不构造对象。

---

## 6. 字段表

见 §3；字段私有。`BoardPin` 与 `SerialOptions` 都是不可变值，复制引用；`_options` 不复制内部字段（其构造器已保证不可变）。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `open`（static） | 打开板级 UART | `Context context, BoardPin transmitPin, BoardPin receivePin, String transmitFunction, String receiveFunction, SerialOptions options` | `Result<UartPort, Error>` | null → panic；`InvalidArgument`/`Unsupported`/`PermissionDenied`/`Busy`/`Io`/`Cancelled`/`Timeout` |
| `transmitPin` | TX 引脚 | 无 | `BoardPin` | 无 |
| `receivePin` | RX 引脚 | 无 | `BoardPin` | 无 |
| `transmitFunction` | TX 复用功能 | 无 | `String` | 无 |
| `receiveFunction` | RX 复用功能 | 无 | `String` | 无 |
| `options` | 串口参数 | 无 | `SerialOptions` | 无 |
| `read` | 读取字节 | `Context context, Bytes buffer` | `Result<Int, Error>` | null → panic；关闭 → `Unavailable`；`PermissionDenied`/`Cancelled`/`Io` |
| `write` | 写入字节 | `Context context, Bytes buffer` | `Result<Int, Error>` | null → panic；关闭 → `Unavailable`；`PermissionDenied`/`Cancelled`/`Timeout`/`Io` |
| `flush` | 刷新输出 | `Context context` | `Result<Unit, Error>` | null → panic；关闭 → `Unavailable`；`PermissionDenied`/`Cancelled`/`Timeout`/`Io` |
| `close` | 关闭端口 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isOpen` | 是否打开 | 无 | `Bool` | 无 |

说明：

- `open`：`context == null`/任一引脚 null/任一功能名 null/`options == null` panic；功能名空串 → `InvalidArgument`；TX 引脚无 `UartTransmit` 或 RX 引脚无 `UartReceive` → `Unsupported`；功能名不在对应引脚 → `InvalidArgument`；两个功能不属于同一 UART 外设由适配器返回 `InvalidArgument`/`Unsupported`。
- `read`：从索引 0 覆盖写入 `buffer`，最多 `buffer.length()` 字节；返回 `0..buffer.length()`；读超时为 `Ok(0)`；空 buffer 返回 `Ok(0)` 且不调用原生层；关闭后 `Unavailable`；取消 → `Cancelled`。
- `write`：从索引 0 读取 `buffer`，返回实际写入字节数；允许部分写；写超时前没有任何进展 → `Timeout`；有部分进展后超时 → `Ok(writtenCount)`；空 buffer 返回 `Ok(0)`。
- `flush`：等待输出队列排空；超过 `options.writeTimeoutMillis()` → `Timeout`；取消 → `Cancelled`；不改变 `isOpen`。
- `close`：第一次标记关闭并调用原生关闭；原生失败返回 `Io`，但对象保持关闭；后续 `Ok(unit)`。`close` 不自动 `flush`；需要确保发送完成时先调用 `flush`。
- `transmitPin`/`receivePin`/`transmitFunction`/`receiveFunction`/`options` 关闭后仍可读。
- 不提供 `setOptions`/`setBaudRate`/`setControlLine`/`setFlowControl`/`path`/`ports`：重新打开或使用 `SerialPort`/X。
- 不提供 `describe`/`equals`/`copy`：端口是资源，不是值对象。

---

## 8. 使用的技术

- 不透明 `Long` 句柄；
- 引脚方向/复用功能名双重校验；
- 复用 `SerialOptions`；
- 读/写超时；
- 部分写与计数返回；
- `Context`/`Result`；
- 幂等关闭；
- 非线程安全句柄。

---

## 9. 需要的支撑

- 语言：class、final 字段、Long、Int、Bool、String、Bytes、Result；
- 运行时/适配器：
  - `uartOpenRaw(Context context, BoardPin transmitPin, BoardPin receivePin, String transmitFunction, String receiveFunction, SerialOptions options) -> Result<Long, Error>`；
  - `uartReadRaw(Context context, Long handle, Bytes buffer, Long timeoutMillis) -> Result<Int, Error>`；
  - `uartWriteRaw(Context context, Long handle, Bytes buffer, Long timeoutMillis) -> Result<Int, Error>`；
  - `uartFlushRaw(Context context, Long handle, Long timeoutMillis) -> Result<Unit, Error>`；
  - `uartCloseRaw(Long handle) -> Result<Unit, Error>`；
- 适配器负责：
  - 把引脚 + 复用功能名映射到 MCU UART 外设；
  - 校验两个功能属于同一外设；
  - 应用波特率/数据位/校验/停止位，拒绝不支持的组合；
  - 实现读/写超时与部分写语义；
- 原生句柄必须 `>0`；`0`/负数在 `open` 中转为 `Internal`，构造器 panic；
- 接口：`Context`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`、`Bytes`、`BoardPin`、`PinCapability`、`SerialOptions`。

---

## 10. 依赖的特性/接口/类

`Context`、`Error`、`Bytes`、`BoardPin`、`PinCapability`、`SerialOptions`、`SerialParity`、`SerialStopBits`、`Board`、`Embedded`。

相关但不同层：`xdk.serial.SerialPort`（OS 串口设备）、`xdk.serial.Serial`（端口枚举）、`xdk.device.GpioPin`（控制线/普通 GPIO）。本类型不复制枚举/路径 API，也不提供控制线/流控。

---

## 11. 所有权与并发

引用语义；端口由调用方持有并关闭；无全局注册表；无循环引用。`BoardPin`/`SerialOptions` 是借用/共享的不可变值。
非线程安全：`read`/`write`/`flush`/`close` 不得并发；调用方需串行化，或确保关闭时没有其它调用。`close` 幂等指重复调用安全，不承诺并发 close 安全。
`Bytes` 归调用方；方法不保留引用；输入字节借用，输出写入调用方缓冲区。
无 `equals`/`copy`；不推荐作 `Map` 键；关闭后不得再用端口。

---

## 12. 示例与反例

正确：

```xnull
BoardPin transmitPin = board.findPin("PA2")
BoardPin receivePin = board.findPin("PA3")
SerialOptions options = new SerialOptions(
    115200, 8, SerialParity.None, SerialStopBits.One, 1000, 1000)
Result<UartPort, Error> opened = UartPort.open(
    context, transmitPin, receivePin, "USART3_TX", "USART3_RX", options)
if opened.isOk() {
    UartPort port = opened.value()
    Bytes buffer = Bytes.alloc(64)
    Result<Int, Error> readResult = port.read(context, buffer)
    if readResult.isOk() && readResult.value() > 0 {
        Result<Int, Error> written = port.write(context, buffer)
    }
    Result<Unit, Error> closed = port.close()
}
```

正确：读超时 `Ok(0)` 后继续轮询；写部分成功后移动剩余区间重试；关闭前 `flush` 等待发送完成。

反例：有 OS 串口设备却用 `UartPort` 打开；引脚不支持 `UartTransmit` 却强行打开；功能名用 `USART3` 而不是 `USART3_TX`；TX/RX 来自不同外设；把 `read` 超时当 `Timeout`；忽略 `write` 的部分写；close 后继续读写；多任务并发读写同一端口；用 `UartPort` 设置 DTR/RTS；假设 `UartPort` 能枚举端口。

---

## 13. 测试场景义务

打开成功/空功能名/引脚能力不匹配/功能名不存在/功能名不同外设/options 非法/无权限/占用/取消/超时；`read` 有数据/超时 0/正超时/空 buffer/关闭后/取消；`write` 全写/部分写/超时无进展/空 buffer/关闭后；`flush` 成功/超时/取消；`close` 幂等/关闭失败仍关闭/关闭后 `Unavailable`；纯读取器关闭后；`options` 与 `SerialPort` 语义一致；`SerialOptions.OnePointFive`/`Mark` 不支持路径；桌面/无 UART 平台 `Unsupported`；原生句柄 `<=0` → `Internal`；与 `SerialPort` 的边界（不枚举、不按路径打开）。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class UartPort {
    final Long _handle
    final BoardPin _transmitPin
    final BoardPin _receivePin
    final String _transmitFunction
    final String _receiveFunction
    final SerialOptions _options
    Bool _open

    UartPort(Long handle, BoardPin transmitPin, BoardPin receivePin,
             String transmitFunction, String receiveFunction,
             SerialOptions options) {
        if handle == null || handle <= 0 {
            throw "UartPort: invalid handle"
        }
        if transmitPin == null
            || !transmitPin.supports(PinCapability.UartTransmit) {
            throw "UartPort: invalid transmit pin"
        }
        if receivePin == null
            || !receivePin.supports(PinCapability.UartReceive) {
            throw "UartPort: invalid receive pin"
        }
        if transmitFunction == null || transmitFunction.trim() == "" {
            throw "UartPort: empty transmit function"
        }
        if receiveFunction == null || receiveFunction.trim() == "" {
            throw "UartPort: empty receive function"
        }
        if !transmitPin.hasAlternateFunction(transmitFunction) {
            throw "UartPort: transmit function not on pin"
        }
        if !receivePin.hasAlternateFunction(receiveFunction) {
            throw "UartPort: receive function not on pin"
        }
        if options == null {
            throw "UartPort: null options"
        }
        _handle = handle
        _transmitPin = transmitPin
        _receivePin = receivePin
        _transmitFunction = transmitFunction
        _receiveFunction = receiveFunction
        _options = options
        _open = true
    }

    static Result<UartPort, Error> open(Context context, BoardPin transmitPin,
                                        BoardPin receivePin,
                                        String transmitFunction,
                                        String receiveFunction,
                                        SerialOptions options) {
        if context == null || transmitPin == null || receivePin == null
            || transmitFunction == null || receiveFunction == null
            || options == null {
            throw "UartPort.open: null argument"
        }
        if transmitFunction.trim() == "" || receiveFunction.trim() == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "empty uart function"))
        }
        if !transmitPin.supports(PinCapability.UartTransmit) {
            return Err(new BasicError(ErrorKind.Unsupported,
                "pin has no uart transmit capability"))
        }
        if !receivePin.supports(PinCapability.UartReceive) {
            return Err(new BasicError(ErrorKind.Unsupported,
                "pin has no uart receive capability"))
        }
        if !transmitPin.hasAlternateFunction(transmitFunction) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "transmit function not on pin"))
        }
        if !receivePin.hasAlternateFunction(receiveFunction) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "receive function not on pin"))
        }
        Result<Long, Error> opened = uartOpenRaw(context, transmitPin,
            receivePin, transmitFunction, receiveFunction, options)
        if opened.isErr() { return Err(opened.error()) }
        if opened.value() <= 0 {
            return Err(new BasicError(ErrorKind.Internal,
                "invalid uart handle"))
        }
        return Ok(new UartPort(opened.value(), transmitPin, receivePin,
            transmitFunction, receiveFunction, options))
    }

    BoardPin transmitPin() { return _transmitPin }
    BoardPin receivePin() { return _receivePin }
    String transmitFunction() { return _transmitFunction }
    String receiveFunction() { return _receiveFunction }
    SerialOptions options() { return _options }
    Bool isOpen() { return _open }

    Result<Int, Error> read(Context context, Bytes buffer) {
        if context == null || buffer == null {
            throw "UartPort.read: null argument"
        }
        if !_open { return Err(unavailableError("uart port")) }
        if buffer.length() == 0 { return Ok(0) }
        return uartReadRaw(context, _handle, buffer,
            _options.readTimeoutMillis())
    }

    Result<Int, Error> write(Context context, Bytes buffer) {
        if context == null || buffer == null {
            throw "UartPort.write: null argument"
        }
        if !_open { return Err(unavailableError("uart port")) }
        if buffer.length() == 0 { return Ok(0) }
        return uartWriteRaw(context, _handle, buffer,
            _options.writeTimeoutMillis())
    }

    Result<Unit, Error> flush(Context context) {
        if context == null { throw "UartPort.flush: null context" }
        if !_open { return Err(unavailableError("uart port")) }
        return uartFlushRaw(context, _handle,
            _options.writeTimeoutMillis())
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return uartCloseRaw(_handle)
    }
}
```
