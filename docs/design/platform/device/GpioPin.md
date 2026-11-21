# `GpioPin`

| 项 | 值 |
| --- | --- |
| 类型 | `class GpioPin` |
| 包 | `xdk.device` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error`、`DeviceBus`、`GpioDirection` |

---

## 1. 定位

已打开的 GPIO 引脚控制句柄：引脚号、方向、读输入、写输出、关闭、是否打开。

不做：pinmux、上拉/下拉、开漏/推挽、驱动强度、PWM、边沿中断、模拟输入、双向模式、裸寄存器/`ioctl`、内核模块。

---

## 2. 设计逻辑

- 为什么是 class：持有不透明句柄与打开状态，生命周期需要显式 `close`；不是 struct，因为句柄不是值；不是 protocol，因为平台差异在适配器内部。
- 由静态 `GpioPin.open(context, pinNumber, direction)` 创建；构造器主要供宿主/测试使用。
- `_handle` 是 `Long` 不透明句柄；不暴露 fd、指针、`/dev/gpiochip*`、寄存器地址。
- `pinNumber` 是适配器定义的逻辑/板级引脚号，不是 SoC 寄存器号；映射由适配器负责，不承诺跨平台一致。
- 方向在打开时固定：`Input` 只读，`Output` 只写；反向操作返回 `InvalidArgument`。
- 打开受 OS 能力/权限门控：不支持 `Unsupported`，无权限 `PermissionDenied`，被占用 `Busy`，I/O 失败 `Io`。
- `close()` 幂等；关闭后 `pinNumber`/`direction`/`bus`/`isOpen`/`close` 可用，`read`/`write` 返回 `Unavailable`。
- 非线程安全；调用方串行化 `read`/`write`/`close`，或确保关闭时没有其它调用。
- 无全局注册表；引脚由调用方持有并关闭。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_handle` | `Long` | final | >0；不透明句柄 |
| `_pinNumber` | `Int` | final | ≥0；适配器逻辑引脚号 |
| `_direction` | `GpioDirection` | final | 非 null；打开时固定 |
| `_open` | `Bool` | 内部 | 是否打开 |

不变量：`_handle > 0`；`_pinNumber ≥ 0`；`_direction` 非 null；构造后 `_open = true`；`close` 后 `_open = false`；`close` 幂等；关闭后不再调用原生读写原语；`_handle` 不复用。

---

## 4. 生命周期

由 `GpioPin.open(context, pinNumber, direction)` 创建；构造器主要供宿主/测试使用。调用方持有；`close()` 释放句柄；无 `deinit` 依赖。
关闭后对象终止，不提供重新打开；需要新方向/新会话时重新 `open`。关闭后只允许 `pinNumber`/`direction`/`bus`/`isOpen`/`close`；`read`/`write` 返回 `Unavailable`。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `GpioPin(Long handle, Int pinNumber, GpioDirection direction)` | handle、pinNumber、direction | handle>0；pinNumber≥0；direction 非 null | 非法 → panic |
| `GpioPin.open(Context context, Int pinNumber, GpioDirection direction)` | context、pinNumber、direction | context 非 null；pinNumber≥0；direction 非 null | null → panic；负 pinNumber → `InvalidArgument`；适配器失败透传 |

`open` 成功后返回打开对象；适配器返回的句柄 ≤0 视为适配器内部错误，返回 `Internal`，不构造对象。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `open` | 打开 GPIO 引脚 | `Context context, Int pinNumber, GpioDirection direction` | `Result<GpioPin, Error>` | null → panic；负 `pinNumber` → `InvalidArgument`；`PermissionDenied`/`Unsupported`/`Busy`/`Io`/`Cancelled`/`Timeout` |
| `pinNumber` | 逻辑引脚号 | 无 | `Int` | 无 |
| `direction` | 引脚方向 | 无 | `GpioDirection` | 无 |
| `bus` | 总线分类 | 无 | `DeviceBus` | 无 |
| `read` | 读输入电平 | `Context context` | `Result<Bool, Error>` | null → panic；关闭 → `Unavailable`；Output → `InvalidArgument`；`Io`/`Cancelled`/`Timeout` |
| `write` | 写输出电平 | `Context context, Bool value` | `Result<Unit, Error>` | null → panic；关闭 → `Unavailable`；Input → `InvalidArgument`；`Io`/`Cancelled`/`Timeout` |
| `close` | 关闭引脚 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `isOpen` | 是否打开 | 无 | `Bool` | 无 |

说明：

- `open` 是静态工厂；`context == null` 或 `direction == null` panic；`pinNumber < 0` 返回 `InvalidArgument`；`pinNumber` 无固定上限，适配器可返回 `Unsupported`/`InvalidArgument`。
- `pinNumber`/`direction`/`bus` 是纯读取；关闭后仍返回打开时的值；`bus` 恒为 `DeviceBus.Gpio`。
- `read`：`context == null` panic；关闭后 `Unavailable`；方向不是 `Input` 返回 `InvalidArgument`；可阻塞，取消 `Cancelled`，超时 `Timeout`。
- `write`：`context == null` panic；关闭后 `Unavailable`；方向不是 `Output` 返回 `InvalidArgument`；`value` 是电平，不是脉冲/占空比；可阻塞，取消/超时同上。
- `close`：第一次调用先置 `_open = false`，再调用原生关闭；后续调用返回 `Ok(unit)`，不再触碰原生句柄；关闭失败返回 `Io`，状态仍视为关闭。
- `isOpen`：不触碰原生句柄；关闭后为 false。
- 不提供 `describe`/`equals`/`copy`；引脚是资源，不是值对象。

