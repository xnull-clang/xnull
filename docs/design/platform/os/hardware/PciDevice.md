# `PciDevice`

| 项 | 值 |
| --- | --- |
| 类型 | `class PciDevice` |
| 包 | `xdk.os.hardware` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

PCI/PCIe 设备只读快照：地址、厂商标识、设备标识、类码、驱动、启用状态。

不做：配置空间读写、BAR 映射、驱动绑定、热插拔事件、寄存器访问。

---

## 2. 设计逻辑

- 不可变快照；由 `HardwareInventory.pciDevices()` 返回。
- `address` 是 `0000:00:1f.2` 形式；未知为空串。
- `vendorId`/`deviceId` 是 16 位 ID；`classCode` 是十六进制字符串。
- `driver` 是当前绑定驱动名；未知为空串。
- `isEnabled` 表示设备是否启用/可见。
- 不提供序列号/子系统 ID 之外的敏感信息；不提供写操作。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_address` | `String` | final | PCI 地址/空 |
| `_vendorId` | `Int` | final | 0..65535 |
| `_deviceId` | `Int` | final | 0..65535 |
| `_classCode` | `String` | final | 十六进制/空 |
| `_driver` | `String` | final | 驱动名/空 |
| `_isEnabled` | `Bool` | final | 是否启用 |

不变量：ID 0..65535；字符串非 null；不可变。

---

## 4. 生命周期

构造后不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `PciDevice(...)` | 6 个字段 | ID 0..65535；字符串非 null | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `address` | PCI 地址 | 无 | `String` | 无 |
| `vendorId` | 厂商 ID | 无 | `Int` | 无 |
| `deviceId` | 设备 ID | 无 | `Int` | 无 |
| `classCode` | 类码 | 无 | `String` | 无 |
| `driver` | 驱动 | 无 | `String` | 无 |
| `isEnabled` | 是否启用 | 无 | `Bool` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `equals` | 值比较 | `PciDevice other` | `Bool` | null → false |
| `copy` | 复制 | 无 | `PciDevice` | 无 |

---

## 8. 使用的技术

- 不可变快照；
- PCI 地址/ID；
- 字符串描述。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Int、Bool；
- 运行时/适配器：sysfs/SetupAPI/IOKit；
- 接口：`HardwareInventory`。

---

## 10. 依赖的特性/接口/类

`HardwareInventory`、`UsbDevice`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：`equals` 字段比较；`==` 仍是引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：按 vendor/device ID 识别设备；显示驱动名。  
反例：写配置空间；用地址做持久 ID；假设地址格式固定。

---

## 13. 测试/场景义务

地址格式；ID 边界 0/65535；未知驱动；启用/禁用；equals/copy；多设备。

---

## 14. XNull 伪代码

```xnull
class PciDevice {
    final String _address
    final Int _vendorId
    final Int _deviceId
    final String _classCode
    final String _driver
    final Bool _isEnabled

    PciDevice(String address, Int vendorId, Int deviceId, String classCode,
              String driver, Bool isEnabled) {
        if address == null || classCode == null || driver == null {
            throw "PciDevice: null string"
        }
        if vendorId < 0 || vendorId > 65535 || deviceId < 0 || deviceId > 65535 {
            throw "PciDevice: invalid id"
        }
        _address = address
        _vendorId = vendorId
        _deviceId = deviceId
        _classCode = classCode
        _driver = driver
        _isEnabled = isEnabled
    }

    String address() { return _address }
    Int vendorId() { return _vendorId }
    Int deviceId() { return _deviceId }
    String classCode() { return _classCode }
    String driver() { return _driver }
    Bool isEnabled() { return _isEnabled }

    String describe() {
        return _address + " " + str(_vendorId) + ":" + str(_deviceId)
            + " class=" + _classCode
            + " driver=" + _driver
    }

    Bool equals(PciDevice other) {
        if other == null { return false }
        return _address == other.address()
            && _vendorId == other.vendorId()
            && _deviceId == other.deviceId()
            && _classCode == other.classCode()
            && _driver == other.driver()
            && _isEnabled == other.isEnabled()
    }

    PciDevice copy() {
        return new PciDevice(_address, _vendorId, _deviceId, _classCode,
            _driver, _isEnabled)
    }
}
```
