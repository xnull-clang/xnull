# `SensorKind`

| 项 | 值 |
| --- | --- |
| 类型 | `enum SensorKind` |
| 包 | `xdk.os.hardware` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

硬件传感器类型：温度、风扇、电压、电流、功率、其他。

不做：传感器驱动、采样循环、告警策略、安全联锁。

---

## 2. 设计逻辑

- 只区分物理量类型；具体单位由 `SensorReading.unit` 给出。
- `Other` 是合法值；未知传感器不 panic。
- 值语义；可作 `Map`/`Set` 键；成员固定，只允许追加。

---

## 3. 表示与不变量

| 成员 | 含义 | 默认单位 |
| --- | --- | --- |
| `Temperature` | 温度 | `C` |
| `Fan` | 风扇转速 | `RPM` |
| `Voltage` | 电压 | `V` |
| `Current` | 电流 | `A` |
| `Power` | 功率 | `W` |
| `Other` | 其他 | 空串 |

不变量：成员固定；只允许追加；值语义。

---

## 4. 生命周期

值类型；无构造器、无 close；可共享。

---

## 5. 构造契约

枚举项直接使用，无构造器。

---

## 6. 字段表

无实例字段。

---

## 7. 方法面

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `sensorKindName` | 稳定小写名 | `SensorKind kind` | `String` | 无 |
| `sensorKindFromName` | 名称解析 | `String name` | `SensorKind?` | 无；未知返回 null |
| `sensorKindDefaultUnit` | 默认单位 | `SensorKind kind` | `String` | 无 |

---

## 8. 使用的技术

- 简单枚举；
- 名称/单位映射。

---

## 9. 需要的支撑

- 语言：enum、String；
- 运行时：无；
- 接口：`SensorReading`。

---

## 10. 依赖的特性/接口/类

`SensorReading`、`HardwareInventory`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：按枚举底层值比较；可作 `Map` 键。

---

## 12. 示例与反例

正确：`reading.kind() == SensorKind.Temperature`。  
反例：用单位猜类型；未知类型 panic；应用扩展枚举。

---

## 13. 测试/场景义务

每个成员名称/解析/默认单位；未知名称；温度/风扇/电压/功率读数；与 `SensorReading` 组合。

---

## 14. XNull 伪代码

```xnull
enum SensorKind {
    Temperature,
    Fan,
    Voltage,
    Current,
    Power,
    Other,
}

String sensorKindName(SensorKind kind) {
    if kind == SensorKind.Temperature { return "temperature" }
    if kind == SensorKind.Fan { return "fan" }
    if kind == SensorKind.Voltage { return "voltage" }
    if kind == SensorKind.Current { return "current" }
    if kind == SensorKind.Power { return "power" }
    return "other"
}

SensorKind? sensorKindFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "temperature" { return SensorKind.Temperature }
    if normalized == "fan" { return SensorKind.Fan }
    if normalized == "voltage" { return SensorKind.Voltage }
    if normalized == "current" { return SensorKind.Current }
    if normalized == "power" { return SensorKind.Power }
    if normalized == "other" { return SensorKind.Other }
    return null
}

String sensorKindDefaultUnit(SensorKind kind) {
    if kind == SensorKind.Temperature { return "C" }
    if kind == SensorKind.Fan { return "RPM" }
    if kind == SensorKind.Voltage { return "V" }
    if kind == SensorKind.Current { return "A" }
    if kind == SensorKind.Power { return "W" }
    return ""
}
```
