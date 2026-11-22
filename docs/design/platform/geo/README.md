# `xdk.geo` 坐标/边界/路径/多边形/投影

| 项 | 值 |
| --- | --- |
| 包 | `xdk.geo` |
| 层 |  |
| 依赖 | `xdk.core`（math/collections） |
| 能力 | 坐标、边界、路径、多边形、距离、投影 |
| 稳定性 | `preview` |

---

## 1. 定位

纯地理几何值类型与静态运算：WGS84 经纬度点、矩形边界、折线路径、简单多边形、球面距离/方位/终点/中点、Web Mercator 投影。

不做：

- 地图瓦片、地理编码、逆地理编码、路径规划/导航；
- 坐标系注册表、基准转换、椭球测地线、UTM 实现；
- 空间索引、多边形布尔运算、洞/多面；
- 文件/网络 I/O、平台探测、地图数据加载。

上述能力归 ecosystem 或 X。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 值语义 | `GeoPoint`/`GeoBounds`/`GeoPath`/`GeoPolygon` 不可变；无 close |
| 纯计算 | 不访问文件/网络/平台；无 `Context` |
| 显式失败 | 构造非法值 → panic；投影不支持/坐标越界 → `Result` |
| 单一基准 | 距离/方位/终点/中点默认 WGS84 球面；不是椭球 |
| 投影分层 | Web Mercator 为基线；UTM 只保留枚举成员，调用返回 `Unsupported` |
| 边界明确 | 基线矩形/多边形不支持跨 180° 经线；跨经线由调用方拆分 |
| 不重复 | 不复制 core 的 `Pair`/`Bytes`/`List` 等类型 |

---

## 3. 类型索引

| 类型 | 种类 | 文件 |
| --- | --- | --- |
| `GeoPoint` | class | [`GeoPoint.md`](GeoPoint.md) |
| `GeoBounds` | class | [`GeoBounds.md`](GeoBounds.md) |
| `GeoPath` | class | [`GeoPath.md`](GeoPath.md) |
| `GeoPolygon` | class | [`GeoPolygon.md`](GeoPolygon.md) |
| `GeoProjection` | enum | [`GeoProjection.md`](GeoProjection.md) |
| `Geo` | class（静态入口） | [`Geo.md`](Geo.md) |

---

## 4. 跨类型规则

- `GeoPoint` 纬度 `-90..90`、经度 `-180..180`；非法构造 → panic。
- `GeoBounds` 要求 `south <= north`、`west <= east`；不支持跨 180° 经线。
- `GeoPath` 至少 2 个点；`length()` 用 WGS84 球面逐段求和；`isClosed()` 仅表示首点与末点相等。
- `GeoPolygon` 外环至少 3 个顶点；支持隐式闭合与显式闭合；基线不支持洞。
- 多边形命中采用经纬度平面射线法；边界点视为包含；自交环不在契约内。
- `GeoProjection.Wgs84` 是恒等投影；`WebMercator` 输出米制 `(x, y)`；`Utm` 保留但基线返回 `Unsupported`。
- `GeoProjection` 名称兜底：null → `"unknown"`，未知未来成员 → `"other"`；`"unknown"`/`"other"` 不是成员，`geoProjectionFromName` 对 null/未知名称返回 null。
- `Geo.project`/`unproject` 使用 `Pair<Double, Double>` 承载坐标对：`first` 为 x/经度，`second` 为 y/纬度；单位由投影决定。
- 距离/方位/终点/中点使用球面近似；不与 `WebMercator` 的米制坐标混用。
- 所有列表参数复制；所有返回值不暴露内部可变状态。

---

## 5. 场景

### G1：距离与方位

两点间 Haversine 距离、初始方位；用于地理围栏提示、日志、粗略排序。不用于测绘级精度。

### G2：目的地与中点

按方位/距离计算终点；按最短大圆计算中点。反极点对没有唯一中点，`Geo.midpoint` 返回 `InvalidArgument`。

### G3：边界过滤

矩形 `GeoBounds` 做快速包含检查；跨 180° 经线的区域拆成两个边界。

### G4：折线长度

`GeoPath.length()` 逐段求和；轨迹/航线概览；不提供抽稀、平滑、路网匹配。

### G5：多边形命中

`GeoPolygon.contains(point)` 用于简单围栏/区域命中；不做洞、布尔运算、自交修复。

### G6：Web Mercator 投影

`Geo.project(point, GeoProjection.WebMercator)` 得到米制 `(x, y)`；`unproject` 还原。用于显示/瓦片坐标计算的前置步骤，不提供瓦片服务。

---

## 6. 缺口

| 项 | 决策 |
| --- | --- |
| 洞/多面 | X |
| 跨 180° 经线的边界/多边形 | X；基线由调用方拆分 |
| UTM 投影/带号/半球 | X |
| 基准转换/椭球测地线 | X/ecosystem |
| GeoJSON/WKT | ecosystem |
| 地图瓦片/地理编码/路径规划 | ecosystem |
| 空间索引/R 树 | X |
| 多边形布尔/自交修复 | X |
| 距离单位换算 | 由调用方换算；本包只返回米 |

---

## 7. 验收谓词

- 6 个类型文件与索引一一对应；
- 每个类型 14 段；
- 所有相对链接可达；
- `check_doc_naming.py` PASS；
- 无地图瓦片/地理编码/路由 API；
- 无平台/驱动/裸设备类型；
- 距离/投影的单位与基准在文档中明确。

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | 无领域注解 |
| 本包消费 | `@Value`、`@Builder`、`@Copy` |
| 处理器 | 标准 A8 |
| 生成物 | GeoPoint/GeoBounds 用合法 struct；Path/Polygon 含列表，用 class + `@Value` |
| 状态 | 无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `GeoPoint`/`GeoBounds` | `struct` | 原生值语义；无需 `@Value` |
| `GeoPath`/`GeoPolygon` | `@Value`/`@Builder` | 值语义/构造 |

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
