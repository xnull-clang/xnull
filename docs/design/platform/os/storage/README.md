# `xdk.os.storage` 存储设备/分区/SMART

| 项 | 值 |
| --- | --- |
| 包 | `xdk.os.storage` |
| 层 | os / `xdk.os` |
| 依赖 | `xdk.core`、`xdk.os` |
| 能力 | `Storage` |
| 稳定性 | `preview` |

---

## 1. 定位

存储设备、分区、文件系统、SMART 健康快照。

不做：文件读写（`xdk.fs`）、挂载/卸载（X）、分区表编辑、格式化、RAID 管理、加密。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 只读 | 设备/分区/SMART 默认只读 |
| 单位 | 容量/字节用 `Long` |
| 脱敏 | 不暴露序列号/World Wide Name；型号可空 |
| 快照 | 不自动刷新；热插拔重新探测 |
| 权限 | SMART/分区信息可能需权限；失败显式 |

---

## 3. 类型索引

| 类型 | 种类 | 文件 |
| --- | --- | --- |
| `StorageInventory` | class | [`StorageInventory.md`](StorageInventory.md) |
| `StorageDevice` | class | [`StorageDevice.md`](StorageDevice.md) |
| `Partition` | class | [`Partition.md`](Partition.md) |
| `SmartHealth` | enum | [`SmartHealth.md`](SmartHealth.md) |
| `SmartInfo` | class | [`SmartInfo.md`](SmartInfo.md) |

---

## 4. 跨类型规则

- 先 `OsProfile.has(OsCapability.Storage)`，再调用 `OsHost.storageInventory`。
- `deviceId`/`partitionId` 是关联键；设备名/挂载点不是持久 ID。
- `smart()` 可为 null；`SmartInfo.isAvailable` 为 false 表示读取失败。
- 不暴露序列号/WWN；不提供写操作。
- 挂载/格式化/分区表编辑是 X/ecosystem，不在只读基线。

---

## 5. 场景

- 服务器巡检：磁盘/分区/SMART 摘要。
- 桌面：显示磁盘容量/可移动设备。
- 监控：SMART 告警；不替代备份。

---

## 6. 缺口

- 挂载/卸载/分区表编辑：X，需特权。
- 加密/RAID/LVM：ecosystem。
- 原始 SMART/NVMe 日志：FFI/厂商工具。
- 热插拔事件：X `DeviceWatcher`。
