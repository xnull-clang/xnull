# `SpiBus`

| 项 | 值 |
| --- | --- |
| 类型 | `class SpiBus` |
| 包 | `xdk.device` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error`、`Bytes`、`DeviceBus` |

---

## 1. 定位

已打开的 SPI 设备控制句柄：总线路径、模式、字长、请求时钟、单次全双工传输、关闭、是否打开。

不做：片选控制、多段传输、批量队列、DMA、从模式、SPI 寄存器映射、原始 `ioctl`、内核驱动、设备树。

---

## 2. 设计逻辑

- 为什么是 class：持有不透明句柄与打开状态，生命周期需要显式 `close`；不是 protocol，因为平台差异在适配器内部。
- 由静态 `SpiBus.open(context, path, mode, bitsPerWord, speedHz)` 创建；构造器主要供宿主/测试使用。
- `_handle` 是 `Long` 不透明句柄；不暴露 fd、指针、内核对象。
- `path` 是平台适配器解释的总线/设备路径；片选通常由路径或平台适配器绑定，baseline 不单独提供 CS API。
- `mode` 是 SPI 模式 0..3（CPOL/CPHA）；`bitsPerWord` 是 1..32；`speedHz` 是请求时钟频率，单位 Hz。
- baseline 是单次全双工 `transfer`：输入 `data` 与输出 `Bytes` 等长；空输入返回空输出且不触碰硬件。
- 实际时钟可能低于请求值；baseline 不提供实际频率回读，也不保证精确匹配。
- `close()` 幂等；关闭后 `path`/`mode`/`bitsPerWord`/`speedHz`/`bus`/`isOpen`/`close` 可用，`transfer` 返回 `Unavailable`。
- 非线程安全；同一总线对象的 `transfer`/`close` 必须串行化。
- 无全局注册表；总线由调用方持有并关闭。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_handle` | `Long` | final | >0；不透明句柄 |
| `_busPath` | `String` | final | 非空；平台总线/设备路径 |
| `_mode` | `Int` | final | 0..3 |
| `_bitsPerWord` | `Int` | final | 1..32 |
| `_speedHz` | `Int` | final | >0；请求频率 |
| `_open` | `Bool` | 内部 | 是否打开 |

不变量：`_handle > 0`；`_busPath` 非空；`_mode` 在 0..3；`_bitsPerWord` 在 1..32；`_speedHz > 0`；构造后 `_open = true`；`close` 后 `_open = false`；`close` 幂等；关闭后不再调用原生传输原语；输入 `data` 不被保留。

---

## 4. 生命周期

由 `SpiBus.open(context, path, mode, bitsPerWord, speedHz)` 创建；构造器主要供宿主/测试使用。调用方持有；`close()` 释放句柄；无 `deinit` 依赖。
关闭后对象终止，不提供重新打开；需要新配置/新会话时重新 `open`。关闭后只允许 `path`/`mode`/`bitsPerWord`/`speedHz`/`bus`/`isOpen`/`close`；`transfer` 返回 `Unavailable`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `SpiBus(Long handle, String busPath, Int mode, Int bitsPerWord, Int speedHz)` | handle、busPath、mode、bitsPerWord、speedHz | handle>0；busPath 非空；mode 0..3；bitsPerWord 1..32；speedHz>0 | 非法 → panic |
| `SpiBus.open(Context context, String path, Int mode, Int bitsPerWord, Int speedHz)` | context、path、mode、bitsPerWord、speedHz | context 非 null；path 非空；mode 0..3；bitsPerWord 1..32；speedHz>0 | null → panic；空 path/范围越界 → `InvalidArgument`；适配器失败透传 |

