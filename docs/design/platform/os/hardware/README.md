# `xdk.os.hardware` 主板/BIOS/PCI/USB/传感器

| 项 | 值 |
| --- | --- |
| 包 | `xdk.os.hardware` |
| 层 | os / `xdk.os` |
| 依赖 | `xdk.core`、`xdk.os` |
| 能力 | `Pci`、`Usb`、`Sensors` |
| 稳定性 | `preview` |

---

## 1. 定位

硬件清单只读快照：主板、BIOS/UEFI、PCI/PCIe、USB、底盘、传感器读数。

不做：驱动绑定、固件升级、寄存器读写、设备热插拔事件、SMBIOS 原始字节、序列号导出。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 只读 | 清单只读；写入/控制归 ecosystem |
| 脱敏 | 不暴露序列号、UUID、MAC；厂商/型号可选 |
| 快照 | 不自动刷新；热插拔需重新探测 |
| 权限 | 读取可能受 OS 限制；失败 `PermissionDenied`/`Unsupported` |
| 容器 | 返回容器可见设备，不承诺宿主全部 |

---

## 3. 类型索引

| 类型 | 种类 | 文件 |
| --- | --- | --- |
| `HardwareInventory` | class | [`HardwareInventory.md`](HardwareInventory.md) |
| `BoardInfo` | class | [`BoardInfo.md`](BoardInfo.md) |
| `BiosInfo` | class | [`BiosInfo.md`](BiosInfo.md) |
| `PciDevice` | class | [`PciDevice.md`](PciDevice.md) |
| `UsbDevice` | class | [`UsbDevice.md`](UsbDevice.md) |
| `SensorKind` | enum | [`SensorKind.md`](SensorKind.md) |
| `SensorReading` | class | [`SensorReading.md`](SensorReading.md) |

---

## 4. 跨类型规则

- 先 `OsProfile.has(OsCapability.Pci/Usb/Sensors)`，再调用 `OsHost`。
- `board`/`bios` 可为 null；列表为空表示无设备/不可见。
- 不提供序列号/UUID/MAC；日志默认脱敏。
- 不提供 BAR/寄存器/配置空间/描述符写入。
- 传感器读数仅诊断，不用于安全联锁。
- 热插拔/设备事件是 X；当前快照不自动更新。

---

## 5. 场景

- 服务器资产/兼容性检查：只读 PCI/USB/主板/BIOS。
- 监控：传感器读数进入指标；不用于安全联锁。
- 桌面：显示硬件信息；不暴露序列号。

---

## 6. 缺口

- 设备热插拔事件：X `DeviceWatcher`。
- SMART/磁盘：见 `xdk.os.storage`。
- 固件升级/驱动绑定/寄存器：ecosystem/FFI。
- 序列号/UUID/MAC：默认不导出；需要时由 OS 工具/授权接口提供。
