# `I2cBus`

| 项 | 值 |
| --- | --- |
| 类型 | `class I2cBus` |
| 包 | `xdk.device` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error`、`Bytes`、`DeviceBus` |

---

## 1. 定位

已打开的 I2C/SMBus 设备控制句柄：总线路径、7 位设备地址、按寄存器读、按寄存器写、关闭、是否打开。

不做：10 位地址、SMBus PEC、块过程调用、总线扫描/仲裁、时钟拉伸控制、原始 `ioctl`、寄存器映射表、内核驱动、设备树。

---

## 2. 设计逻辑

- 为什么是 class：持有不透明句柄与打开状态，生命周期需要显式 `close`；不是 protocol，因为平台差异在适配器内部。
- 由静态 `I2cBus.open(context, path, deviceAddress)` 创建；构造器主要供宿主/测试使用。
- `_handle` 是 `Long` 不透明句柄；不暴露 fd、指针、`/dev/i2c-*` 内核对象。
- `path` 是平台适配器解释的总线路径/标识；Linux 常见为 `/dev/i2c-N`，其它平台由适配器映射；不承诺跨平台一致。
- `deviceAddress` 是 7 位地址，范围 0..127；10 位地址是 X。保留地址由适配器校验，可能返回 `InvalidArgument`/`Unsupported`。
- baseline 是 SMBus 风格寄存器事务：8 位 `registerAddress`，1..32 字节块；`read` 写入调用方 `target` 并返回实际字节数；`write` 发送 1..32 字节。
- `target` 是借用缓冲区，`read` 成功时原地写入；`data` 是只读借用，适配器不得保留。错误时 `target` 内容未定义，调用方不得部分使用。
- `close()` 幂等；关闭后 `path`/`deviceAddress`/`bus`/`isOpen`/`close` 可用，`read`/`write` 返回 `Unavailable`。
- 非线程安全；同一总线对象的 `read`/`write`/`close` 必须串行化。
- 无全局注册表；总线由调用方持有并关闭。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_handle` | `Long` | final | >0；不透明句柄 |
| `_busPath` | `String` | final | 非空；平台总线路径/标识 |
| `_deviceAddress` | `Int` | final | 0..127；7 位地址 |
| `_open` | `Bool` | 内部 | 是否打开 |

不变量：`_handle > 0`；`_busPath` 非空；`_deviceAddress` 在 0..127；构造后 `_open = true`；`close` 后 `_open = false`；`close` 幂等；关闭后不再调用原生读写原语；`target`/`data` 不被对象保留。

---

## 4. 生命周期

由 `I2cBus.open(context, path, deviceAddress)` 创建；构造器主要供宿主/测试使用。调用方持有；`close()` 释放句柄；无 `deinit` 依赖。
关闭后对象终止，不提供重新打开；需要新会话时重新 `open`。关闭后只允许 `path`/`deviceAddress`/`bus`/`isOpen`/`close`；`read`/`write` 返回 `Unavailable`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `I2cBus(Long handle, String busPath, Int deviceAddress)` | handle、busPath、deviceAddress | handle>0；busPath 非空；address 0..127 | 非法 → panic |
| `I2cBus.open(Context context, String path, Int deviceAddress)` | context、path、deviceAddress | context 非 null；path 非空；address 0..127 | null → panic；空 path/地址越界 → `InvalidArgument`；适配器失败透传 |

