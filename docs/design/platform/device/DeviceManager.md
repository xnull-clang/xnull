# `DeviceManager`

| 项 | 值 |
| --- | --- |
| 类型 | `class DeviceManager`（静态入口/聚合） |
| 包 | `xdk.device` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`Error`、`GpioPin`、`I2cBus`、`SpiBus`、`CameraDevice`、`GpioDirection` |

---

## 1. 定位

`xdk.device` 的静态入口/聚合：打开 GPIO/I2C/SPI，枚举相机，按路径打开相机。

不做：硬件清单、设备缓存、全局注册表、引用计数、`closeAll`、热插拔监听、权限提升、驱动绑定。`xdk.os.hardware` 仍只读清单；USB 控制不在此。

---

## 2. 设计逻辑

- 为什么是 class：提供稳定的包级命名空间与聚合方法；不是 protocol，因为没有多实现；不是单例，因为无实例状态。
- 静态无状态：所有方法都是便捷入口，不缓存设备、不持有句柄、不跨调用保存 `Context`。
- `openGpio`/`openI2c`/`openSpi` 直接委托对应类型的静态 `open`，参数与失败语义保持一致；不复制校验逻辑。
- `cameras` 返回 `CameraDevice.list` 的未打开描述符副本；`cameraPaths` 只返回路径字符串，适合先展示/选择再打开。
- `openCamera` 按精确 `path` 在新鲜枚举中查找，找到后调用 `open`；找不到返回 `NotFound`；不缓存描述符，避免路径失效后仍复用旧对象。
- 不提供 `closeAll`：管理器不拥有设备；每个 `GpioPin`/`I2cBus`/`SpiBus`/`CameraDevice` 由调用方关闭。
- 不提供 `gpioPins`/`i2cBuses`/`spiBuses` 清单：这些是平台清单/探测问题，不在本包重复；GPIO/I2C/SPI 的可用性由打开结果表达。
- 不提供总线清单方法：分类由各设备的 `bus()` 暴露；管理器不维护总线清单。
- 静态方法无共享状态，可并发调用；返回的对象各自独立，仍需按各自并发规则使用。

---

## 3. 表示与不变量

无实例字段。

不变量：不可实例化；所有方法静态；不缓存句柄；不保存 `Context`；返回的列表是新副本；返回的设备由调用方拥有；调用之间无隐藏状态。

---

## 4. 生命周期

静态类；无实例；无 `close`；无全局资源；无 `deinit` 依赖。管理器不延长任何设备生命周期；设备关闭后管理器不感知，也不应被要求感知。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `DeviceManager()` | 无 | 私有；禁止实例化 | 无 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `openGpio` | 打开 GPIO | `Context context, Int pinNumber, GpioDirection direction` | `Result<GpioPin, Error>` | 同 `GpioPin.open` |
| `openI2c` | 打开 I2C | `Context context, String path, Int deviceAddress` | `Result<I2cBus, Error>` | 同 `I2cBus.open` |
| `openSpi` | 打开 SPI | `Context context, String path, Int mode, Int bitsPerWord, Int speedHz` | `Result<SpiBus, Error>` | 同 `SpiBus.open` |
| `cameras` | 枚举相机描述符 | `Context context` | `Result<List<CameraDevice>, Error>` | null → panic；`PermissionDenied`/`Unsupported`/`Io`/`Cancelled`/`Timeout`/`DataCorrupted` |
| `cameraPaths` | 枚举相机路径 | `Context context` | `Result<List<String>, Error>` | 同 `cameras`；映射不新增失败 |
| `openCamera` | 按路径打开相机 | `Context context, String path` | `Result<CameraDevice, Error>` | null → panic；空 path → `InvalidArgument`；未找到 → `NotFound`；打开失败同 `CameraDevice.open` |

说明：

- `openGpio`/`openI2c`/`openSpi` 是纯委托；null、范围、权限、能力、I/O 错误语义完全由被委托类型定义。
- `cameras`：`context == null` panic；返回未打开描述符的新列表；顺序不承诺；每次重新枚举。
- `cameraPaths`：`context == null` panic；调用 `CameraDevice.list` 后提取 `path()`；返回新的 `List<String>`；不返回描述符，不打开设备；顺序与 `cameras` 一致（即不承诺）。
- `openCamera`：`context == null` 或 `path == null` panic；空 `path` 返回 `InvalidArgument`；在新鲜 `CameraDevice.list` 中按精确 `path` 查找；找到后 `open(context)` 并返回该描述符；未找到返回 `NotFound`；不缓存、不做模糊匹配、不做路径规范化。
- 如果枚举中出现重复 `path`，返回第一个匹配；适配器应保证同一枚举内 `path` 唯一。
- `DeviceManager` 不提供 `close`/`closeAll`；调用方关闭返回的设备。
- 全部方法无隐藏全局状态；`cameraPaths` 的映射是 O(n)，其余为委托。

---

## 8. 使用的技术

