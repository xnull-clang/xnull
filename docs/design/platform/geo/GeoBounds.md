# `GeoBounds`

| 项 | 值 |
| --- | --- |
| 类型 | `class GeoBounds` |
| 包 | `xdk.geo` |
| 稳定性 | `preview` |
| 依赖 | `GeoPoint` |

---

## 1. 定位

经纬度矩形边界：南/西/北/东四个边界值；用于点/边界包含判断、中心点与尺寸诊断。

不做：跨 180° 经线的环绕边界、空间索引、多边形、地图数据。

---

## 2. 设计逻辑

- 四个不可变字段 `_south`、`_west`、`_north`、`_east`，单位度。
- 合法域：`-90 <= south <= north <= 90`、`-180 <= west <= east <= 180`。
- 包含判断使用闭区间：边界上的点算包含。
- 不支持 `west > east` 的跨 180° 经线；需要时拆成两个边界。
- 值语义；`equals` 按四个字段比较；可作 `Map`/`Set` 键。
- 无资源；无 close；可共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_south` | `Double` | final | `-90..90` |
| `_west` | `Double` | final | `-180..180` |
| `_north` | `Double` | final | `-90..90`；`>= _south` |
| `_east` | `Double` | final | `-180..180`；`>= _west` |

不变量：字段有限；范围合法；`south <= north`；`west <= east`；不可变；列表/点参数不保留外部可变状态。

---

## 4. 生命周期

构造后不可变；无 close；可共享；无需刷新。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `GeoBounds(Double south, Double west, Double north, Double east)` | 四个边界 | 有限；范围合法；south≤north；west≤east | null/非有限/越界/顺序错误 → panic |

跨 180° 经线的 `west > east` 不是合法构造；调用方应拆分为两个 `GeoBounds`。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `south` | 南边界 | 无 | `Double` | 无 |
| `west` | 西边界 | 无 | `Double` | 无 |
| `north` | 北边界 | 无 | `Double` | 无 |
| `east` | 东边界 | 无 | `Double` | 无 |
| `containsPoint` | 点包含 | `GeoPoint point` | `Bool` | null → panic |
| `containsBounds` | 边界包含 | `GeoBounds other` | `Bool` | null → panic |
| `center` | 中心点 | 无 | `GeoPoint` | 无 |
| `widthDegrees` | 经度跨度 | 无 | `Double` | 无 |
| `heightDegrees` | 纬度跨度 | 无 | `Double` | 无 |
| `equals` | 值比较 | `GeoBounds other` | `Bool` | null → false |
| `describe` | 单行摘要 | 无 | `String` | 无 |

说明：

- `containsPoint` 使用闭区间；经度/纬度边界都包含。
- `containsBounds` 是矩形包含：`other` 的四个边界都落在本边界内；闭区间。
- `center` 返回 `((south+north)/2, (west+east)/2)`；不处理跨 180° 经线。
- `widthDegrees`/`heightDegrees` 只是角度差；不是米制距离。
- `equals` 精确比较四个 `Double`；不做容差。
- 不提供面积/相交/并集；这些是 X 或调用方组合。

---

## 8. 使用的技术

- 不可变矩形边界；
- 闭区间包含；
- 中点/跨度计算；
- 字段相等。

---

## 9. 需要的支撑

- 语言：class、final 字段、Double、Bool、String；
- 运行时：`isFinite(Double)`、`str(Double)`；
- 接口：`GeoPoint`、`Geo`。

---

## 10. 依赖的特性/接口/类

`GeoPoint`、`Geo`、`GeoPath`、`GeoPolygon`。

---

## 11. 所有权与并发

不可变；无资源；可共享；无取消点。
相等：`equals` 值语义；`==` 仍是引用身份；可作 `Map`/`Set` 键。

---

## 12. 示例与反例

正确：

```xnull
GeoBounds europe = new GeoBounds(35.0, -10.0, 60.0, 30.0)
Bool inside = europe.containsPoint(new GeoPoint(52.52, 13.405))
GeoPoint center = europe.center()
```

反例：构造 `new GeoBounds(60.0, -10.0, 35.0, 30.0)`（南>北）；用 `west=170, east=-170` 表示跨经线；把 `widthDegrees` 当公里；在边界外却期望 `containsBounds` 为 true。

---

## 13. 测试/场景义务

四个边界读取；边界点包含；边界外点；内部/外部边界包含；中心点；零宽/零高边界；顺序错误/越界/null/NaN panic；`equals`；`describe`；跨 180° 经线的拆分场景；与 `GeoPolygon.contains` 组合。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class GeoBounds {
    final Double _south
    final Double _west
    final Double _north
    final Double _east

    GeoBounds(Double south, Double west, Double north, Double east) {
        if south == null || west == null || north == null || east == null {
            throw "GeoBounds: null bound"
        }
        if !isFinite(south) || !isFinite(west)
            || !isFinite(north) || !isFinite(east) {
            throw "GeoBounds: non-finite bound"
        }
        if south < -90.0 || north > 90.0 || south > north {
            throw "GeoBounds: invalid latitude range"
        }
        if west < -180.0 || east > 180.0 || west > east {
            throw "GeoBounds: invalid longitude range"
        }
        _south = south
        _west = west
        _north = north
        _east = east
    }

    Double south() { return _south }
    Double west() { return _west }
    Double north() { return _north }
    Double east() { return _east }

    Bool containsPoint(GeoPoint point) {
        if point == null { throw "GeoBounds.containsPoint: null point" }
        if point.latitude() < _south || point.latitude() > _north {
            return false
        }
        if point.longitude() < _west || point.longitude() > _east {
            return false
        }
        return true
    }

    Bool containsBounds(GeoBounds other) {
        if other == null { throw "GeoBounds.containsBounds: null bounds" }
        if other.south() < _south || other.west() < _west {
            return false
        }
        if other.north() > _north || other.east() > _east {
            return false
        }
        return true
    }

    GeoPoint center() {
        Double centerLatitude = (_south + _north) / 2.0
        Double centerLongitude = (_west + _east) / 2.0
        return new GeoPoint(centerLatitude, centerLongitude)
    }

    Double widthDegrees() { return _east - _west }
    Double heightDegrees() { return _north - _south }

    Bool equals(GeoBounds other) {
        if other == null { return false }
        return _south == other.south()
            && _west == other.west()
            && _north == other.north()
            && _east == other.east()
    }

    String describe() {
        return "geo bounds south=" + str(_south)
            + " west=" + str(_west)
            + " north=" + str(_north)
            + " east=" + str(_east)
    }
}
```
