# `SerialPort`

| 项 | 值 |
| --- | --- |
| 类型 | `class SerialPort` |
| 包 | `xdk.serial` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error`、`Bytes`、`SerialOptions` |

---

## 1. 定位

已打开串口的生命周期句柄：读写、刷新输出、关闭、是否可用；静态 `open` 负责打开。

不做：PTY、termios 原始设置、控制线（DTR/RTS/CTS/DSR）、流控、独占锁、热插拔事件、驱动/厂商 SDK。

---

## 2. 设计逻辑

- `_handle` 是 `Long` 不透明句柄；不暴露裸 fd/指针/驱动句柄。
- 由 `SerialPort.open(context, devicePath, options)` 创建；构造器主要供宿主/测试使用。
- 打开时保存不可变 `devicePath` 与 `SerialOptions`；`read`/`write`/`flush` 使用其中的超时。
- `read`/`write` 返回实际处理字节数 `Int`；`read` 超时返回 `Ok(0)`，`write` 无进展超时返回 `Timeout`。
- `close()` 幂等：第一次关闭后 `_open = false`；后续返回 `Ok(unit)`；关闭失败仍视为已关闭，错误只诊断。
- 关闭后 `read`/`write`/`flush` 返回 `Unavailable`；`path`/`isOpen` 仍可读。
- 非线程安全；`read`/`write`/`flush`/`close` 必须由调用方串行化。
- 平台不支持串口时 `open` 返回 `Unsupported`；权限不足返回 `PermissionDenied`，不重试、不提权。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_handle` | `Long` | final | `>0`；不透明 |
| `_path` | `String` | final | 非空；打开时的设备路径 |
| `_options` | `SerialOptions` | final | 非 null；打开参数快照 |
| `_open` | `Bool` | 内部 | 是否可用 |

不变量：handle>0；path 非空；options 非 null；打开时 `_open=true`；关闭后 `_open=false`；close 幂等；句柄不跨进程、不持久化。

---

## 4. 生命周期

由 `SerialPort.open` 创建；调用方持有；调用方 `close()`；close 幂等；无 `deinit` 依赖。
关闭后只允许 `path`/`isOpen`/`close`；其余操作返回 `Unavailable`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `SerialPort(Long handle, String path, SerialOptions options)` | handle、path、options | handle>0；path 非空；options 非 null | 非法 → panic |
| `SerialPort.open(Context context, String devicePath, SerialOptions options)` | context、devicePath、options | context/options 非 null；devicePath 非空 | null → panic；空路径 → `InvalidArgument`；打开失败 → `Result` |

构造器主要供宿主/测试使用；业务代码通过静态 `open` 获取。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `open`（static） | 打开串口 | `Context context, String devicePath, SerialOptions options` | `Result<SerialPort, Error>` | `InvalidArgument`/`NotFound`/`PermissionDenied`/`Busy`/`Unsupported`/`Cancelled`/`Io` |
| `path` | 设备路径 | 无 | `String` | 无 |
| `read` | 读取字节 | `Context context, Bytes buffer` | `Result<Int, Error>` | `Unavailable`/`PermissionDenied`/`Cancelled`/`Io` |
| `write` | 写入字节 | `Context context, Bytes buffer` | `Result<Int, Error>` | `Unavailable`/`PermissionDenied`/`Cancelled`/`Timeout`/`Io` |
| `flush` | 刷新输出 | `Context context` | `Result<Unit, Error>` | `Unavailable`/`PermissionDenied`/`Cancelled`/`Timeout`/`Io` |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |

说明：

- `open`：`context == null`/`options == null`/`devicePath == null` panic；空白路径返回 `InvalidArgument`；不预先枚举，也不检查端口是否在 `Serial.ports` 列表中；OS 可能允许共享打开，也可能返回 `Busy`，不做独占承诺。
- `read`：从索引 0 开始覆盖写入 `buffer`，最多写入 `buffer.length()` 字节；返回 `0..buffer.length()`。读超时为 `Ok(0)`；空 buffer 返回 `Ok(0)` 且不调用原生层；关闭后 `Unavailable`；取消 → `Cancelled`。
- `write`：从索引 0 开始读取 `buffer`，返回实际写入字节数 `0..buffer.length()`；允许部分写。写超时前没有任何进展 → `Timeout`；有部分进展后超时 → `Ok(writtenCount)`，调用方重试剩余部分；空 buffer 返回 `Ok(0)` 且不调用原生层。
- `flush`：等待输出队列排空；超过 `writeTimeoutMillis` → `Timeout`；取消 → `Cancelled`；不改变 `isOpen`。
- `close`：幂等；第一次标记关闭并调用原生关闭；原生失败返回 `Io`，但对象保持关闭；后续返回 `Ok(unit)`。
- `path`：返回打开时的设备路径，关闭后仍可读。
- `isOpen`：纯读取 `_open`；不触碰原生句柄。
- 所有可阻塞方法首参 `Context`；`context == null` 是合同错误。
- 不提供控制线、波特率重配、流控、原始 termios、PTY；这些是 X。

---

## 8. 使用的技术

- 不透明 `Long` 句柄；
- `Context`/`Result`；
- 读/写超时；
- 部分写与计数返回；
- 幂等关闭；
- 非线程安全句柄。

