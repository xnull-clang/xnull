# `MetricKind`

| 项 | 值 |
| --- | --- |
| 类型 | `enum MetricKind` |
| 包 | `xdk.metrics` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

指标语义分类：Counter、Gauge、Histogram、Timer。

不做：指标值、标签、导出格式、注册表键、配置项。

---

## 2. 设计逻辑

- `Counter`：单调累计值，只增不减，`reset` 是唯一归零入口。
- `Gauge`：瞬时值，可增可减、可正可负。
- `Histogram`：按固定边界统计分布，快照包含桶、总和、计数。
- `Timer`：按单调时钟统计时长，快照包含计数、总和、最大值。
- 枚举只表达语义；具体行为由对应类型实现。
- 序号不稳定，不写入持久化数据；跨进程只使用小写名称。
- 值语义；无 close；可作 `Map` 键。

---

## 3. 表示与不变量

| 成员 | 语义 | 典型导出 |
| --- | --- | --- |
| `Counter` | 单调累计 | `counter` |
| `Gauge` | 瞬时值 | `gauge` |
| `Histogram` | 桶分布 | `histogram` |
| `Timer` | 时长分布 | `summary` |

不变量：成员固定；不存在 `Summary`/`Meter`/`Rate` 等隐式成员；分类与 `MetricFamily.kind` 一致。

---

## 4. 生命周期

值类型；无 close；无资源；可跨任务共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| 枚举成员 | 无 | 固定四项 | 无 |

说明：

- 直接使用成员，不提供整数转换。
- 不提供 `parse`；配置/协议层必须显式映射，未知文本视为配置错误。
- 不从序号恢复语义，避免版本间序号变化导致误读。

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

无实例方法。

包级函数：

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `metricKindName` | 稳定小写名 | `MetricKind kind` | `String` | 无 |

说明：

- `metricKindName` 只用于诊断/导出前缀；不承担解析。
- 名称固定为 `counter`、`gauge`、`histogram`、`timer`。

---

## 8. 使用的技术

- 简单枚举；
- 稳定名称映射；
- 导出时按 kind 分派。

---

## 9. 需要的支撑

- 语言：enum、String、switch/if；
- 运行时：无；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

值语义；不可变；可共享；可并发比较；无资源。

---

## 12. 示例与反例

正确：`metric.kind() == MetricKind.Counter`。  
反例：把 Histogram 当 Gauge 合并；持久化枚举序号；用字符串代替枚举传参；假设存在 `MetricKind.Summary`。

---

## 13. 测试/场景义务

四个成员；`metricKindName` 映射；switch 覆盖全部成员；作为 `Map` 键；跨模块比较；未知文本拒绝。

---

## 14. XNull 伪代码

```xnull
enum MetricKind {
    Counter,
    Gauge,
    Histogram,
    Timer,
}

String metricKindName(MetricKind kind) {
    if kind == MetricKind.Counter { return "counter" }
    if kind == MetricKind.Gauge { return "gauge" }
    if kind == MetricKind.Histogram { return "histogram" }
    return "timer"
}
```
