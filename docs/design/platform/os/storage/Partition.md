# `Partition`

| 项 | 值 |
| --- | --- |
| 类型 | `class Partition` |
| 包 | `xdk.os.storage` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

分区只读快照：分区 ID、所属设备、挂载点、文件系统、容量、可用空间。

不做：挂载/卸载、格式化、分区表编辑、配额、加密。

---

## 2. 设计逻辑

- 不可变快照；由 `StorageInventory.partitions()` 返回。
- `partitionId`/`deviceId` 非空；`mountPoint` 可为空（未挂载）。
- `fileSystem` 可为空；`sizeBytes`/`freeBytes` ≥0。
- `freeBytes` 可能未知（0）或大于 `sizeBytes` 的异常值；实现应钳制/标记。
- 不提供写操作。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_partitionId` | `String` | final | 非空 |
| `_deviceId` | `String` | final | 非空 |
| `_mountPoint` | `String` | final | 可为空 |
| `_fileSystem` | `String` | final | 可为空 |
| `_sizeBytes` | `Long` | final | ≥0 |
| `_freeBytes` | `Long` | final | ≥0 |

不变量：id 非空；大小 ≥0；不可变。

---

## 4. 生命周期

构造后不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Partition(...)` | 6 个字段 | id 非空；大小 ≥0 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `partitionId` | 分区 ID | 无 | `String` | 无 |
| `deviceId` | 设备 ID | 无 | `String` | 无 |
| `mountPoint` | 挂载点 | 无 | `String` | 无 |
| `fileSystem` | 文件系统 | 无 | `String` | 无 |
| `sizeBytes` | 容量 | 无 | `Long` | 无 |
| `freeBytes` | 可用 | 无 | `Long` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `equals` | 值比较 | `Partition other` | `Bool` | null → false |
| `copy` | 复制 | 无 | `Partition` | 无 |

---

## 8. 使用的技术

- 不可变快照；
- 分区/文件系统枚举；
- 字符串描述。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Long、Bool；
- 运行时/适配器：mountinfo/sysfs/IOKit/Windows volume API；
- 接口：`StorageDevice`、`StorageInventory`。

---

## 10. 依赖的特性/接口/类

`StorageDevice`、`StorageInventory`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：`equals` 字段比较；`==` 仍是引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：按 `deviceId` 关联设备；显示挂载点/文件系统/可用空间。  
反例：用挂载点做持久 ID；假设 freeBytes 精确；未挂载时 panic。

---

## 13. 测试/场景义务

已挂载/未挂载；空文件系统；free=0；多分区；equals/copy；容器/overlay。

---

## 14. XNull 伪代码

```xnull
class Partition {
    final String _partitionId
    final String _deviceId
    final String _mountPoint
    final String _fileSystem
    final Long _sizeBytes
    final Long _freeBytes

    Partition(String partitionId, String deviceId, String mountPoint,
              String fileSystem, Long sizeBytes, Long freeBytes) {
        if partitionId == null || partitionId == "" {
            throw "Partition: empty partition id"
        }
        if deviceId == null || deviceId == "" {
            throw "Partition: empty device id"
        }
        if mountPoint == null || fileSystem == null {
            throw "Partition: null string"
        }
        if sizeBytes < 0 || freeBytes < 0 {
            throw "Partition: negative size"
        }
        _partitionId = partitionId
        _deviceId = deviceId
        _mountPoint = mountPoint
        _fileSystem = fileSystem
        _sizeBytes = sizeBytes
        _freeBytes = freeBytes
    }

    String partitionId() { return _partitionId }
    String deviceId() { return _deviceId }
    String mountPoint() { return _mountPoint }
    String fileSystem() { return _fileSystem }
    Long sizeBytes() { return _sizeBytes }
    Long freeBytes() { return _freeBytes }

    String describe() {
        return "partition " + _partitionId
            + " device=" + _deviceId
            + " mount=" + _mountPoint
            + " fs=" + _fileSystem
            + " free=" + str(_freeBytes) + "/" + str(_sizeBytes)
    }

    Bool equals(Partition other) {
        if other == null { return false }
        return _partitionId == other.partitionId()
            && _deviceId == other.deviceId()
            && _mountPoint == other.mountPoint()
            && _fileSystem == other.fileSystem()
            && _sizeBytes == other.sizeBytes()
            && _freeBytes == other.freeBytes()
    }

    Partition copy() {
        return new Partition(_partitionId, _deviceId, _mountPoint, _fileSystem,
            _sizeBytes, _freeBytes)
    }
}
```