`open` 成功后返回打开对象；适配器返回的句柄 ≤0 视为适配器内部错误，返回 `Internal`，不构造对象。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `open` | 打开 I2C 设备 | `Context context, String path, Int deviceAddress` | `Result<I2cBus, Error>` | null → panic；空 path/地址越界 → `InvalidArgument`；`PermissionDenied`/`Unsupported`/`Busy`/`Io`/`Cancelled`/`Timeout` |
| `path` | 总线路径/标识 | 无 | `String` | 无 |
| `deviceAddress` | 7 位设备地址 | 无 | `Int` | 无 |
| `bus` | 总线分类 | 无 | `DeviceBus` | 无 |
| `read` | 从寄存器读块 | `Context context, Int registerAddress, Bytes target` | `Result<Int, Error>` | null → panic；关闭 → `Unavailable`；寄存器/长度越界 → `InvalidArgument`；`Io`/`Cancelled`/`Timeout`/`DataCorrupted` |
| `write` | 向寄存器写块 | `Context context, Int registerAddress, Bytes data` | `Result<Unit, Error>` | null → panic；关闭 → `Unavailable`；寄存器/长度越界 → `InvalidArgument`；`Io`/`Cancelled`/`Timeout` |
| `close` | 关闭设备 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isOpen` | 是否打开 | 无 | `Bool` | 无 |

说明：

- `open` 是静态工厂；`context == null` 或 `path == null` panic；空 `path`、`deviceAddress` 不在 0..127 返回 `InvalidArgument`；适配器可对保留地址或 10 位地址返回 `Unsupported`/`InvalidArgument`。
- `path`/`deviceAddress`/`bus` 是纯读取；关闭后仍返回打开时的值；`bus` 恒为 `DeviceBus.I2c`。
- `read`：`context == null` 或 `target == null` panic；关闭后 `Unavailable`；`registerAddress` 不在 0..255 返回 `InvalidArgument`；`target.length() > 32` 返回 `InvalidArgument`；`target.length() == 0` 返回 `Ok(0)` 且不触碰硬件；成功返回实际读取字节数，范围 0..`target.length()`；原生返回越界计数视为 `DataCorrupted`。
- `read` 成功但短读时，`target` 中超过返回计数的字节内容未定义；调用方必须使用返回计数。错误时 `target` 内容未定义。
- `write`：`context == null` 或 `data == null` panic；关闭后 `Unavailable`；`registerAddress` 不在 0..255 返回 `InvalidArgument`；`data.length()` 不在 1..32 返回 `InvalidArgument`；`data` 只读借用，适配器不得保留。
- `close`：第一次调用先置 `_open = false`，再调用原生关闭；后续调用返回 `Ok(unit)`，不再触碰原生句柄；关闭失败返回 `Io`，状态仍视为关闭。
- `isOpen`：不触碰原生句柄；关闭后为 false。
- 不提供 `describe`/`equals`/`copy`；总线是资源，不是值对象。

---

## 8. 使用的技术

- 不透明 `Long` 句柄；
- SMBus 风格寄存器事务；
- 借用缓冲区原地写入；
- `Context`/`Result`；
- 幂等关闭；
- 原生错误映射。

---

## 9. 需要的支撑

- 语言：class、final 字段、Long、Int、String、Bool、Bytes、Result；
- 运行时/适配器：
  - `i2cOpenRaw(Context context, String path, Int deviceAddress) -> Result<Long, Error>`；
  - `i2cReadRaw(Context context, Long handle, Int registerAddress, Bytes target) -> Result<Int, Error>`；
  - `i2cWriteRaw(Context context, Long handle, Int registerAddress, Bytes data) -> Result<Unit, Error>`；
  - `i2cCloseRaw(Long handle) -> Result<Unit, Error>`；
- 适配器负责 7 位地址校验、保留地址策略、SMBus 块长度限制与平台错误映射；
- 原生句柄必须 >0；0/负数视为适配器内部错误（`open` 返回 `Internal`，构造器 panic）；
- 接口：`Context`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`、`Bytes`、`DeviceBus`。

---

## 10. 依赖的特性/接口/类

`Context`、`Error`、`BasicError`、`ErrorKind`、`Bytes`、`DeviceBus`、`DeviceManager`。

`xdk.os.hardware` 的只读清单不提供 I2C 控制；本类型不复制任何清单类型。

---

## 11. 所有权与并发

引用语义；总线由调用方持有并关闭；无全局注册表；无循环引用。
`read` 的 `target` 是借用并原地修改；`write` 的 `data` 是只读借用；两者都不被对象保留，调用返回后适配器不得再访问。
非线程安全：同一对象的 `read`/`write`/`close` 不得并发；调用方需串行化，或确保 close 时没有其它调用；不得让两个并发读共享同一个 `target`。`close` 幂等指重复调用安全，不承诺并发 close 安全。
`path`/`deviceAddress`/`bus`/`isOpen` 是纯读取，但不要依赖与并发 `close` 的时序。
无 `equals`/`copy`；不推荐作 `Map` 键；关闭后不得再用总线。