`open` 成功后返回打开对象；适配器返回的句柄 ≤0 视为适配器内部错误，返回 `Internal`，不构造对象。适配器可对不支持的 mode/字长/频率返回 `Unsupported`。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `open` | 打开 SPI 设备 | `Context context, String path, Int mode, Int bitsPerWord, Int speedHz` | `Result<SpiBus, Error>` | null → panic；空 path/范围越界 → `InvalidArgument`；`PermissionDenied`/`Unsupported`/`Busy`/`Io`/`Cancelled`/`Timeout` |
| `path` | 总线/设备路径 | 无 | `String` | 无 |
| `mode` | SPI 模式 | 无 | `Int` | 无 |
| `bitsPerWord` | 字长 | 无 | `Int` | 无 |
| `speedHz` | 请求时钟 Hz | 无 | `Int` | 无 |
| `bus` | 总线分类 | 无 | `DeviceBus` | 无 |
| `transfer` | 单次全双工传输 | `Context context, Bytes data` | `Result<Bytes, Error>` | null → panic；关闭 → `Unavailable`；`Io`/`Cancelled`/`Timeout`/`DataCorrupted` |
| `close` | 关闭设备 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isOpen` | 是否打开 | 无 | `Bool` | 无 |

说明：

- `open` 是静态工厂；`context == null` 或 `path == null` panic；空 `path`、`mode` 不在 0..3、`bitsPerWord` 不在 1..32、`speedHz ≤ 0` 返回 `InvalidArgument`；适配器可返回 `Unsupported`。
- `path`/`mode`/`bitsPerWord`/`speedHz`/`bus` 是纯读取；关闭后仍返回打开时的值；`bus` 恒为 `DeviceBus.Spi`。
- `transfer`：`context == null` 或 `data == null` panic；关闭后 `Unavailable`；`data.length() == 0` 返回 `Ok(Bytes.empty())` 且不触碰硬件；成功返回新的 `Bytes`，长度必须等于 `data.length()`，否则 `DataCorrupted`。
- `transfer` 是借用 `data`、返回新所有权；输入与输出都不是视图；调用返回后适配器不得保留 `data`。
- `transfer` 可阻塞，取消 `Cancelled`，超时 `Timeout`；单次长度上限由适配器决定，超限可由适配器返回 `Unsupported`/`Io`。
- `close`：第一次调用先置 `_open = false`，再调用原生关闭；后续调用返回 `Ok(unit)`，不再触碰原生句柄；关闭失败返回 `Io`，状态仍视为关闭。
- `isOpen`：不触碰原生句柄；关闭后为 false。
- 不提供 `describe`/`equals`/`copy`；总线是资源，不是值对象。

---

## 8. 使用的技术

- 不透明 `Long` 句柄；
- 全双工传输；
- 请求参数快照；
- `Context`/`Result`；
- 幂等关闭；
- 输出长度校验。

---

## 9. 需要的支撑

- 语言：class、final 字段、Long、Int、String、Bool、Bytes、Result；
- 运行时/适配器：
  - `spiOpenRaw(Context context, String path, Int mode, Int bitsPerWord, Int speedHz) -> Result<Long, Error>`；
  - `spiTransferRaw(Context context, Long handle, Bytes data) -> Result<Bytes, Error>`；
  - `spiCloseRaw(Long handle) -> Result<Unit, Error>`；
- 适配器负责模式/字长/频率能力校验、片选绑定、平台错误映射；
- 原生句柄必须 >0；0/负数视为适配器内部错误（`open` 返回 `Internal`，构造器 panic）；
- 接口：`Context`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`、`Bytes`、`DeviceBus`。

---

## 10. 依赖的特性/接口/类

`Context`、`Error`、`BasicError`、`ErrorKind`、`Bytes`、`DeviceBus`、`DeviceManager`。

`xdk.os.hardware` 的只读清单不提供 SPI 控制；本类型不复制任何清单类型。

---

## 11. 所有权与并发

引用语义；总线由调用方持有并关闭；无全局注册表；无循环引用。
`transfer` 的 `data` 是只读借用；返回的 `Bytes` 是新所有权；输入/输出都不被对象保留，调用返回后适配器不得再访问 `data`。
非线程安全：同一对象的 `transfer`/`close` 不得并发；调用方需串行化，或确保 close 时没有其它调用。`close` 幂等指重复调用安全，不承诺并发 close 安全。
`path`/`mode`/`bitsPerWord`/`speedHz`/`bus`/`isOpen` 是纯读取，但不要依赖与并发 `close` 的时序。
无 `equals`/`copy`；不推荐作 `Map` 键；关闭后不得再用总线。

