# `GeoPolygon`

| 项 | 值 |
| --- | --- |
| 类型 | `class GeoPolygon` |
| 包 | `xdk.geo` |
| 稳定性 | `preview` |
| 依赖 | `GeoPoint`、`GeoPath`、`Geo` |

---

## 1. 定位

简单多边形：一个外环 `GeoPath`，提供点命中判断（经纬度平面射线法）。

不做：洞/多面、布尔运算、自交修复、面积/周长、地图数据、跨 180° 经线环绕。

---

## 2. 设计逻辑

- 外环 `_outerRing` 是 `GeoPath`；构造时派生去除显式闭合重复点后的 `_vertices`。
- 至少 3 个顶点；相邻顶点不能相等；显式闭合（首点=末点）会被规范化。
- `contains(point)` 在经纬度平面上做射线法；边界点算包含；不使用球面多边形算法。
- 自交环/共线退化环不在契约内；构造器不检测自交或面积，结果由射线法定义，调用方应保证简单、非退化环。
- 基线不支持洞；洞、多面、布尔运算是 X。
- 不可变；`outerRing()` 返回不可变外环引用，`vertexCount()` 返回规范化后的顶点数。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_outerRing` | `GeoPath` | final | 原始外环；不可变 |
| `_vertices` | `List<GeoPoint>` | final | 去闭合重复点后的顶点；至少 3 个 |

不变量：外环非 null；`_vertices` 至少 3 个；相邻顶点不相等；顶点非 null；不可变；`_vertices` 与 `_outerRing` 的点序一致（仅去掉一个闭合重复点）。

---

## 4. 生命周期

构造后不可变；无 close；可共享；无需刷新。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `GeoPolygon(GeoPath outerRing)` | `outerRing` | 非 null；至少 3 个点；去闭合重复点后至少 3 个；相邻顶点不相等 | null/点数不足/重复相邻点 → panic |

构造不检测自交；自交环不属于合法契约。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `outerRing` | 外环 | 无 | `GeoPath` | 无 |
| `vertexCount` | 规范化顶点数 | 无 | `Int` | 无 |
| `contains` | 点命中 | `GeoPoint point` | `Bool` | null → panic |
| `equals` | 值比较 | `GeoPolygon other` | `Bool` | null → false |
| `describe` | 单行摘要 | 无 | `String` | 无 |

说明：

- `outerRing()` 返回构造时的不可变 `GeoPath`；不会因调用方操作而改变。
- `vertexCount()` 是去掉显式闭合重复点后的顶点数；与 `outerRing().pointCount()` 可能差 1。
- `contains` 对边界点返回 `true`；对顶点/边上的点使用线段判断，避免射线法边界抖动。
- `contains` 复杂度 O(n)；不自交假设下结果符合常规多边形包含。
- `equals` 比较规范化后的顶点序；显式闭合与隐式闭合的相同环视为相等。
- 不提供 `area`/`perimeter`/`holes`；基线只做命中。

---

## 8. 使用的技术

- 外环规范化；
- 经纬度平面射线法；
- 线段边界判断；
- 列表复制与逐点相等。

---

## 9. 需要的支撑

- 语言：class、final 字段、List、Int、Bool、Double、String；
- 运行时：`abs(Double)`、`str(Int/Double)`；
- 接口：`GeoPoint`、`GeoPath`、`Geo`。

---

## 10. 依赖的特性/接口/类

`GeoPoint`、`GeoPath`、`Geo`。

---

## 11. 所有权与并发

不可变；无资源；可共享；无取消点。
`outerRing()` 返回不可变引用；`_vertices` 不暴露；`contains` 纯读取。
相等：`equals` 值语义；`==` 仍是引用身份；可作 `Map`/`Set` 键。

---

## 12. 示例与反例

正确：

```xnull
GeoPath ring = new GeoPath([
    new GeoPoint(0.0, 0.0),
    new GeoPoint(0.0, 10.0),
    new GeoPoint(10.0, 10.0),
    new GeoPoint(10.0, 0.0),
    new GeoPoint(0.0, 0.0)
])
GeoPolygon area = new GeoPolygon(ring)
Bool inside = area.contains(new GeoPoint(5.0, 5.0))
```

反例：用 2 个点构造多边形；依赖隐式洞；传入自交环并期望稳定结果；把 `outerRing().pointCount()` 当顶点数；用多边形做跨 180° 经线的环绕区域。

---

## 13. 测试/场景义务

3 点/4 点/显式闭合环；隐式闭合；顶点/边/内部/外部点；凹多边形；退化/共线环文档化行为；相邻重复点拒绝；自交环文档化行为；`vertexCount`；`equals` 显式/隐式闭合等价；`outerRing` 不可变；null panic；跨 180° 经线限制。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class GeoPolygon {
    final GeoPath _outerRing
    final List<GeoPoint> _vertices

    GeoPolygon(GeoPath outerRing) {
        if outerRing == null { throw "GeoPolygon: null outer ring" }
        List<GeoPoint> rawPoints = outerRing.points()
        if rawPoints.length() < 3 {
            throw "GeoPolygon: need at least three points"
        }
        if rawPoints.get(0).equals(rawPoints.get(rawPoints.length() - 1)) {
            rawPoints.remove(rawPoints.length() - 1)
        }
        if rawPoints.length() < 3 {
            throw "GeoPolygon: need at least three distinct vertices"
        }
        Int index = 0
        while index < rawPoints.length() {
            Int nextIndex = index + 1
            if nextIndex == rawPoints.length() { nextIndex = 0 }
            if rawPoints.get(index).equals(rawPoints.get(nextIndex)) {
                throw "GeoPolygon: duplicate adjacent vertex"
            }
            index = index + 1
        }
        _outerRing = outerRing
        _vertices = rawPoints.copy()
    }

    GeoPath outerRing() { return _outerRing }
    Int vertexCount() { return _vertices.length() }

    Bool contains(GeoPoint point) {
        if point == null { throw "GeoPolygon.contains: null point" }
        Bool inside = false
        Int index = 0
        while index < _vertices.length() {
            GeoPoint current = _vertices.get(index)
            Int nextIndex = index + 1
            if nextIndex == _vertices.length() { nextIndex = 0 }
            GeoPoint next = _vertices.get(nextIndex)
            if self.isPointOnSegment(point, current, next) {
                return true
            }
            Bool crosses = (current.latitude() > point.latitude())
                != (next.latitude() > point.latitude())
            if crosses {
                Double intersectionLongitude =
                    (next.longitude() - current.longitude())
                    * (point.latitude() - current.latitude())
                    / (next.latitude() - current.latitude())
                    + current.longitude()
                if point.longitude() < intersectionLongitude {
                    inside = !inside
                }
            }
            index = index + 1
        }
        return inside
    }

    private Bool isPointOnSegment(GeoPoint point, GeoPoint start, GeoPoint end) {
        Double cross = (point.latitude() - start.latitude())
            * (end.longitude() - start.longitude())
            - (point.longitude() - start.longitude())
            * (end.latitude() - start.latitude())
        if abs(cross) > 0.000000000001 { return false }
        Double dot = (point.longitude() - start.longitude())
            * (end.longitude() - start.longitude())
            + (point.latitude() - start.latitude())
            * (end.latitude() - start.latitude())
        if dot < 0.0 { return false }
        Double lengthSquared = (end.longitude() - start.longitude())
            * (end.longitude() - start.longitude())
            + (end.latitude() - start.latitude())
            * (end.latitude() - start.latitude())
        if dot > lengthSquared { return false }
        return true
    }

    Bool equals(GeoPolygon other) {
        if other == null { return false }
        List<GeoPoint> otherPoints = other.outerRing().points()
        if otherPoints.get(0).equals(
                otherPoints.get(otherPoints.length() - 1)) {
            otherPoints.remove(otherPoints.length() - 1)
        }
        if _vertices.length() != otherPoints.length() { return false }
        Int index = 0
        while index < _vertices.length() {
            if !_vertices.get(index).equals(otherPoints.get(index)) {
                return false
            }
            index = index + 1
        }
        return true
    }

    String describe() {
        return "geo polygon vertices=" + str(_vertices.length())
            + " ringPoints=" + str(_outerRing.pointCount())
    }
}
```
