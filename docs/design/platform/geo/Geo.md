# `Geo`

| 项 | 值 |
| --- | --- |
| 类型 | `class Geo`（静态入口） |
| 包 | `xdk.geo` |
| 稳定性 | `preview` |
| 依赖 | `GeoPoint`、`GeoProjection`、`Pair` |

---

## 1. 定位

地理静态运算：Haversine 距离、初始方位、按方位/距离求终点、大圆中点、经度归一、Web Mercator 投影/反投影。

不做：地图瓦片、地理编码、路径规划、椭球测地线、UTM 实现、坐标基准转换、空间索引。

---

## 2. 设计逻辑

- 无实例字段；所有方法静态、无状态、纯计算（投影只做数学）。
- 距离/方位/终点/中点使用 WGS84 球面近似，地球平均半径 `6371008.8` 米；不是椭球测地线。
- `project`/`unproject` 的坐标对使用 core `Pair<Double, Double>`：`first` 为 x/经度，`second` 为 y/纬度。
- `Wgs84` 是恒等投影，输出度；`WebMercator` 输出米制 `(x, y)`，使用 EPSG:3857 球面半径 `6378137.0`。
- `Utm` 在基线中返回 `Unsupported`；带号/半球参数是 X。
- 无 I/O、无 `Context`、无取消点；失败只来自投影不支持或反投影坐标越界。
- 中点对反极点对没有唯一解，返回 `InvalidArgument`；重合点返回同坐标点。

---

## 3. 表示与不变量

无实例字段。

不变量：静态方法不读写全局状态；距离/方位/终点/中点不修改参数；投影返回新 `Pair`；反投影返回新 `GeoPoint`。

---

## 4. 生命周期

静态类；无实例；无 close；无全局初始化/关闭。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Geo()` | 无 | 私有；禁止实例化 | 无 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `distanceMeters` | Haversine 距离 | `GeoPoint first, GeoPoint second` | `Double` | null → panic |
| `bearingDegrees` | 初始方位 | `GeoPoint first, GeoPoint second` | `Double` | null → panic |
| `destination` | 按方位/距离求终点 | `GeoPoint origin, Double initialBearingDegrees, Double travelDistanceMeters` | `GeoPoint` | null/非有限/负距离 → panic |
| `midpoint` | 大圆中点 | `GeoPoint first, GeoPoint second` | `Result<GeoPoint, Error>` | null → panic；反极点对 → `InvalidArgument` |
| `normalizeLongitude` | 经度归一 | `Double longitude` | `Double` | null/非有限 → panic |
| `project` | 投影到坐标对 | `GeoPoint point, GeoProjection projection` | `Result<Pair<Double, Double>, Error>` | null → panic；`Utm` → `Unsupported` |
| `unproject` | 坐标对还原 | `Pair<Double, Double> projectedCoordinate, GeoProjection projection` | `Result<GeoPoint, Error>` | null → panic；越界/非有限 → `InvalidArgument`；`Utm` → `Unsupported` |

说明：

- `distanceMeters` 返回米；对相同点返回 0；对反极点对返回半个大圆；经度差先归一到最短方向。
- `bearingDegrees` 返回初始方位 `[0, 360)`；相同点返回 0；反极点对方位不唯一，结果由 `atan2` 决定。
- `destination` 的 `travelDistanceMeters >= 0`；方位可为任意有限值；结果经度归一到 `[-180, 180)`。
- `midpoint` 使用最短大圆；反极点对（分母趋近 0）返回 `InvalidArgument`；重合点返回同坐标点。
- `normalizeLongitude` 返回 `[-180, 180)`；`180` 映射为 `-180`；`-180` 保持 `-180`。
- `project`：`Wgs84` 返回 `(longitude, latitude)` 度；`WebMercator` 返回米制 `(x, y)`，纬度先钳制到 `±85.05112878`；`Utm` 返回 `Unsupported`。
- `unproject`：`Wgs84` 的 `(x, y)` 按 `(longitude, latitude)` 解释；`WebMercator` 的米制坐标超出 `±20037508.342789244` 返回 `InvalidArgument`；`Utm` 返回 `Unsupported`。
- 不提供批量距离、最近点、线段距离、面积；这些由调用方组合或 X。

---

## 8. 使用的技术

- Haversine 球面距离；
- 初始方位/大圆公式；
- 球面中点；
- 经度回绕；
- Web Mercator 正/反投影；
- 静态无状态类。

---

## 9. 需要的支撑

- 语言：class、static、Double、Bool、String、Pair、Result；
- 数学：`sin`、`cos`、`tan`、`asin`、`atan`、`atan2`、`sqrt`、`log`、`exp`、`floor`、`deg2rad`、`rad2deg`、`abs`、`isFinite`、`PI`；
- 错误：`BasicError`、`ErrorKind`、`Error`；
- 接口：`GeoPoint`、`GeoProjection`。

---

## 10. 依赖的特性/接口/类

`GeoPoint`、`GeoBounds`、`GeoPath`、`GeoPolygon`、`GeoProjection`、`Pair`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

静态无状态；可并发调用；无资源；无取消点。
返回值为新对象/新 `Pair`/新 `GeoPoint`；参数只读；不缓存结果。
相等：无实例；不适用。

---

## 12. 示例与反例

正确：

```xnull
GeoPoint berlin = new GeoPoint(52.5200, 13.4050)
GeoPoint paris = new GeoPoint(48.8566, 2.3522)
Double distance = Geo.distanceMeters(berlin, paris)
Double bearing = Geo.bearingDegrees(berlin, paris)
GeoPoint destination = Geo.destination(berlin, 90.0, 1000.0)
Result<GeoPoint, Error> middle = Geo.midpoint(berlin, paris)
Result<Pair<Double, Double>, Error> projected =
    Geo.project(berlin, GeoProjection.WebMercator)
