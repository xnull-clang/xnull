# `HardwareInventory`

| 项 | 值 |
| --- | --- |
| 类型 | `class HardwareInventory` |
| 包 | `xdk.os.hardware` |
| 稳定性 | `preview` |
| 依赖 | `BoardInfo`、`BiosInfo`、`PciDevice`、`UsbDevice` |

---

## 1. 定位

硬件清单只读快照：主板、BIOS/UEFI、PCI/PCIe、USB、机箱类型。

不做：驱动绑定、固件升级、寄存器读写、热插拔事件、原始 SMBIOS 表。

---

## 2. 设计逻辑

- 不可变快照；由 `OsHost.hardwareInventory(context)` 返回。
- `board`/`bios` 可为 null（不可用/无权限）；列表为空表示无设备。
- `pciDevices`/`usbDevices` 返回副本。
- `chassis` 是机箱类型字符串；未知为空串。
- 不提供序列号/UUID/MAC；不提供写操作。
- 容器内只返回可见设备。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_board` | `BoardInfo?` | final | 可为 null |
| `_bios` | `BiosInfo?` | final | 可为 null |
| `_pciDevices` | `List<PciDevice>` | final | PCI 快照 |
| `_usbDevices` | `List<UsbDevice>` | final | USB 快照 |
| `_chassis` | `String` | final | 机箱类型/空 |

不变量：列表/字符串非 null；不可变；列表返回副本。

---

## 4. 生命周期

构造后不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `HardwareInventory(...)` | 5 个字段 | 列表/字符串非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `board` | 主板 | 无 | `BoardInfo?` | 无 |
| `bios` | BIOS/UEFI | 无 | `BiosInfo?` | 无 |
| `pciDevices` | PCI 快照 | 无 | `List<PciDevice>` | 无 |
| `usbDevices` | USB 快照 | 无 | `List<UsbDevice>` | 无 |
| `chassis` | 机箱类型 | 无 | `String` | 无 |
| `pciCount` | PCI 数 | 无 | `Int` | 无 |
| `usbCount` | USB 数 | 无 | `Int` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `equals` | 值比较 | `HardwareInventory other` | `Bool` | null → false |
| `copy` | 复制 | 无 | `HardwareInventory` | 无 |

---

## 8. 使用的技术

- 不可变快照；
- 列表复制；
- 可空快照字段；
- 字符串描述。

---

## 9. 需要的支撑

- 语言：class、final 字段、List、String、Bool；
- 运行时/适配器：sysfs/SetupAPI/IOKit；
- 接口：`BoardInfo`、`BiosInfo`、`PciDevice`、`UsbDevice`、`OsHost`。

---

## 10. 依赖的特性/接口/类

`BoardInfo`、`BiosInfo`、`PciDevice`、`UsbDevice`、`SensorReading`、`OsHost`。

---

## 11. 所有权与并发

不可变；可共享；列表返回副本；无资源；无取消点。
相等：`equals` 字段/列表比较；`==` 仍是引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：诊断显示主板/BIOS/PCI/USB 摘要；按 vendor/device ID 识别设备。  
反例：导出序列号；假设 board/bios 非 null；把 PCI 列表当驱动状态；容器内假设宿主全部。

---

## 13. 测试/场景义务

board/bios null；空列表；多 PCI/USB；chassis 空；equals/copy；容器裁剪；脱敏。

---

## 14. XNull 伪代码

```xnull
class HardwareInventory {
    final BoardInfo? _board
    final BiosInfo? _bios
    final List<PciDevice> _pciDevices
    final List<UsbDevice> _usbDevices
    final String _chassis

    HardwareInventory(BoardInfo? board, BiosInfo? bios,
                      List<PciDevice> pciDevices, List<UsbDevice> usbDevices,
                      String chassis) {
        if (pciDevices == null || usbDevices == null || chassis == null) {
            throw "HardwareInventory: null field"
        }
        _board = board
        _bios = bios
        _pciDevices = pciDevices.copy()
        _usbDevices = usbDevices.copy()
        _chassis = chassis
    }

    BoardInfo? board() { return _board }
    BiosInfo? bios() { return _bios }
    List<PciDevice> pciDevices() { return _pciDevices.copy() }
    List<UsbDevice> usbDevices() { return _usbDevices.copy() }
    String chassis() { return _chassis }
    Int pciCount() { return _pciDevices.length() }
    Int usbCount() { return _usbDevices.length() }

    String describe() {
        return "hardware pci=" + str(_pciDevices.length())
            + " usb=" + str(_usbDevices.length())
            + " chassis=" + _chassis
    }

    Bool equals(HardwareInventory other) {
        if other == null { return false }
        if (_board == null) {
            if other.board() != null { return false }
        } else {
            BoardInfo boardValue = _board as BoardInfo
            BoardInfo otherBoard = other.board() as BoardInfo
            if !boardValue.equals(otherBoard) { return false }
        }
        if (_bios == null) {
            if other.bios() != null { return false }
        } else {
            BiosInfo biosValue = _bios as BiosInfo
            BiosInfo otherBios = other.bios() as BiosInfo
            if !biosValue.equals(otherBios) { return false }
        }
        if _chassis != other.chassis() { return false }
        List<PciDevice> otherPci = other.pciDevices()
        if _pciDevices.length() != otherPci.length() { return false }
        Int index = 0
        while index < _pciDevices.length() {
            if !_pciDevices.get(index).equals(otherPci.get(index)) {
                return false
            }
            index = index + 1
        }
        List<UsbDevice> otherUsb = other.usbDevices()
        if _usbDevices.length() != otherUsb.length() { return false }
        index = 0
        while index < _usbDevices.length() {
            if !_usbDevices.get(index).equals(otherUsb.get(index)) {
                return false
            }
            index = index + 1
        }
        return true
    }

    HardwareInventory copy() {
        return new HardwareInventory(_board, _bios, _pciDevices, _usbDevices,
            _chassis)
    }
}
```
