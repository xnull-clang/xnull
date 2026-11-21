# `GeoPoint`

| 项 | 值 |
| --- | --- |
| 类型 | `class GeoPoint` |
| 包 | `xdk.geo` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

WGS84 经纬度点：纬度/经度均为十进制度；用于距离、边界、路径、多边形与投影的输入。

不做：高度/海拔、坐标系标识、基准转换、时间、地图数据。

---

## 2. 设计逻辑

- 两个不可变字段 `_latitude`、`_longitude`；单位为度。
- 纬度合法域 `[-90, 90]`，经度合法域 `[-180, 180]`；越界或非有限值 → 构造 panic。
- 经度不做自动归一；需要 `[-180, 180)` 时调用 `Geo.normalizeLongitude`。
- 值语义：`equals` 按两个字段精确比较；可作 `Map`/`Set` 键。
- 不持有资源；无 close；可跨任务共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_latitude` | `Double` | final | `-90.0..90.0` |
| `_longitude` | `Double` | final | `-180.0..180.0` |

不变量：字段有限；范围合法；不可变；`equals` 与字段一一对应。

---

## 4. 生命周期

构造后不可变；无 close；可共享；无需刷新。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `GeoPoint(Double latitude, Double longitude)` | `latitude`、`longitude` | 有限；纬度 `-90..90`；经度 `-180..180` | null/非有限/越界 → panic |

构造 panic 表示调用方违反合同；来自外部输入的坐标应先校验再用 `Result` 通道处理。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `latitude` | 纬度 | 无 | `Double` | 无 |
| `longitude` | 经度 | 无 | `Double` | 无 |
| `equals` | 值比较 | `GeoPoint other` | `Bool` | null → false |
| `describe` | 单行摘要 | 无 | `String` | 无 |

说明：

- `latitude`/`longitude` 是纯读取，返回构造时的值。
- `equals` 精确比较两个 `Double`；`-0.0` 与 `0.0` 按语言 `==` 语义处理；不做容差。
- `describe` 只用于日志/诊断，不保证可解析；需要机器格式时由调用方格式化。
- 不提供 `distanceMeters`；距离统一走 `Geo.distanceMeters`，避免同一算法多处实现。

---

## 8. 使用的技术

- 不可变值对象；
- 十进制度坐标；
- 有限值/范围校验；
- 字段相等。

---

## 9. 需要的支撑

- 语言：class、final 字段、Double、Bool、String；
- 运行时：`isFinite(Double)`、`str(Double)`；
- 接口：`Geo`、`GeoBounds`、`GeoPath`、`GeoPolygon`。

---

## 10. 依赖的特性/接口/类

`Geo`、`GeoBounds`、`GeoPath`、`GeoPolygon`、`GeoProjection`。

---

## 11. 所有权与并发

不可变；无资源；可共享；无取消点。
相等：`equals` 值语义；`==` 仍是引用身份；推荐作 `Map`/`Set` 键时使用不可变点。

---

## 12. 示例与反例

正确：

```xnull
GeoPoint berlin = new GeoPoint(52.5200, 13.4050)
GeoPoint paris = new GeoPoint(48.8566, 2.3522)
Double distance = Geo.distanceMeters(berlin, paris)
```

反例：用 `new GeoPoint(91.0, 0.0)` 表示未知位置；把经度 `190.0` 直接传入；用 `==` 比较两个不同对象的值；把海拔塞进经度字段。

---

## 13. 测试/场景义务

纬度边界 `-90`/`90`；经度边界 `-180`/`180`；越界/NaN/Infinity/null panic；`equals` 自反/对称/传递；`describe` 非空；与 `GeoBounds`/`GeoPath`/`GeoPolygon` 组合；跨 180° 经线的点仍可表示。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class GeoPoint {
    final Double _latitude
    final Double _longitude

    GeoPoint(Double latitude, Double longitude) {
        if latitude == null || longitude == null {
            throw "GeoPoint: null coordinate"
        }
        if !isFinite(latitude) || !isFinite(longitude) {
            throw "GeoPoint: non-finite coordinate"
        }
        if latitude < -90.0 || latitude > 90.0 {
            throw "GeoPoint: latitude out of range"
        }
        if longitude < -180.0 || longitude > 180.0 {
            throw "GeoPoint: longitude out of range"
        }
        _latitude = latitude
        _longitude = longitude
    }

    Double latitude() { return _latitude }
    Double longitude() { return _longitude }

    Bool equals(GeoPoint other) {
        if other == null { return false }
        return _latitude == other.latitude()
            && _longitude == other.longitude()
    }

    String describe() {
        return "geo point lat=" + str(_latitude)
            + " lon=" + str(_longitude)
    }
}
```