---

## 12. 示例与反例

正确：`I2cBus.open(context, "/dev/i2c-1", 72)`；`Bytes target = Bytes.alloc(2)`；`Result<Int, Error> count = bus.read(context, 0, target)`；用 `count.value()` 决定有效字节；`bus.write(context, 1, config)`；最后 `bus.close()`。  
反例：把 `deviceAddress` 当 8 位地址传 128；`target` 长度 64；假设 `read` 一定填满；错误后继续使用 `target` 的部分内容；并发读共享同一个 `target`；close 后继续读写；把 `path` 当跨平台稳定 ID；用原始 `ioctl` 绕过本类型；假设支持 10 位地址/PEC。

---

## 13. 测试/场景义务

打开/关闭；地址 0/127/128；空 path；寄存器 0/255/256；`target` 长度 0/1/32/33；短读计数；原生计数越界；`write` 长度 0/1/32/33；无权限；不支持；占用；取消/超时；
close 幂等；关闭后 `read`/`write` 返回 `Unavailable`；关闭后 `path`/`deviceAddress`/`bus` 可读；
`target` 原地写入与错误内容未定义；`data` 不被保留；多个总线独立；`bus()` 为 `DeviceBus.I2c`；桌面/无 I2C 平台打开返回 `Unsupported` 或 `PermissionDenied`；close 失败只诊断。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class I2cBus {
    final Long _handle
    final String _busPath
    final Int _deviceAddress
    Bool _open

    I2cBus(Long handle, String busPath, Int deviceAddress) {
        if handle <= 0 || busPath == null || busPath == "" {
            throw "I2cBus: invalid field"
        }
        if deviceAddress < 0 || deviceAddress > 127 {
            throw "I2cBus: invalid address"
        }
        _handle = handle
        _busPath = busPath
        _deviceAddress = deviceAddress
        _open = true
    }

    static Result<I2cBus, Error> open(Context context, String path,
                                      Int deviceAddress) {
        if context == null || path == null {
            throw "I2cBus.open: null argument"
        }
        if path == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "empty i2c path"))
        }
        if deviceAddress < 0 || deviceAddress > 127 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "i2c address out of range"))
        }
        Result<Long, Error> opened = i2cOpenRaw(context, path, deviceAddress)
        if opened.isErr() { return Err(opened.error()) }
        if opened.value() <= 0 {
            return Err(new BasicError(ErrorKind.Internal, "invalid i2c handle"))
        }
        return Ok(new I2cBus(opened.value(), path, deviceAddress))
    }

    String path() { return _busPath }
    Int deviceAddress() { return _deviceAddress }
    DeviceBus bus() { return DeviceBus.I2c }
    Bool isOpen() { return _open }

    Result<Int, Error> read(Context context, Int registerAddress, Bytes target) {
        if context == null || target == null {
            throw "I2cBus.read: null argument"
        }
        if !_open { return Err(unavailableError("i2c bus")) }
        if registerAddress < 0 || registerAddress > 255 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "i2c register out of range"))
        }
        if target.length() > 32 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "i2c read exceeds 32 bytes"))
        }
        if target.length() == 0 { return Ok(0) }
        Result<Int, Error> readCount = i2cReadRaw(context, _handle,
            registerAddress, target)
        if readCount.isErr() { return Err(readCount.error()) }
        if readCount.value() < 0 || readCount.value() > target.length() {
            return Err(new BasicError(ErrorKind.DataCorrupted,
                "i2c read count out of range"))
        }
        return Ok(readCount.value())
    }

    Result<Unit, Error> write(Context context, Int registerAddress, Bytes data) {
        if context == null || data == null {
            throw "I2cBus.write: null argument"
        }
        if !_open { return Err(unavailableError("i2c bus")) }
        if registerAddress < 0 || registerAddress > 255 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "i2c register out of range"))
        }
        if data.length() == 0 || data.length() > 32 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "i2c write size must be 1..32"))
        }
        return i2cWriteRaw(context, _handle, registerAddress, data)
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return i2cCloseRaw(_handle)
    }
}
```
