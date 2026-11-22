# `xdk.device` 设备控制面

| 项 | 值 |
| --- | --- |
| 包 | `xdk.device` |
| 层 |  |
| 依赖 | `xdk.core`、`xdk.os.hardware` |
| 能力 | GPIO、I2C、SPI、相机控制面 |
| 稳定性 | `preview` |

---

## 1. 定位

`xdk.device` 是设备**控制面**：打开、读写、采集、关闭 GPIO / I2C / SPI / 相机。

`xdk.os.hardware` 只提供**只读清单**（主板、BIOS、PCI、USB、传感器）；本包不重复这些清单类型，也不把 USB 控制塞进设备总线。USB 仍在 `xdk.os.hardware` / ecosystem。

不做：驱动绑定、内核模块、厂商 SDK、裸设备 `ioctl`、寄存器映射表、设备树/overlay、固件升级、热插拔事件、权限提升。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 控制面 | 只做打开/读写/采集/关闭；清单与探测属于 `xdk.os.hardware` |
| 不重复 | 不复制 `PciDevice`/`UsbDevice`/`SensorReading`；USB 不进入 `DeviceBus` |
| 不透明句柄 | 设备用 `Long` 句柄；不暴露 fd、指针、内核对象、后端句柄 |
| 可失败 | 不支持 `Unsupported`；无权限 `PermissionDenied`；占用 `Busy`；I/O `Io`；不 panic 运行时失败 |
| 可取消 | 可阻塞方法首参 `Context`；取消 `Cancelled`；超时 `Timeout` |
| 显式生命周期 | 调用方持有并 `close()`；`close()` 幂等；无 finalizer 依赖 |
| 无全局注册表 | `DeviceManager` 只做入口/聚合，不拥有设备；设备由调用方关闭 |
| 路径平台化 | I2C/SPI/相机 `path` 由平台适配器解释；不承诺跨平台一致 |
| 安全默认 | 打开受 OS 权限/能力门控；相机采集必须显式 `open`；不后台采集、不落盘 |
| 字节所有权 | 输入字节借用；输出字节/帧归调用方；不保留调用方缓冲区 |

---

## 3. 类型索引

| 类型 | 种类 | 文件 |
| --- | --- | --- |
| `DeviceBus` | enum | [`DeviceBus.md`](DeviceBus.md) |
| `GpioDirection` | enum | [`GpioDirection.md`](GpioDirection.md) |
| `GpioPin` | class | [`GpioPin.md`](GpioPin.md) |
| `I2cBus` | class | [`I2cBus.md`](I2cBus.md) |
| `SpiBus` | class | [`SpiBus.md`](SpiBus.md) |
| `CameraPixelFormat` | enum | [`CameraPixelFormat.md`](CameraPixelFormat.md) |
| `CameraFrame` | class | [`CameraFrame.md`](CameraFrame.md) |
| `CameraDevice` | class | [`CameraDevice.md`](CameraDevice.md) |
| `DeviceManager` | class（静态入口/聚合） | [`DeviceManager.md`](DeviceManager.md) |

类型索引 9 项 = 9 个类型文件；README 不含类型方法表或伪代码。

---

## 4. 跨类型规则

