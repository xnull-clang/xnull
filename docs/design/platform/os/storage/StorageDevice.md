# `StorageDevice`

| 项 | 值 |
| --- | --- |
| 类型 | `class StorageDevice` |
| 包 | `xdk.os.storage` |
| 稳定性 | `preview` |
| 依赖 | `SmartInfo` |

---

## 1. 定位

存储设备只读快照：设备 ID、名称、型号、容量、可移动/固态、SMART 摘要。

不做：读写/格式化/分区/挂载、序列号/WWN、RAID/LVM、加密。

---

## 2. 设计逻辑

- 不可变快照；由 `StorageInventory.devices()` 返回。
- `deviceId` 是稳定标识（实现可脱敏）；`name` 是 OS 设备名。
- `sizeBytes` 用 `Long`；`model` 可为空。
- `smart` 可为 null（不支持/无权限）。
- 不提供序列号/WWN；不提供写操作。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_deviceId` | `String` | final | 非空 |
| `_name` | `String` | final | 非空 |
| `_model` | `String` | final | 可为空 |
| `_sizeBytes` | `Long` | final | ≥0 |
| `_isRemovable` | `Bool` | final | 是否可移动 |
| `_isSolidState` | `Bool` | final | 是否 SSD |
| `_smart` | `SmartInfo?` | final | 可为 null |

不变量：deviceId/name 非空；size ≥0；不可变。

---

## 4. 生命周期

构造后不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `StorageDevice(...)` | 7 个字段 | id/name 非空；size ≥0 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `deviceId` | 设备 ID | 无 | `String` | 无 |
| `name` | 设备名 | 无 | `String` | 无 |
| `model` | 型号 | 无 | `String` | 无 |
| `sizeBytes` | 容量 | 无 | `Long` | 无 |
| `isRemovable` | 可移动 | 无 | `Bool` | 无 |
| `isSolidState` | 固态 | 无 | `Bool` | 无 |
| `smart` | SMART 摘要 | 无 | `SmartInfo?` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `equals` | 值比较 | `StorageDevice other` | `Bool` | null → false |
| `copy` | 复制 | 无 | `StorageDevice` | 无 |

---

## 8. 使用的技术

- 不可变快照；
- 设备枚举；
- SMART 组合。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Long、Bool；
- 运行时/适配器：sysfs/IOKit/Windows storage API；
- 接口：`SmartInfo`、`StorageInventory`。

---

## 10. 依赖的特性/接口/类

`SmartInfo`、`StorageInventory`、`Partition`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：`equals` 字段比较；`==` 仍是引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：按 `deviceId` 关联分区；显示容量/SSD/可移动。  
反例：用设备名做持久 ID；导出序列号；假设 SMART 一定可用；把容量当可用空间。

---

## 13. 测试/场景义务

HDD/SSD；可移动；空 model；SMART null/不可用；equals/copy；多设备。

---

## 14. XNull 伪代码

```xnull
class StorageDevice {
    final String _deviceId
    final String _name
    final String _model
    final Long _sizeBytes
    final Bool _isRemovable
    final Bool _isSolidState
    final SmartInfo? _smart

    StorageDevice(String deviceId, String name, String model, Long sizeBytes,
                  Bool isRemovable, Bool isSolidState, SmartInfo? smart) {
        if deviceId == null || deviceId == "" || name == null || name == "" {
            throw "StorageDevice: empty id/name"
        }
        if model == null { throw "StorageDevice: null model" }
        if sizeBytes < 0 { throw "StorageDevice: negative size" }
        _deviceId = deviceId
        _name = name
        _model = model
        _sizeBytes = sizeBytes
        _isRemovable = isRemovable
        _isSolidState = isSolidState
        _smart = smart
    }

    String deviceId() { return _deviceId }
    String name() { return _name }
    String model() { return _model }
    Long sizeBytes() { return _sizeBytes }
    Bool isRemovable() { return _isRemovable }
    Bool isSolidState() { return _isSolidState }
    SmartInfo? smart() { return _smart }

    String describe() {
        return name() + " " + _model
            + " size=" + str(_sizeBytes)
            + " ssd=" + str(_isSolidState)
    }

    Bool equals(StorageDevice other) {
        if other == null { return false }
        if _deviceId != other.deviceId()
            || _name != other.name()
            || _model != other.model()
            || _sizeBytes != other.sizeBytes()
            || _isRemovable != other.isRemovable()
            || _isSolidState != other.isSolidState() {
            return false
        }
        if _smart == null {
            return other.smart() == null
        }
        SmartInfo value = _smart as SmartInfo
        SmartInfo? otherSmart = other.smart()
        if otherSmart == null { return false }
        return value.equals(otherSmart as SmartInfo)
    }

    StorageDevice copy() {
        return new StorageDevice(_deviceId, _name, _model, _sizeBytes,
            _isRemovable, _isSolidState, _smart)
    }
}
```
