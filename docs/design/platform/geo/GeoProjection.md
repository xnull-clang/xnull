# `GeoProjection`

| 项 | 值 |
| --- | --- |
| 类型 | `enum GeoProjection` |
| 包 | `xdk.geo` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

地理坐标/投影家族：WGS84 经纬度、Web Mercator、UTM。

不做：基准转换、带号/半球参数、投影参数注册、瓦片编号、地图数据；不把 null 或未知名称猜成合法成员。

---

## 2. 设计逻辑

- 封闭枚举：只列基线能命名的投影家族；应用不能扩展。
- `Wgs84` 表示经纬度恒等坐标，不是米制投影。
- `WebMercator` 是基线可用的球面墨卡托投影；`Geo.project`/`unproject` 支持。
- `Utm` 保留成员，表示未来支持；基线调用 `Geo.project`/`unproject` 返回 `Unsupported`。
- 枚举不携带带号、半球、中央经线等参数；这些是 X 的 UTM 扩展。
- 值语义；成员只允许追加，不允许改义/删除。
- 名称函数有冻结兜底：null → `"unknown"`，未知未来成员 → `"other"`；不 panic，不映射到合法成员。
- `geoProjectionFromName` 是查找函数：null/未知/空 → `null`（未找到）；`"unknown"`/`"other"` 不是成员，不得解析成合法成员。

---

## 3. 表示与不变量

| 成员 | 含义 | `Geo.project` 基线行为 |
| --- | --- | --- |
| `Wgs84` | WGS84 经纬度（度） | 恒等：返回 `(longitude, latitude)` |
| `WebMercator` | 球面 Web Mercator | 返回米制 `(x, y)` |
| `Utm` | UTM 家族 | `Unsupported`（X） |

不变量：成员固定；只允许追加；值语义；`Utm` 不是“自动选择带号”的投影；任何成员都不表示具体基准转换；`"unknown"`/`"other"` 不是成员。

---

## 4. 生命周期

值类型；无构造器、无 close；可共享。

---

## 5. 构造契约

枚举项直接使用，无构造器。名称解析失败返回 null，不抛错。

兜底策略（冻结）：

- `geoProjectionName(null)` → `"unknown"`；未知未来成员 → `"other"`；`"unknown"`/`"other"` 都不是枚举成员。
- `geoProjectionFromName(null)` / 未知 / 空串 → `null`（未找到）；`"unknown"`/`"other"` 不得解析成成员。
- 兜底不 panic，不把 null 映射成 `Utm` 或其他合法成员；闭枚举仍只有 3 个成员。

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `geoProjectionName` | 稳定小写名 | `GeoProjection projection` | `String` | 无；null → `"unknown"`；未知成员 → `"other"` |
| `geoProjectionFromName` | 名称解析 | `String name` | `GeoProjection?` | 无；null/未知 → null（未找到） |

说明：

- 稳定名用于日志/配置/诊断，不是 EPSG 编号。
- 解析只接受稳定名，做 `trim().toLower()` 归一；不做模糊匹配。
- `geoProjectionName` 的 `"unknown"`/`"other"` 是诊断兜底文本，不是成员；`geoProjectionFromName` 不接受它们。
- `geoProjectionFromName` 的 null 表示“未找到”，调用方决定默认值或报错；不得把 null/未知名称猜成任一合法成员。
- 不提供 `isSupported`；支持矩阵由 `Geo.project`/`unproject` 的返回通道表达。

---

## 8. 使用的技术

- 简单枚举；
- 名称映射；
- 值语义比较。

---

## 9. 需要的支撑

- 语言：enum、String；
- 运行时：`trim()`、`toLower()`；
- 接口：`Geo`、`GeoPoint`。

---

## 10. 依赖的特性/接口/类

`Geo`、`GeoPoint`、`GeoBounds`。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。
相等：按枚举底层值比较；可作 `Map`/`Set` 键。

---

## 12. 示例与反例

正确：

```xnull
GeoProjection projection = GeoProjection.WebMercator
Result<Pair<Double, Double>, Error> projected = Geo.project(
    new GeoPoint(52.5200, 13.4050), projection)
```

正确：`geoProjectionName(null) == "unknown"`；未知未来成员 → `"other"`；`geoProjectionFromName("unknown") == null`。

反例：把 `Wgs84` 当米制投影；把 `Utm` 当“自动带号”；用投影枚举推断 EPSG 编号；用 `WebMercator` 坐标直接计算球面距离；把 `geoProjectionName(null)` 返回 `"utm"`；把未知名称猜成 `WebMercator`/`Utm`；把 `"unknown"`/`"other"` 当成员；对 null/未知成员 panic（本合同选择不 panic）。

---

## 13. 测试/场景义务

每个成员稳定名/解析；大小写/空白归一；`geoProjectionName` 的 null → `"unknown"`、未知未来成员 → `"other"`；`geoProjectionFromName` 的 null/未知名称 → `null`；`"unknown"`/`"other"` 不解析成成员；`Wgs84` 恒等；`WebMercator` 往返；`Utm` 返回 `Unsupported`；与 `Geo.project`/`unproject` 组合；跨平台无差异。闭枚举当前无法直接构造未来成员；追加成员时先补“旧分派返回 `other`”的前向测试，再更新分派表。

---

## 14. XNull 伪代码

以下为 XNull 形态伪代码，非可执行。

```xnull
enum GeoProjection {
    Wgs84,
    WebMercator,
    Utm,
}

String geoProjectionName(GeoProjection projection) {
    if projection == null { return "unknown" }
    if projection == GeoProjection.Wgs84 { return "wgs84" }
    if projection == GeoProjection.WebMercator { return "web_mercator" }
    if projection == GeoProjection.Utm { return "utm" }
    return "other"
}

GeoProjection? geoProjectionFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "wgs84" { return GeoProjection.Wgs84 }
    if normalized == "web_mercator" { return GeoProjection.WebMercator }
    if normalized == "utm" { return GeoProjection.Utm }
    return null
}
```