```

反例：用 `project` 的米制 `(x, y)` 直接调用 `Geo.distanceMeters`；把 `Utm` 当已支持；忽略 `midpoint` 的 `Result`；用 `normalizeLongitude` 代替边界校验；把 Haversine 结果当测绘级精度；用 `Double` 精确相等判断距离是否为零。

---

## 13. 测试/场景义务

相同点/近距离/远距离/跨 180° 经线；南北半球；反极点对；方位 `[0,360)`；目的地往返；中点重合/普通/反极点；经度 `180`/`-180`/`540`/`-540`；WebMercator 已知点/往返/极区钳制/经度 180 往返归一到 -180；`unproject` 越界；`Utm` 返回 `Unsupported`；null/非有限参数 panic；与 `GeoBounds`/`GeoPath`/`GeoPolygon` 组合。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
class Geo {
    private Geo() {}

    static Double distanceMeters(GeoPoint first, GeoPoint second) {
        if first == null || second == null {
            throw "Geo.distanceMeters: null point"
        }
        Double firstLatitude = deg2rad(first.latitude())
        Double secondLatitude = deg2rad(second.latitude())
        Double latitudeDelta = secondLatitude - firstLatitude
        Double longitudeDelta = deg2rad(
            Geo.normalizeLongitude(second.longitude() - first.longitude()))
        Double latitudeSine = sin(latitudeDelta / 2.0)
        Double longitudeSine = sin(longitudeDelta / 2.0)
        Double haversine = latitudeSine * latitudeSine
            + cos(firstLatitude) * cos(secondLatitude)
            * longitudeSine * longitudeSine
        if haversine < 0.0 { haversine = 0.0 }
        if haversine > 1.0 { haversine = 1.0 }
        Double centralAngle = 2.0 * atan2(sqrt(haversine),
            sqrt(1.0 - haversine))
        return 6371008.8 * centralAngle
    }

    static Double bearingDegrees(GeoPoint first, GeoPoint second) {
        if first == null || second == null {
            throw "Geo.bearingDegrees: null point"
        }
        Double firstLatitude = deg2rad(first.latitude())
        Double secondLatitude = deg2rad(second.latitude())
        Double longitudeDelta = deg2rad(
            Geo.normalizeLongitude(second.longitude() - first.longitude()))
        Double y = sin(longitudeDelta) * cos(secondLatitude)
        Double x = cos(firstLatitude) * sin(secondLatitude)
            - sin(firstLatitude) * cos(secondLatitude) * cos(longitudeDelta)
        Double bearing = rad2deg(atan2(y, x))
        bearing = bearing - 360.0 * floor(bearing / 360.0)
        return bearing
    }

    static GeoPoint destination(GeoPoint origin, Double initialBearingDegrees,
                                Double travelDistanceMeters) {
        if origin == null || initialBearingDegrees == null
            || travelDistanceMeters == null {
            throw "Geo.destination: null argument"
        }
        if !isFinite(initialBearingDegrees) || !isFinite(travelDistanceMeters) {
            throw "Geo.destination: non-finite argument"
        }
        if travelDistanceMeters < 0.0 {
            throw "Geo.destination: negative distance"
        }
        Double originLatitude = deg2rad(origin.latitude())
        Double originLongitude = deg2rad(origin.longitude())
        Double bearing = deg2rad(initialBearingDegrees)
        Double angularDistance = travelDistanceMeters / 6371008.8
        Double destinationLatitudeSine =
            sin(originLatitude) * cos(angularDistance)
            + cos(originLatitude) * sin(angularDistance) * cos(bearing)
        if destinationLatitudeSine > 1.0 { destinationLatitudeSine = 1.0 }
        if destinationLatitudeSine < -1.0 { destinationLatitudeSine = -1.0 }
        Double destinationLatitude = asin(destinationLatitudeSine)
        Double destinationLongitude = originLongitude + atan2(
            sin(bearing) * sin(angularDistance) * cos(originLatitude),
            cos(angularDistance)
            - sin(originLatitude) * sin(destinationLatitude))
        return new GeoPoint(rad2deg(destinationLatitude),
            Geo.normalizeLongitude(rad2deg(destinationLongitude)))
    }

    static Result<GeoPoint, Error> midpoint(GeoPoint first, GeoPoint second) {
        if first == null || second == null {
            throw "Geo.midpoint: null point"
        }
        if first.equals(second) {
            return Ok(new GeoPoint(first.latitude(), first.longitude()))
        }
        Double firstLatitude = deg2rad(first.latitude())
        Double firstLongitude = deg2rad(first.longitude())
        Double secondLatitude = deg2rad(second.latitude())
        Double longitudeDelta = deg2rad(
            Geo.normalizeLongitude(second.longitude() - first.longitude()))
        Double bx = cos(secondLatitude) * cos(longitudeDelta)
        Double by = cos(secondLatitude) * sin(longitudeDelta)
        Double denominatorX = cos(firstLatitude) + bx
        Double denominator = sqrt(denominatorX * denominatorX + by * by)
        if denominator < 0.000000000001 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "antipodal midpoint"))
        }
        Double middleLatitude = atan2(
            sin(firstLatitude) + sin(secondLatitude), denominator)
        Double middleLongitude = firstLongitude + atan2(by, denominatorX)
        return Ok(new GeoPoint(rad2deg(middleLatitude),
            Geo.normalizeLongitude(rad2deg(middleLongitude))))
    }

    static Double normalizeLongitude(Double longitude) {
        if longitude == null {
            throw "Geo.normalizeLongitude: null longitude"
        }
        if !isFinite(longitude) {
            throw "Geo.normalizeLongitude: non-finite longitude"
        }
        Double normalized = longitude
            - 360.0 * floor((longitude + 180.0) / 360.0)
        return normalized
    }

    static Result<Pair<Double, Double>, Error> project(
            GeoPoint point, GeoProjection projection) {
        if point == null || projection == null {
            throw "Geo.project: null argument"
        }
        if projection == GeoProjection.Wgs84 {
            return Ok(new Pair<Double, Double>(
                point.longitude(), point.latitude()))
        }
        if projection == GeoProjection.WebMercator {
            Double latitude = point.latitude()
            if latitude > 85.05112878 { latitude = 85.05112878 }
            if latitude < -85.05112878 { latitude = -85.05112878 }
            Double projectedX = point.longitude()
                * 20037508.342789244 / 180.0
            Double projectedY = 6378137.0 * log(
                tan(PI / 4.0 + deg2rad(latitude) / 2.0))
            return Ok(new Pair<Double, Double>(projectedX, projectedY))
        }
        return Err(new BasicError(ErrorKind.Unsupported,
            "utm projection is not supported"))
    }

    static Result<GeoPoint, Error> unproject(
            Pair<Double, Double> projectedCoordinate,
            GeoProjection projection) {
        if projectedCoordinate == null || projection == null {
            throw "Geo.unproject: null argument"
        }
        Double projectedX = projectedCoordinate.first()
        Double projectedY = projectedCoordinate.second()
        if projectedX == null || projectedY == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "null projected coordinate"))
        }
        if !isFinite(projectedX) || !isFinite(projectedY) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "non-finite projected coordinate"))
        }
        if projection == GeoProjection.Wgs84 {
            if projectedX < -180.0 || projectedX > 180.0 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "longitude out of range"))
            }
            if projectedY < -90.0 || projectedY > 90.0 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "latitude out of range"))
            }
            return Ok(new GeoPoint(projectedY, projectedX))
        }
        if projection == GeoProjection.WebMercator {
            if projectedX < -20037508.342789244
                || projectedX > 20037508.342789244 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "web mercator x out of range"))
            }
            if projectedY < -20037508.342789244
                || projectedY > 20037508.342789244 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "web mercator y out of range"))
            }
            Double longitude = projectedX / 6378137.0 * 180.0 / PI
            Double latitude = rad2deg(2.0 * atan(exp(
                projectedY / 6378137.0)) - PI / 2.0)
            return Ok(new GeoPoint(latitude,
                Geo.normalizeLongitude(longitude)))
        }
        return Err(new BasicError(ErrorKind.Unsupported,
            "utm projection is not supported"))
    }
}
```
