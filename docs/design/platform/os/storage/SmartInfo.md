# `SmartInfo`

| 项 | 值 |
| --- | --- |
| 类型 | `class SmartInfo` |
| 包 | `xdk.os.storage` |
| 稳定性 | `preview` |
| 依赖 | `SmartHealth` |

---

## 1. 定位

SMART 健康摘要：健康分类、温度、通电小时、重分配扇区、是否可用。

不做：原始 SMART 属性表、NVMe 日志、故障预测、保修判断、安全联锁。

---

## 2. 设计逻辑

- 不可变快照；由 `StorageDevice.smart()` 返回。
- `kind` 是 `SmartHealth`；`isAvailable` 表示数据是否成功读取。
- 温度可为 NaN（未知）；通电小时/重分配扇区 ≥0。
- 读数因厂商/协议而异；仅诊断。
- 不提供写入/清除 SMART。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_kind` | `SmartHealth` | final | 非 null |
| `_temperatureCelsius` | `Double` | final | 可为 NaN |
| `_powerOnHours` | `Long` | final | ≥0 |
| `_reallocatedSectors` | `Long` | final | ≥0 |
| `_isAvailable` | `Bool` | final | 数据是否可用 |

不变量：kind 非 null；小时/扇区 ≥0；不可变。

---

## 4. 生命周期

构造后不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `SmartInfo(...)` | 5 个字段 | kind 非 null；小时/扇区 ≥0 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `kind` | 健康分类 | 无 | `SmartHealth` | 无 |
| `temperatureCelsius` | 温度 | 无 | `Double` | 无 |
| `powerOnHours` | 通电小时 | 无 | `Long` | 无 |
| `reallocatedSectors` | 重分配扇区 | 无 | `Long` | 无 |
| `isAvailable` | 是否可用 | 无 | `Bool` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `equals` | 值比较 | `SmartInfo other` | `Bool` | null → false |
| `copy` | 复制 | 无 | `SmartInfo` | 无 |

---

## 8. 使用的技术

- 不可变快照；
- SMART/NVMe 读取；
- 双精度温度。

---

## 9. 需要的支撑

- 语言：class、final 字段、Double、Long、Bool；
- 运行时/适配器：SMART ioctl/NVMe 日志；
- 接口：`SmartHealth`、`StorageDevice`。

---

## 10. 依赖的特性/接口/类

`SmartHealth`、`StorageDevice`、`StorageInventory`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：`equals` 字段比较；`==` 仍是引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：巡检读取健康/温度/重分配扇区；`isAvailable` 为 false 时显示“未知”。  
反例：用 SMART 替代备份；把 NaN 当 0；用重分配扇区预测寿命。

---

## 13. 测试/场景义务

Good/Warning/Critical/Unknown；不可用；NaN 温度；边界小时/扇区；equals/copy。

---

## 14. XNull 伪代码

```xnull
class SmartInfo {
    final SmartHealth _kind
    final Double _temperatureCelsius
    final Long _powerOnHours
    final Long _reallocatedSectors
    final Bool _isAvailable

    SmartInfo(SmartHealth kind, Double temperatureCelsius,
              Long powerOnHours, Long reallocatedSectors, Bool isAvailable) {
        if kind == null { throw "SmartInfo: null kind" }
        if powerOnHours < 0 || reallocatedSectors < 0 {
            throw "SmartInfo: negative field"
        }
        _kind = kind
        _temperatureCelsius = temperatureCelsius
        _powerOnHours = powerOnHours
        _reallocatedSectors = reallocatedSectors
        _isAvailable = isAvailable
    }

    SmartHealth kind() { return _kind }
    Double temperatureCelsius() { return _temperatureCelsius }
    Long powerOnHours() { return _powerOnHours }
    Long reallocatedSectors() { return _reallocatedSectors }
    Bool isAvailable() { return _isAvailable }

    String describe() {
        if !_isAvailable { return "smart unavailable" }
        return "smart " + smartHealthName(_kind)
            + " temp=" + str(_temperatureCelsius)
            + " hours=" + str(_powerOnHours)
            + " reallocated=" + str(_reallocatedSectors)
    }

    Bool equals(SmartInfo other) {
        if other == null { return false }
        return _kind == other.kind()
            && _temperatureCelsius == other.temperatureCelsius()
            && _powerOnHours == other.powerOnHours()
            && _reallocatedSectors == other.reallocatedSectors()
            && _isAvailable == other.isAvailable()
    }

    SmartInfo copy() {
        return new SmartInfo(_kind, _temperatureCelsius, _powerOnHours,
            _reallocatedSectors, _isAvailable)
    }
}
```