---

## 9. 需要的支撑

- 语言：class、final 字段、Long、Int、Bool、String、Bytes、Result；
- 运行时/适配器：
  - `serialOpenRaw(Context context, String devicePath, SerialOptions options) -> Result<Long, Error>`；
  - `serialReadRaw(Context context, Long handle, Bytes buffer, Long timeoutMillis) -> Result<Int, Error>`；
  - `serialWriteRaw(Context context, Long handle, Bytes buffer, Long timeoutMillis) -> Result<Int, Error>`；
  - `serialFlushRaw(Context context, Long handle, Long timeoutMillis) -> Result<Unit, Error>`；
  - `serialCloseRaw(Long handle) -> Result<Unit, Error>`；
- 原生句柄必须 >0；0/负数在 `open` 中转为 `Io`，构造器 panic；
- 接口：`Context`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`、`Bytes`、`SerialOptions`。

---

## 10. 依赖的特性/接口/类

`Context`、`Error`、`Bytes`、`SerialOptions`、`SerialPortInfo`、`Serial`、`SerialParity`、`SerialStopBits`。

---

## 11. 所有权与并发

引用语义；端口由调用方持有；`close` 后不得再读写；`Bytes` 归调用方，方法不保留引用。
非线程安全：`read`/`write`/`flush`/`close` 不得并发；调用方需串行化，或确保关闭时没有其它调用。`close` 幂等指重复调用安全，不承诺并发 close 安全。
无 `equals`/`copy`；不推荐作 `Map` 键；关闭后不得再用句柄。

---

## 12. 示例与反例

正确：

```xnull
SerialOptions options = new SerialOptions(
    115200, 8, SerialParity.None, SerialStopBits.One, 1000, 1000)
Result<SerialPort, Error> opened = SerialPort.open(
    context, "/dev/ttyUSB0", options)
if opened.isOk() {
    SerialPort port = opened.value()
    Bytes buffer = Bytes.alloc(64)
    Result<Int, Error> readResult = port.read(context, buffer)
    if readResult.isOk() && readResult.value() > 0 {
        Result<Int, Error> written = port.write(context, buffer)
    }
    Result<Unit, Error> closed = port.close()
}
```

反例：`close` 后继续 `read`；用 `0` 字节超时却期望阻塞；忽略 `write` 的部分写；并发 `read`/`write`；把 `OnePointFive` 当一定支持；用 `SerialPort` 设置 DTR/RTS；把 `path` 当持久唯一标识。

---

## 13. 测试/场景义务

打开成功/空路径/不存在/无权限/平台不支持/取消；`read` 有数据/超时 0/正超时/空 buffer/关闭后；`write` 全写/部分写/超时无进展/空 buffer/关闭后；`flush` 成功/超时/取消；`close` 幂等/关闭失败仍关闭/关闭后 `Unavailable`；`path`/`isOpen`；并发串行化；`OnePointFive`/`Mark` 不支持路径；跨平台错误映射。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class SerialPort {
    final Long _handle
    final String _path
    final SerialOptions _options
    Bool _open

    SerialPort(Long handle, String path, SerialOptions options) {
        if handle == null || handle <= 0 {
            throw "SerialPort: invalid handle"
        }
        if path == null || path.trim() == "" {
            throw "SerialPort: empty path"
        }
        if options == null {
            throw "SerialPort: null options"
        }
        _handle = handle
        _path = path
        _options = options
        _open = true
    }

    static Result<SerialPort, Error> open(Context context, String devicePath,
                                          SerialOptions options) {
        if context == null || devicePath == null || options == null {
            throw "SerialPort.open: null argument"
        }
        if devicePath.trim() == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "empty serial path"))
        }
        Result<Long, Error> opened = serialOpenRaw(
            context, devicePath, options)
        if opened.isErr() { return Err(opened.error()) }
        Long handle = opened.value()
        if handle <= 0 {
            return Err(new BasicError(ErrorKind.Io,
                "invalid native serial handle"))
        }
        return Ok(new SerialPort(handle, devicePath, options))
    }

    String path() { return _path }
    Bool isOpen() { return _open }

    Result<Int, Error> read(Context context, Bytes buffer) {
        if context == null || buffer == null {
            throw "SerialPort.read: null argument"
        }
        if !_open { return Err(unavailableError("serial port")) }
        if buffer.length() == 0 { return Ok(0) }
        return serialReadRaw(
            context, _handle, buffer, _options.readTimeoutMillis())
    }

    Result<Int, Error> write(Context context, Bytes buffer) {
        if context == null || buffer == null {
            throw "SerialPort.write: null argument"
        }
        if !_open { return Err(unavailableError("serial port")) }
        if buffer.length() == 0 { return Ok(0) }
        return serialWriteRaw(
            context, _handle, buffer, _options.writeTimeoutMillis())
    }

    Result<Unit, Error> flush(Context context) {
        if context == null {
            throw "SerialPort.flush: null context"
        }
        if !_open { return Err(unavailableError("serial port")) }
        return serialFlushRaw(
            context, _handle, _options.writeTimeoutMillis())
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return serialCloseRaw(_handle)
    }
}
```
