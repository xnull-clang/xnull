# `DeviceBus`

| 项 | 值 |
| --- | --- |
| 类型 | `enum DeviceBus` |
| 包 | `xdk.device` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

设备控制面的总线分类：GPIO、I2C、SPI、相机、蓝牙、其他。

不做：硬件清单、总线号/地址分配、USB 分类、驱动绑定、热插拔事件。USB 的只读清单留在 `xdk.os.hardware` 的 `UsbDevice`，不在此枚举重复。

---

## 2. 设计逻辑

- 为什么是 enum：分类集合固定、值语义、可穷举；调用方用它做权限策略、日志、诊断和 `bus()` 返回值。
- 不是硬件清单：不携带厂商、型号、总线号、地址、路径；这些由具体设备类型或 `xdk.os.hardware` 提供。
- `Gpio`/`I2c`/`Spi`/`Camera` 对应本包 baseline 的四类控制面。
- `Bluetooth` 仅保留分类；当前包没有蓝牙控制 API，避免未来新增类型时换义。
- `Other` 表示未知/未分类控制面总线；未知值不 panic。
- 成员固定，只允许追加；名称映射稳定小写，便于日志与配置。
- 不提供 `Usb`：USB 控制不在本包，清单在 `xdk.os.hardware`；重复会制造两个真相源。

---

## 3. 表示与不变量

| 成员 | 含义 | baseline |
| --- | --- | --- |
| `Gpio` | GPIO 引脚控制面 | `GpioPin` |
| `I2c` | I2C/SMBus 控制面 | `I2cBus` |
| `Spi` | SPI 控制面 | `SpiBus` |
| `Camera` | 相机采集控制面 | `CameraDevice` |
| `Bluetooth` | 蓝牙分类保留 | 无控制 API |
| `Other` | 其他/未知控制面 | 无具体类型 |

不变量：成员固定；只允许追加；值语义；枚举项非 null；名称映射对每个成员稳定。

---

## 4. 生命周期

值类型；无构造器、无 `close`；可共享；无资源；无取消点。

---

## 5. 构造契约

枚举项直接使用，无构造器。不允许应用扩展成员；未知总线用 `Other`。

---

## 6. 字段表

无实例字段；成员表见 §3。

---

## 7. 方法总表 / 详表

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `deviceBusName` | 稳定小写名 | `DeviceBus bus` | `String` | 无；null 返回 `"other"` |
| `deviceBusFromName` | 名称解析 | `String name` | `DeviceBus?` | 无；未知/null 返回 null |

说明：

- `deviceBusName` 对 `Gpio`/`I2c`/`Spi`/`Camera`/`Bluetooth`/`Other` 分别返回 `"gpio"`/`"i2c"`/`"spi"`/`"camera"`/`"bluetooth"`/`"other"`。
- `deviceBusName` 的 null 输入返回 `"other"`，不抛错；这是诊断兜底，不表示 null 是合法设备。
- `deviceBusFromName` 先 `trim()` 再 `toLower()`；只接受稳定名，不接受本地化名称、平台路径、厂商字符串。
- `deviceBusFromName` 对 `"usb"` 返回 null；USB 不在本枚举。
- 两个函数都是纯函数、O(1)、无锁、可并发调用。

---

## 8. 使用的技术

- 简单枚举；
- 稳定名称映射；
- 大小写归一；
- 值语义。

---

## 9. 需要的支撑

- 语言：enum、String；
- 运行时：无；
- 接口：`GpioPin`、`I2cBus`、`SpiBus`、`CameraDevice` 的 `bus()` 返回本枚举。

---

## 10. 依赖的特性/接口/类

`GpioPin`、`I2cBus`、`SpiBus`、`CameraDevice`、`DeviceManager`。

`xdk.os.hardware.UsbDevice` 是独立清单类型，不依赖本枚举。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：按枚举底层值比较；可作 `Map`/`Set` 键；排序按声明顺序稳定。

---

## 12. 示例与反例

正确：`pin.bus() == DeviceBus.Gpio`；`deviceBusName(bus)` 写日志；`deviceBusFromName("i2c")` 解析配置。  
反例：把 `DeviceBus` 当硬件清单；新增 `Usb` 成员复制 `xdk.os.hardware`；用 `Bluetooth` 假设已有蓝牙控制；用本地化名称解析；把未知总线硬塞成 `Gpio`。

---

## 13. 测试/场景义务

六个成员名称/解析往返；大小写与空白；未知名称；null；`"usb"` 返回 null；`bus()` 与类型一致；枚举作 `Map` 键；追加成员不改变旧名称。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
enum DeviceBus {
    Gpio,
    I2c,
    Spi,
    Camera,
    Bluetooth,
    Other,
}

String deviceBusName(DeviceBus bus) {
    if bus == DeviceBus.Gpio { return "gpio" }
    if bus == DeviceBus.I2c { return "i2c" }
    if bus == DeviceBus.Spi { return "spi" }
    if bus == DeviceBus.Camera { return "camera" }
    if bus == DeviceBus.Bluetooth { return "bluetooth" }
    return "other"
}

DeviceBus? deviceBusFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "gpio" { return DeviceBus.Gpio }
    if normalized == "i2c" { return DeviceBus.I2c }
    if normalized == "spi" { return DeviceBus.Spi }
    if normalized == "camera" { return DeviceBus.Camera }
    if normalized == "bluetooth" { return DeviceBus.Bluetooth }
    if normalized == "other" { return DeviceBus.Other }
    return null
}
```
