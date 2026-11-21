# `Metric`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol Metric` |
| 包 | `xdk.metrics` |
| 稳定性 | `preview` |
| 依赖 | `MetricKind`、`MetricFamily`、`MetricSample` |

---

## 1. 定位

所有指标类型的非泛型公共合同：名称、语义、help、unit、标签、快照、重置。

不做：注册、导出、聚合、标签派生、持久化、线程调度。

---

## 2. 设计逻辑

- XNull 禁止泛型协议；`Metric` 不带类型参数，具体指标自行提供强类型方法。
- `name`/`kind`/`help`/`unit` 在生命周期内稳定；注册表按这些字段判定冲突。
- `labels` 是构造时固定的标签集；读取返回副本。
- `snapshot` 返回该序列的不可变 `MetricFamily`；不得修改指标状态。
- `reset` 只清空数值，不改变名称/标签/元数据，也不从注册表移除。
- 所有实现必须线程安全；注册表可能跨任务共享指标引用。
- 无 close；指标无外部资源。

---

## 3. 表示与不变量

协议无字段。实现保证：

- `name()` 非空且符合指标名规则；
- `kind()` 与实现类型一致；
- `help()`/`unit()` 非 null；
- `labels()` 返回私有快照，键非空、值非 null；
- `snapshot()` 的 family 元数据与访问器一致，样本名符合 kind 约定；
- `reset()` 后 `snapshot()` 仍返回合法 family（计数值为 0 或空统计的 NaN）；
- 并发读写不产生撕裂值。

---

## 4. 生命周期

- 由具体实现构造；通常在注册表中长期存活。
- `reset` 可重复调用；无 close；无资源释放。
- 从注册表移除不会使已持有引用失效；调用方仍可读取/重置。

---

## 5. 构造契约

协议无构造；由 `Counter`、`Gauge`、`Histogram`、`Timer` 定义。

---

## 6. 字段表

无协议字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 指标名 | 无 | `String` | 无 |
| `kind` | 语义分类 | 无 | `MetricKind` | 无 |
| `help` | 说明 | 无 | `String` | 无 |
| `unit` | 单位 | 无 | `String` | 无 |
| `labels` | 标签快照 | 无 | `Map<String,String>` | 无 |
| `snapshot` | 族快照 | 无 | `MetricFamily` | 无 |
| `reset` | 清空数值 | 无 | `void` | 无 |

说明：

- `snapshot` 不返回 `Result`：实现必须保证快照可构造；内部错误属于实现缺陷。
- `reset` 不返回 `Result`：重置是无失败操作。
- `labels` 的返回顺序不承诺；导出器需自行排序。
- 具体实现可增加强类型方法（`inc`/`set`/`observe` 等），但不得改变本协议语义。

---

## 8. 使用的技术

- 非泛型协议；
- 快照模式；
- 元数据稳定性；
- 标签防御性复制；
- 实现级线程安全。

---

## 9. 需要的支撑

- 语言：protocol、class、String、Map、void；
- 运行时：实现决定（`RuntimeMonitor`、`nowMono`）；
- 接口：`MetricKind`、`MetricFamily`、`MetricSample`。

---

## 10. 依赖的特性/接口/类

`MetricKind`、`MetricFamily`、`MetricSample`。

---

## 11. 所有权与并发

- 引用语义；调用方只持有接口引用。
- 实现必须线程安全；可跨任务共享。
- `snapshot` 读取一致状态；`reset` 与读写并发安全。
- 注册表不拥有指标的业务生命周期；移除不等于销毁。

---

## 12. 示例与反例

正确：导出器接收 `List<Metric>`，逐个 `snapshot()` 后编码。  
反例：给 `Metric` 加泛型参数；假设 `snapshot` 可失败；用 `reset` 注销指标；修改 `labels()` 返回值期望影响指标；让 `Metric` 依赖 `log`。

---

## 13. 测试/场景义务

每个实现验证：元数据稳定；`labels` 副本；`snapshot` 元数据一致；`reset` 后合法；并发更新/快照；从注册表移除后仍可用；接口分派；空统计快照。

---

## 14. XNull 伪代码

```xnull
protocol Metric {
    String name();
    MetricKind kind();
    String help();
    String unit();
    Map<String, String> labels();
    MetricFamily snapshot();
    void reset();
}
```