---

## 8. 使用的技术

- 不透明 `Long` 句柄；
- 平台能力/权限门控；
- `Context`/`Result`；
- 方向固定；
- 幂等关闭；
- 原生错误映射。

---

## 9. 需要的支撑

- 语言：class、final 字段、Long、Int、Bool、Result；
- 运行时/适配器：
  - `gpioOpenRaw(Context context, Int pinNumber, GpioDirection direction) -> Result<Long, Error>`；
  - `gpioReadRaw(Context context, Long handle) -> Result<Bool, Error>`；
  - `gpioWriteRaw(Context context, Long handle, Bool value) -> Result<Unit, Error>`；
  - `gpioCloseRaw(Long handle) -> Result<Unit, Error>`；
- 适配器负责把 `pinNumber` 映射到平台引脚，并拒绝不支持的编号/方向；
- 原生句柄必须 >0；0/负数视为适配器内部错误（`open` 返回 `Internal`，构造器 panic）；
- 接口：`Context`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`、`DeviceBus`、`GpioDirection`。

---

## 10. 依赖的特性/接口/类

`Context`、`Error`、`BasicError`、`ErrorKind`、`DeviceBus`、`GpioDirection`、`DeviceManager`。

`xdk.os.hardware` 的只读清单不提供 GPIO 控制；本类型不复制任何清单类型。

---

## 11. 所有权与并发

引用语义；引脚由调用方持有并关闭；无全局注册表；无循环引用。
非线程安全：`read`/`write`/`close` 不得并发；调用方需串行化，或确保 close 时没有其它调用。`close` 幂等指重复调用安全，不承诺并发 close 安全。
`pinNumber`/`direction`/`bus`/`isOpen` 是纯读取，但不要依赖与并发 `close` 的时序。
无 `equals`/`copy`；不推荐作 `Map` 键；关闭后不得再用引脚。

---

## 12. 示例与反例

正确：`GpioPin.open(context, 17, GpioDirection.Output)` 后 `write(context, true)` 点亮 LED，最后 `close()`。  
正确：`GpioPin.open(context, 27, GpioDirection.Input)` 后循环 `read(context)` 读按键，取消时 `Cancelled`，退出前 `close()`。  
反例：对 `Input` 调用 `write`；对 `Output` 调用 `read`；close 后继续读写；假设 `pinNumber` 跨平台一致；假设有上拉/边沿中断；把 `read` 当去抖；多任务并发读写同一个引脚；用 `close` 重试恢复 I/O 错误。

---

## 13. 测试/场景义务

打开/关闭；Input 读、Output 写；Input 写/Output 读返回 `InvalidArgument`；负 `pinNumber`；不支持引脚；无权限；占用；取消/超时；
close 幂等；关闭后 `read`/`write` 返回 `Unavailable`；关闭后 `pinNumber`/`direction`/`bus` 可读；
多个引脚独立；方向固定；`bus()` 为 `DeviceBus.Gpio`；桌面/无 GPIO 平台打开返回 `Unsupported` 或 `PermissionDenied`；close 失败只诊断；关闭后不触碰原生句柄。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class GpioPin {
    final Long _handle
    final Int _pinNumber
    final GpioDirection _direction
    Bool _open

    GpioPin(Long handle, Int pinNumber, GpioDirection direction) {
        if handle <= 0 || pinNumber < 0 || direction == null {
            throw "GpioPin: invalid field"
        }
        _handle = handle
        _pinNumber = pinNumber
        _direction = direction
        _open = true
    }

    static Result<GpioPin, Error> open(Context context, Int pinNumber,
                                       GpioDirection direction) {
        if context == null || direction == null {
            throw "GpioPin.open: null argument"
        }
        if pinNumber < 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "negative gpio pin number"))
        }
        Result<Long, Error> opened = gpioOpenRaw(context, pinNumber, direction)
        if opened.isErr() { return Err(opened.error()) }
        if opened.value() <= 0 {
            return Err(new BasicError(ErrorKind.Internal, "invalid gpio handle"))
        }
        return Ok(new GpioPin(opened.value(), pinNumber, direction))
    }

    Int pinNumber() { return _pinNumber }
    GpioDirection direction() { return _direction }
    DeviceBus bus() { return DeviceBus.Gpio }
    Bool isOpen() { return _open }

    Result<Bool, Error> read(Context context) {
        if context == null { throw "GpioPin.read: null context" }
        if !_open { return Err(unavailableError("gpio pin")) }
        if _direction != GpioDirection.Input {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "read on output pin"))
        }
        return gpioReadRaw(context, _handle)
    }

    Result<Unit, Error> write(Context context, Bool value) {
        if context == null { throw "GpioPin.write: null context" }
        if !_open { return Err(unavailableError("gpio pin")) }
        if _direction != GpioDirection.Output {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "write on input pin"))
        }
        return gpioWriteRaw(context, _handle, value)
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return gpioCloseRaw(_handle)
    }
}
```