---

## 12. 示例与反例

正确：`SpiBus.open(context, "/dev/spidev0.0", 0, 8, 1000000)`；`Result<Bytes, Error> response = bus.transfer(context, command)`；校验 `response.value().length() == command.length()`；最后 `bus.close()`。  
反例：`mode = 4`；`bitsPerWord = 0`；`speedHz = 0`；假设实际时钟等于请求值；假设有独立 CS 控制；空传输仍触碰硬件；并发 `transfer`；close 后继续传输；把 `path` 当跨平台稳定 ID；把返回值当输入缓冲区的视图。

---

## 13. 测试/场景义务

打开/关闭；mode 0..3/4；bitsPerWord 0/1/8/32/33；speedHz 0/1/大值；空 path；无权限；不支持的模式/频率；占用；取消/超时；
`transfer` 空输入返回空输出且不触碰硬件；正常等长输出；原生返回 null/长度不匹配 → `DataCorrupted`；
close 幂等；关闭后 `transfer` 返回 `Unavailable`；关闭后 `path`/`mode`/`bitsPerWord`/`speedHz`/`bus` 可读；
输入不被保留；多个总线独立；`bus()` 为 `DeviceBus.Spi`；桌面/无 SPI 平台打开返回 `Unsupported` 或 `PermissionDenied`；close 失败只诊断。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class SpiBus {
    final Long _handle
    final String _busPath
    final Int _mode
    final Int _bitsPerWord
    final Int _speedHz
    Bool _open

    SpiBus(Long handle, String busPath, Int mode, Int bitsPerWord, Int speedHz) {
        if handle <= 0 || busPath == null || busPath == "" {
            throw "SpiBus: invalid field"
        }
        if mode < 0 || mode > 3 {
            throw "SpiBus: invalid mode"
        }
        if bitsPerWord < 1 || bitsPerWord > 32 {
            throw "SpiBus: invalid bits per word"
        }
        if speedHz <= 0 {
            throw "SpiBus: invalid speed"
        }
        _handle = handle
        _busPath = busPath
        _mode = mode
        _bitsPerWord = bitsPerWord
        _speedHz = speedHz
        _open = true
    }

    static Result<SpiBus, Error> open(Context context, String path, Int mode,
                                      Int bitsPerWord, Int speedHz) {
        if context == null || path == null {
            throw "SpiBus.open: null argument"
        }
        if path == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "empty spi path"))
        }
        if mode < 0 || mode > 3 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "spi mode out of range"))
        }
        if bitsPerWord < 1 || bitsPerWord > 32 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "spi bits per word out of range"))
        }
        if speedHz <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "spi speed must be positive"))
        }
        Result<Long, Error> opened = spiOpenRaw(context, path, mode,
            bitsPerWord, speedHz)
        if opened.isErr() { return Err(opened.error()) }
        if opened.value() <= 0 {
            return Err(new BasicError(ErrorKind.Internal, "invalid spi handle"))
        }
        return Ok(new SpiBus(opened.value(), path, mode, bitsPerWord, speedHz))
    }

    String path() { return _busPath }
    Int mode() { return _mode }
    Int bitsPerWord() { return _bitsPerWord }
    Int speedHz() { return _speedHz }
    DeviceBus bus() { return DeviceBus.Spi }
    Bool isOpen() { return _open }

    Result<Bytes, Error> transfer(Context context, Bytes data) {
        if context == null || data == null {
            throw "SpiBus.transfer: null argument"
        }
        if !_open { return Err(unavailableError("spi bus")) }
        if data.length() == 0 { return Ok(Bytes.empty()) }
        Result<Bytes, Error> transferred = spiTransferRaw(context, _handle, data)
        if transferred.isErr() { return Err(transferred.error()) }
        Bytes result = transferred.value()
        if result == null || result.length() != data.length() {
            return Err(new BasicError(ErrorKind.DataCorrupted,
                "spi transfer length mismatch"))
        }
        return Ok(result)
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return spiCloseRaw(_handle)
    }
}
```
