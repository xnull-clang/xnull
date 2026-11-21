# `StorageInventory`

| 项 | 值 |
| --- | --- |
| 类型 | `class StorageInventory` |
| 包 | `xdk.os.storage` |
| 稳定性 | `preview` |
| 依赖 | `StorageDevice`、`Partition` |

---

## 1. 定位

存储清单只读快照：磁盘/SSD 设备与分区。

不做：文件读写、挂载/卸载、格式化、分区表编辑、RAID/LVM、加密。

---

## 2. 设计逻辑

- 不可变快照；由 `OsHost.storageInventory(context)` 返回。
- `devices`/`partitions` 返回副本；空列表表示无设备/不可见。
- 不自动刷新；热插拔/挂载变化重新探测。
- 不提供写操作；不暴露序列号/WWN。
- `findDevice`/`partitionsFor` 便于关联。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_devices` | `List<StorageDevice>` | final | 设备快照 |
| `_partitions` | `List<Partition>` | final | 分区快照 |

不变量：列表非 null；不可变；列表返回副本。

---

## 4. 生命周期

构造后不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `StorageInventory(...)` | 2 个列表 | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `devices` | 设备快照 | 无 | `List<StorageDevice>` | 无 |
| `partitions` | 分区快照 | 无 | `List<Partition>` | 无 |
| `deviceCount` | 设备数 | 无 | `Int` | 无 |
| `partitionCount` | 分区数 | 无 | `Int` | 无 |
| `findDevice` | 按 ID 查设备 | `String deviceId` | `StorageDevice?` | null → panic |
| `partitionsFor` | 设备的分区 | `String deviceId` | `List<Partition>` | null → panic |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `equals` | 值比较 | `StorageInventory other` | `Bool` | null → false |
| `copy` | 复制 | 无 | `StorageInventory` | 无 |

---

## 8. 使用的技术

- 不可变快照；
- 列表复制/查找；
- 字符串描述。

---

## 9. 需要的支撑

- 语言：class、final 字段、List、String、Bool；
- 运行时/适配器：存储枚举；
- 接口：`StorageDevice`、`Partition`、`OsHost`。

---

## 10. 依赖的特性/接口/类

`StorageDevice`、`Partition`、`OsHost`。

---

## 11. 所有权与并发

不可变；可共享；列表返回副本；无资源；无取消点。
相等：`equals` 字段/列表比较；`==` 仍是引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：巡检显示设备/分区；按 `deviceId` 关联。  
反例：用挂载点做持久 ID；假设列表非空；把容量当可用；容器内假设宿主全部。

---

## 13. 测试/场景义务

空清单；单/多设备；多分区；未挂载；findDevice/partitionsFor；equals/copy；热插拔后重新探测。

---

## 14. XNull 伪代码

```xnull
class StorageInventory {
    final List<StorageDevice> _devices
    final List<Partition> _partitions

    StorageInventory(List<StorageDevice> devices, List<Partition> partitions) {
        if devices == null || partitions == null {
            throw "StorageInventory: null list"
        }
        _devices = devices.copy()
        _partitions = partitions.copy()
    }

    List<StorageDevice> devices() { return _devices.copy() }
    List<Partition> partitions() { return _partitions.copy() }
    Int deviceCount() { return _devices.length() }
    Int partitionCount() { return _partitions.length() }

    StorageDevice? findDevice(String deviceId) {
        if deviceId == null { throw "StorageInventory.findDevice: null id" }
        Int index = 0
        while index < _devices.length() {
            if _devices.get(index).deviceId() == deviceId {
                return _devices.get(index)
            }
            index = index + 1
        }
        return null
    }

    List<Partition> partitionsFor(String deviceId) {
        if deviceId == null {
            throw "StorageInventory.partitionsFor: null id"
        }
        List<Partition> result = []
        Int index = 0
        while index < _partitions.length() {
            if _partitions.get(index).deviceId() == deviceId {
                result.push(_partitions.get(index))
            }
            index = index + 1
        }
        return result
    }

    String describe() {
        return "storage devices=" + str(_devices.length())
            + " partitions=" + str(_partitions.length())
    }

    Bool equals(StorageInventory other) {
        if other == null { return false }
        List<StorageDevice> otherDevices = other.devices()
        if _devices.length() != otherDevices.length() { return false }
        Int index = 0
        while index < _devices.length() {
            if !_devices.get(index).equals(otherDevices.get(index)) {
                return false
            }
            index = index + 1
        }
        List<Partition> otherPartitions = other.partitions()
        if _partitions.length() != otherPartitions.length() { return false }
        index = 0
        while index < _partitions.length() {
            if !_partitions.get(index).equals(otherPartitions.get(index)) {
                return false
            }
            index = index + 1
        }
        return true
    }

    StorageInventory copy() {
        return new StorageInventory(_devices, _partitions)
    }
}
```