- 静态入口；
- 委托；
- 列表映射；
- 新鲜枚举；
- 无状态聚合；
- `Context`/`Result`。

---

## 9. 需要的支撑

- 语言：class、static、私有构造器、List、String、Result；
- 运行时/适配器：无直接原生原语；全部通过 `GpioPin`/`I2cBus`/`SpiBus`/`CameraDevice` 的适配器；
- 接口：`Context`、`Error`、`BasicError`、`ErrorKind`、`GpioPin`、`I2cBus`、`SpiBus`、`CameraDevice`、`GpioDirection`。

---

## 10. 依赖的特性/接口/类

`Context`、`Error`、`BasicError`、`ErrorKind`、`GpioPin`、`GpioDirection`、`I2cBus`、`SpiBus`、`CameraDevice`、`CameraFrame`、`DeviceBus`。

`xdk.os.hardware` 的只读清单不被复制；USB 控制不在此。

---

## 11. 所有权与并发

静态无状态；无实例；无全局注册表；不拥有设备；不缓存句柄或 `Context`。
静态方法无共享状态，可并发调用；底层适配器可能串行化枚举/打开，若适配器有全局设备表，调用方需串行化。每次调用创建独立对象/列表；并发 `openCamera` 可能打开同一 `path` 的多个句柄，由调用方去重/关闭；管理器不做单例仲裁。
返回的 `GpioPin`/`I2cBus`/`SpiBus`/`CameraDevice` 归调用方所有，按各自并发规则使用。
无 `equals`/`copy`；无实例；不适用作 `Map` 键。

---

## 12. 示例与反例

正确：`Result<GpioPin, Error> pin = DeviceManager.openGpio(context, 17, GpioDirection.Output)`；用完 `pin.value().close()`。  
正确：`List<String> paths = DeviceManager.cameraPaths(context).value()`；用户选择后 `CameraDevice camera = DeviceManager.openCamera(context, paths.get(0)).value()`；用完 `camera.close()`。  
正确：`cameras(context)` 先展示描述符，再对选中项 `open`。  
反例：期望 `DeviceManager` 自动关闭设备；把它当硬件清单/总线枚举；用它打开 USB；假设 `cameraPaths` 顺序稳定；缓存 `CameraDevice` 并假设路径永远有效；并发打开同一相机却不关闭；用 `closeAll` 的思维管理生命周期；把管理器当全局单例保存状态。

---

## 13. 测试/场景义务

三个 `open*` 委托的参数/失败语义；null context/direction/path；负 `pinNumber`；I2C 地址边界；SPI mode/字长/频率边界；
`cameras` 空/单/多；列表副本独立；未打开描述符；顺序不承诺；`cameraPaths` 与 `cameras` 一致；`openCamera` 找到/未找到/空 path/重复 path；
权限/不支持/占用/取消/超时；并发调用各自独立；无全局状态；返回设备由调用方关闭；`DeviceManager` 无 `close`。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class DeviceManager {
    private DeviceManager() {}

    static Result<GpioPin, Error> openGpio(Context context, Int pinNumber,
                                          GpioDirection direction) {
        return GpioPin.open(context, pinNumber, direction)
    }

    static Result<I2cBus, Error> openI2c(Context context, String path,
                                         Int deviceAddress) {
        return I2cBus.open(context, path, deviceAddress)
    }

    static Result<SpiBus, Error> openSpi(Context context, String path, Int mode,
                                         Int bitsPerWord, Int speedHz) {
        return SpiBus.open(context, path, mode, bitsPerWord, speedHz)
    }

    static Result<List<CameraDevice>, Error> cameras(Context context) {
        return CameraDevice.list(context)
    }

    static Result<List<String>, Error> cameraPaths(Context context) {
        if context == null { throw "DeviceManager.cameraPaths: null context" }
        Result<List<CameraDevice>, Error> listed = CameraDevice.list(context)
        if listed.isErr() { return Err(listed.error()) }
        List<CameraDevice> devices = listed.value()
        List<String> paths = []
        Int index = 0
        while index < devices.length() {
            paths.push(devices.get(index).path())
            index = index + 1
        }
        return Ok(paths)
    }

    static Result<CameraDevice, Error> openCamera(Context context, String path) {
        if context == null || path == null {
            throw "DeviceManager.openCamera: null argument"
        }
        if path == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "empty camera path"))
        }
        Result<List<CameraDevice>, Error> listed = CameraDevice.list(context)
        if listed.isErr() { return Err(listed.error()) }
        List<CameraDevice> devices = listed.value()
        Int index = 0
        while index < devices.length() {
            CameraDevice device = devices.get(index)
            if device.path() == path {
                Result<Unit, Error> opened = device.open(context)
                if opened.isErr() { return Err(opened.error()) }
                return Ok(device)
            }
            index = index + 1
        }
        return Err(new BasicError(ErrorKind.NotFound, "camera path not found"))
    }
}
```