- 先打开再操作。未打开 / 已关闭的设备，除 `isOpen`、`close` 与纯读取器（`pinNumber`/`direction`/`path`/`deviceAddress`/`mode`/`bitsPerWord`/`speedHz`/`name`/`bus`）外，返回 `Unavailable`。
- `close()` 幂等：第一次释放原生句柄，后续返回 `Ok(unit)`；关闭失败返回 `Io` 仅作诊断，状态仍视为关闭，避免重复释放。
- 方向固定：`GpioPin` 在 `open` 时确定 `Input`/`Output`；`Input.read`、`Output.write`；反向操作返回 `InvalidArgument`。要换方向，关闭后重新打开。
- I2C baseline 是 SMBus 风格寄存器读写：7 位地址、8 位寄存器、1..32 字节块；10 位地址、PEC、原始 `ioctl` 是 X。
- SPI baseline 是单次全双工 `transfer`：输入与输出等长；片选、批量传输、DMA、从模式是 X。
- 相机列表返回**未打开的描述符**；`open` 原地打开，`capture` 返回新的 `CameraFrame`；不新增 `CameraDeviceInfo`，避免与描述符重复。
- `CameraFrame` 不可变：构造复制输入字节，`data()` 返回副本；已知格式校验帧字节数；`Unknown` 合法但不解释布局。
- 设备控制面只做 I/O；图像编码/录制、GPIO PWM/边沿中断、I2C 原始传输、SPI 多设备仲裁都不在本包 baseline。
- `DeviceBus.Bluetooth` 仅保留分类；当前包没有蓝牙控制 API。`DeviceBus.Other` 表示未知/未分类控制面总线。
- `DeviceManager` 不拥有设备，不提供 `closeAll`；每个打开的对象由调用方关闭。
- 并发：设备对象非线程安全；同一对象的读写/采集/关闭必须由调用方串行化。不同对象可并行，前提是平台适配器支持并发；适配器可串行化平台调用。

---

## 5. 场景

- 嵌入式 Linux：GPIO 读按键/写 LED；I2C 读传感器寄存器；SPI 读 ADC/写显示控制器。
- 桌面/笔记本：相机枚举、打开、抓取一帧原始图像；GPIO/I2C/SPI 通常返回 `Unsupported`。
- 服务器/CI：无设备时列表为空；打开返回 `Unsupported`/`PermissionDenied`；不 panic。
- 隐私敏感应用：相机必须显式 `open`；采集失败不返回空帧；帧不自动落盘。
- 设备诊断：用 `bus()`、`path()`、`deviceAddress()`、`mode()` 写日志；日志不包含帧数据。

---

## 6. 缺口

- GPIO：PWM、边沿中断、上拉/下拉、pinmux、模拟输入、双向模式；X。
- I2C：10 位地址、PEC、SMBus 复杂事务、总线扫描、原始 `ioctl`；X。
- SPI：片选控制、多段传输、DMA、从模式、实际时钟回读；X。
- 相机：曝光/增益/白平衡/变焦控制、格式协商、持续流、热插拔监听、录像/编码；X。
- 蓝牙控制：X；本包只保留 `DeviceBus.Bluetooth` 分类。
- USB 控制：留在 `xdk.os.hardware` 只读清单与 ecosystem/FFI；不进入本包。
- 权限策略、设备树/overlay、沙箱/容器设备映射：由宿主/运行时/部署层提供。
- 串口：独立包 `xdk.serial`，不在本包重复。

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | `@Device`、`@Gpio`、`@I2cAddress` |
| 本包消费 | `@Value`、`@Builder`、`@Packed`、`@Align`、`@NativeLayout` |
| 处理器 | DeviceAnnotationProcessor（Validate/Generate） |
| 生成物 | 设备/引脚/地址目录、布局校验 |
| 状态 | 领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 板级/设备类 | `@Device` | 设备目录 |
| 引脚字段/参数 | `@Gpio` | 引脚目录 |
| I2C 字段/参数 | `@I2cAddress` | 地址目录 |
| `CameraFrame` | `@Value` | 不可变帧快照 |
| `GpioPin`/`I2cBus`/`SpiBus`/`CameraDevice` | — | 资源句柄，保持显式 class/close |

### 声明

```x
@Target(Type)
@Retention(Runtime)
@annotation Device {
    final String kind
}

@Target(Field, Parameter)
@Retention(Runtime)
@annotation Gpio {
    final Int pin
    final GpioDirection direction = GpioDirection.In
}

@Target(Field, Parameter)
@Retention(Runtime)
@annotation I2cAddress {
    final Int address
}
```

声明文件：每个注解单独一个 PascalCase 文件；处理器为构建期类型；生成代码在 `<package>/generated/`。

### 使用

```x
@Device("board")
class Board {
    @Gpio(17, GpioDirection.Out) Int statusLed
    @I2cAddress(0x3C) Int display
}
```

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
