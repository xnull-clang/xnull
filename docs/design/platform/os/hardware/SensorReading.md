# `SensorReading`

| 项 | 值 |
| --- | --- |
| 类型 | `class SensorReading` |
| 包 | `xdk.os.hardware` |
| 稳定性 | `preview` |
| 依赖 | `SensorKind` |

---

## 1. 定位

单次传感器读数：类型、名称、数值、单位、是否临界。

不做：采样循环、告警、历史、校准、控制风扇/电压。

---

## 2. 设计逻辑

- 不可变快照；由 `OsHost.sensors(context)` 或 `HardwareInventory` 返回。
- `value` 是 `Double`；单位由 `unit` 给出。
- `isCritical` 是 OS/驱动报告的高危标记；不用于安全联锁。
- 读数可能瞬时/不准；不用于计费/保护。
- 不提供写入/控制。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_kind` | `SensorKind` | final | 非 null |
| `_name` | `String` | final | 非空 |
| `_value` | `Double` | final | 可为 NaN/Inf？ |
| `_unit` | `String` | final | 可为空 |
| `_isCritical` | `Bool` | final | 是否临界 |

不变量：kind 非 null；name 非空；unit 非 null；不可变。

---

## 4. 生命周期

构造后不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `SensorReading(...)` | 5 个字段 | kind 非 null；name 非空；unit 非 null | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `kind` | 类型 | 无 | `SensorKind` | 无 |
| `name` | 名称 | 无 | `String` | 无 |
| `value` | 数值 | 无 | `Double` | 无 |
| `unit` | 单位 | 无 | `String` | 无 |
| `isCritical` | 是否临界 | 无 | `Bool` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `equals` | 值比较 | `SensorReading other` | `Bool` | null → false |
| `copy` | 复制 | 无 | `SensorReading` | 无 |

说明：

- `value` 允许 NaN/Inf（例如无效读数）；调用方需检查。
- 不承诺 `unit` 与 `kind` 默认单位一致；以 `unit` 为准。

---

## 8. 使用的技术

- 不可变快照；
- 枚举/双精度；
- 字符串描述。

---

## 9. 需要的支撑

- 语言：class、final 字段、Double、String、Bool；
- 运行时/适配器：sysfs/IOKit/WMI 传感器；
- 接口：`SensorKind`、`HardwareInventory`。

---

## 10. 依赖的特性/接口/类

`SensorKind`、`HardwareInventory`、`OsHost`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：`equals` 字段比较；`==` 仍是引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：`reading.kind() == SensorKind.Temperature`；日志脱敏。  
反例：用读数做安全联锁；假设单位固定；忽略 NaN；把临界当故障。

---

## 13. 测试/场景义务

温度/风扇/电压/功率；空单位；NaN/Inf；临界标记；equals/copy；多传感器。

---

## 14. XNull 伪代码

```xnull
class SensorReading {
    final SensorKind _kind
    final String _name
    final Double _value
    final String _unit
    final Bool _isCritical

    SensorReading(SensorKind kind, String name, Double value,
                  String unit, Bool isCritical) {
        if kind == null || name == null || name == "" || unit == null {
            throw "SensorReading: null/empty field"
        }
        _kind = kind
        _name = name
        _value = value
        _unit = unit
        _isCritical = isCritical
    }

    SensorKind kind() { return _kind }
    String name() { return _name }
    Double value() { return _value }
    String unit() { return _unit }
    Bool isCritical() { return _isCritical }

    String describe() {
        String suffix = ""
        if _isCritical { suffix = " critical" }
        return _name + "=" + str(_value) + _unit + suffix
    }

    Bool equals(SensorReading other) {
        if other == null { return false }
        return _kind == other.kind()
            && _name == other.name()
            && _value == other.value()
            && _unit == other.unit()
            && _isCritical == other.isCritical()
    }

    SensorReading copy() {
        return new SensorReading(_kind, _name, _value, _unit, _isCritical)
    }
}
```
