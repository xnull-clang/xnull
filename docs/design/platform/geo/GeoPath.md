# `GeoPath`

| 项 | 值 |
| --- | --- |
| 类型 | `class GeoPath` |
| 包 | `xdk.geo` |
| 稳定性 | `preview` |
| 依赖 | `GeoPoint`、`Geo` |

---

## 1. 定位

有序经纬度点折线：点访问、点数、球面长度、是否显式闭合、值比较。

不做：资源关闭（路径没有 `close()`）、线段加密/抽稀、路网匹配、路径规划、地图数据。

---

## 2. 设计逻辑

- 唯一字段 `_points: List<GeoPoint>`；构造时复制列表，之后不可变。
- 至少 2 个点；每个点非 null；允许相邻点相同（零长度段），但会保留。
- `isClosed()` 仅当点数 `>=3` 且首点与末点 `equals`；不自动闭合，也不修改输入。
- `length()` 按顺序对相邻点调用 `Geo.distanceMeters`（WGS84 球面）并求和，单位米。
- `points()` 返回副本，避免调用方修改内部列表。
- `GeoPolygon` 可复用本类型作为外环；本类型不负责洞或面积。
- 无资源、无 `Context`、无取消点。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_points` | `List<GeoPoint>` | final | 至少 2 个；非 null；元素非 null |

不变量：列表是构造时快照；不随外部修改；`pointCount >= 2`；`isClosed` 只由首末点决定；不可变。

---

## 4. 生命周期

构造后不可变；无 close；可共享；无需刷新。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `GeoPath(List<GeoPoint> points)` | `points` | 非 null；至少 2 个；元素非 null | null/点数不足/元素 null → panic |

构造复制列表；调用方之后修改原列表不影响路径。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `points` | 点快照 | 无 | `List<GeoPoint>` | 无 |
| `pointCount` | 点数 | 无 | `Int` | 无 |
| `pointAt` | 按索引取点 | `Int pointIndex` | `GeoPoint` | 越界 → panic |
| `length` | 球面长度（米） | 无 | `Double` | 无 |
| `isClosed` | 是否显式闭合 | 无 | `Bool` | 无 |
| `equals` | 值比较 | `GeoPath other` | `Bool` | null → false |
| `describe` | 单行摘要 | 无 | `String` | 无 |

说明：

- `points()` 每次返回新列表；元素是不可变 `GeoPoint`，可安全共享。
- `pointAt` 的 `pointIndex` 合法域 `[0, pointCount-1]`；越界是合同错误。
- `length()` 复杂度 O(n)；坐标跨 180° 经线时 Haversine 仍按最短大圆段处理。
- `isClosed()` 不修改路径；`[A,B,A]` 为闭合，`[A,B]` 为非闭合。
- `equals` 按顺序逐点比较；不比较“几何等价但反向”的路径。
- 没有 `close()`；路径不是资源。

---

## 8. 使用的技术

- 不可变点列表；
- 列表复制；
- 球面逐段距离；
- 首末点闭合判断；
- 逐点相等。

---

## 9. 需要的支撑

- 语言：class、final 字段、List、Int、Double、Bool、String；
- 运行时：`Geo.distanceMeters`、`str(Int/Double)`；
- 接口：`GeoPoint`、`Geo`、`GeoPolygon`。

---

## 10. 依赖的特性/接口/类

`GeoPoint`、`Geo`、`GeoBounds`、`GeoPolygon`。

---

## 11. 所有权与并发

不可变；无资源；可共享；无取消点。
`points()` 返回副本；`pointAt` 返回不可变元素；`length`/`isClosed` 纯读取。
相等：`equals` 值语义；`==` 仍是引用身份；可作 `Map`/`Set` 键。

---

## 12. 示例与反例

正确：

```xnull
GeoPath route = new GeoPath([
    new GeoPoint(52.5200, 13.4050),
    new GeoPoint(50.1109, 8.6821),
    new GeoPoint(48.8566, 2.3522)
])
Double routeMeters = route.length()
Bool closed = route.isClosed()
```

反例：用空列表构造；把 `isClosed` 当资源关闭状态；期望 `length()` 返回点数；依赖构造后修改原列表改变路径；用路径表示多边形洞。

---

## 13. 测试/场景义务

2 点/3 点/多点；零长度段；显式闭合 `[A,B,A]` 与隐式多边形环；跨 180° 经线段；`pointAt` 越界 panic；`points()` 副本独立性；`equals` 顺序敏感；`length` 与已知距离对比；`describe`；null/点数不足构造 panic。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class GeoPath {
    final List<GeoPoint> _points

    GeoPath(List<GeoPoint> points) {
        if points == null { throw "GeoPath: null points" }
        if points.length() < 2 { throw "GeoPath: need at least two points" }
        Int index = 0
        while index < points.length() {
            if points.get(index) == null {
                throw "GeoPath: null point"
            }
            index = index + 1
        }
        _points = points.copy()
    }

    List<GeoPoint> points() { return _points.copy() }
    Int pointCount() { return _points.length() }

    GeoPoint pointAt(Int pointIndex) {
        if pointIndex < 0 || pointIndex >= _points.length() {
            throw "GeoPath.pointAt: index out of range"
        }
        return _points.get(pointIndex)
    }

    Double length() {
        Double totalMeters = 0.0
        Int index = 0
        while index + 1 < _points.length() {
            totalMeters = totalMeters + Geo.distanceMeters(
                _points.get(index), _points.get(index + 1))
            index = index + 1
        }
        return totalMeters
    }

    Bool isClosed() {
        if _points.length() < 3 { return false }
        return _points.get(0).equals(_points.get(_points.length() - 1))
    }

    Bool equals(GeoPath other) {
        if other == null { return false }
        List<GeoPoint> otherPoints = other.points()
        if _points.length() != otherPoints.length() { return false }
        Int index = 0
        while index < _points.length() {
            if !_points.get(index).equals(otherPoints.get(index)) {
                return false
            }
            index = index + 1
        }
        return true
    }

    String describe() {
        return "geo path points=" + str(_points.length())
            + " lengthMeters=" + str(self.length())
            + " closed=" + str(self.isClosed())
    }
}
```
