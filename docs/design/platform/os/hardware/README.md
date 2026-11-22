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

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | `@Packed`、`@Align`、`@NativeLayout` |
| 本包消费 | `@Value`、`@Builder`、`@Serializable` |
| 处理器 | HardwareLayoutProcessor（Validate/Generate） |
| 生成物 | FFI 布局/对齐校验、硬件清单序列化 |
| 状态 | 领域注解 planned；A8 派生 planned；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 原生布局类型 | `@Packed`/`@Align`/`@NativeLayout` | 布局/对齐校验 |
| `HardwareInventory`/`BoardInfo`/`BiosInfo`/`PciDevice`/`UsbDevice`/`SensorReading` | `@Value`/`@Builder` | 值语义/构造 |

### 声明

```x
@Target(Type, Field)
@Retention(Binary)
@annotation Packed {
}

@Target(Type, Field)
@Retention(Binary)
@annotation Align {
    final Int value
}

@Target(Type)
@Retention(Binary)
@annotation NativeLayout {
}
```

### 使用

```x
@Packed
@Align(8)
@NativeLayout
class CHeader {
    @Align(4) Int code
    Long payload
}
```

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../../ANNOTATION-CATALOG.md)。
