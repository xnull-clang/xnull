# `xdk.stats` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.stats` |
| 层 | L4 数据/编码（文档分组 `utils/`） |
| 依赖 | `xdk.math`、`xdk.collections` |
| 被依赖 | `xdk.metrics`、应用 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

有状态统计对象：流式摘要、固定内存统计、直方图、线性回归、移动平均、指数移动平均。

标量统计函数（sum/mean/median/variance/quantile/covariance/correlation）已在 `xdk.math`；本包不重复。

不做：绘图、数据框、分布式聚合、近似分位草图（X）、持久化。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 不重复 xdk.math | 无状态函数用 `xdk.math`；本包只提供有状态对象 |
| 显式精度 | 精确分位存储原始值；固定内存用 `RunningStats` |
| 失败明确 | 非法参数/空数据按契约 panic 或返回 NaN |
| 无全局 | 无全局直方图/指标注册表 |
| 不隐藏内存 | `Summary` 存储值；`RunningStats` 常数内存 |
| 可复用 | `Histogram`/`Summary` 可被 `xdk.metrics` 组合 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `HistogramBucket` | class | 桶边界/计数 | [`HistogramBucket.md`](HistogramBucket.md) |
| `Histogram` | class | 桶计数/分位近似 | [`Histogram.md`](Histogram.md) |
| `Summary` | class | 精确分位/矩统计 | [`Summary.md`](Summary.md) |
| `RunningStats` | class | 常数内存均值/方差 | [`RunningStats.md`](RunningStats.md) |
| `Regression` | class | 最小二乘回归 | [`Regression.md`](Regression.md) |
| `MovingAverage` | class | 固定窗口平均 | [`MovingAverage.md`](MovingAverage.md) |
| `Ema` | class | 指数移动平均 | [`Ema.md`](Ema.md) |

X：t-digest/ reservoir 近似分位、加权统计、分布式合并、时间窗口滑窗。

---

## 4. 顶层函数

无；标量函数复用 `xdk.math`。

---

## 5. 技术/支撑/依赖

- 技术：Welford 在线方差、桶计数、最小二乘、环形窗口、EMA。
- 支撑：`xdk.math` 的 `sqrt`/`abs`/`min`/`max`、`xdk.collections.sortedBy`。
- 依赖：`math`、`collections`。

---

## 6. 场景

### S1：接口延迟

`Histogram` 记录毫秒延迟；`percentile(95)` 近似 P95。

### S2：流式摘要

`Summary.observe` 记录值；`quantile(0.99)` 精确分位；内存随样本增长。

### S3：固定内存监控

`RunningStats` 只保留 count/mean/m2/min/max；适合长期指标。

### S4：趋势

`MovingAverage(window)` 平滑短期波动；`Ema(alpha)` 对近期值加权。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 标量函数 | 复用 `xdk.math`，不新增 `Stats` 类 |
| 精确分位 | `Summary` 存储原始值 |
| 固定内存分位 | X |
| 线程安全 | 默认非线程安全；跨任务共享需外部同步 |
| 直方图边界 | 必须严格递增；空边界表示单一无界桶 |
| 空数据 | 均值/方差/分位返回 NaN；min/max 返回 NaN |
