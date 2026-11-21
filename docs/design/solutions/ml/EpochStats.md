# `EpochStats`

| 项 | 值 |
| --- | --- |
| 类型 | `class EpochStats` |
| 包 | `xdk.ml` |
| 稳定性 | `preview` |
| 依赖 | `Map`、`Double`、`Long`、`Int` |

---

## 1. 定位

一个训练/评估 epoch 的不可变统计快照：epoch 序号、训练/评估标志、批次数、样本数、平均损失、附加指标和耗时。

只做统计承载；不做指标聚合、日志导出、早停、学习率调度或模型选择。

不做：混淆矩阵、PR 曲线、逐类指标、梯度范数、显存统计、分布式归约、持久化。

---

## 2. 设计逻辑

- 用 `class`：需要复制指标映射、校验空 epoch/非空 epoch 的字段一致性。
- `_training` 区分 train/evaluate；同一类型不在两个语义间复用不同字段。
- `_sampleCount == 0` 时 `_meanLoss` 必须为 `null`，`_batchCount == 0`；非空 epoch 时 `_meanLoss` 必须有限且 `_batchCount > 0`。不用 `0.0` 表示“没有样本”。
- 指标映射是 `Map<String,Double>` 快照；键非空，值有限；不承诺顺序。
- `batchCount`/`sampleCount` 用 `Long`：由数据集大小派生，避免大 epoch 溢出；`epochIndex` 用 `Int`。
- 耗时用 `Long` 毫秒；非负。
- 不可变；可跨任务共享；无 close。
- 不提供 `equals`；指标映射比较成本低但无稳定哈希合同。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_epochIndex` | `Int` | final | ≥0 |
| `_training` | `Bool` | final | true = 训练；false = 评估 |
| `_batchCount` | `Long` | final | ≥0 |
| `_sampleCount` | `Long` | final | ≥0 |
| `_meanLoss` | `Double?` | final | sampleCount 0 → null；否则有限 |
| `_metrics` | `Map<String,Double>` | final | 私有快照；键非空；值有限 |
| `_elapsedMillis` | `Long` | final | ≥0 |

不变量：epochIndex/耗时非负；批次/样本数非负；空 epoch ⇒ batchCount 0 且 meanLoss null；非空 epoch ⇒ batchCount >0 且 meanLoss 有限；指标键非空、值有限；构造后不可变；映射返回副本。

---

## 4. 生命周期

构造后不可变；无 close；无资源；可跨任务共享；GC 管理内存。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `EpochStats(Int epochIndex, Bool training, Long batchCount, Long sampleCount, Double? meanLoss, Map<String,Double> metrics, Long elapsedMillis)` | 序号、训练标志、批次数、样本数、平均损失、指标、耗时 | epochIndex ≥0；batchCount/sampleCount/elapsedMillis ≥0；空/非空一致性；meanLoss 合法；指标键非空、值有限 | 违约 → panic |

构造器复制指标映射；调用方之后修改原映射不影响统计。

---

## 6. 字段表

见 §3；字段私有。不暴露训练器内部状态、参数、梯度或设备信息。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `epochIndex` | epoch 序号 | 无 | `Int` | 无 | ≥0 |
| `isTraining` | 是否训练 epoch | 无 | `Bool` | 无 | 区分 evaluate |
| `batchCount` | 批次数 | 无 | `Long` | 无 | 空 epoch 为 0 |
| `sampleCount` | 样本数 | 无 | `Long` | 无 | 空 epoch 为 0 |
| `meanLoss` | 平均损失 | 无 | `Double?` | 无 | 空 epoch 为 null |
| `metrics` | 指标副本 | 无 | `Map<String,Double>` | 无 | 值有限 |
| `metric` | 按名取指标 | `String name` | `Double?` | null name → panic | 缺失 → null |
| `elapsedMillis` | 耗时 | 无 | `Long` | 无 | ≥0 |
| `describe` | 单行描述 | 无 | `String` | 无 | 不含指标全集 |

说明：

- `metric` 精确匹配名称；空串返回 `null`；不做大小写折叠。
- `meanLoss` 与 `sampleCount` 的一致性由构造器保证；调用方不需要再判空。
- `describe` 输出 epoch/训练标志/样本数/平均损失/耗时；不输出全部指标，避免噪声。
- 不提供 `withMetric`；统计在 epoch 结束后一次构造。
- 不提供 `equals`；`==` 是引用身份；需要比较时逐字段/逐指标比较。

---

## 8. 使用的技术

- 不可变统计快照；
- 映射复制；
- 空/非空 epoch 一致性校验；
- `Long` 批次/样本计数；
- 有限数值校验；
- 稳定单行描述。

---

## 9. 需要的支撑

- 语言：class、final 字段、Int、Long、Double、Bool、String、Map；
- 数学：`isFinite`；
- 接口：[`Trainer`](Trainer.md)、[`DataLoader`](DataLoader.md)、[`Optimizer`](Optimizer.md)、[`LossKind`](LossKind.md)。

---

## 10. 依赖的特性/接口/类

[`Trainer`](Trainer.md)、[`DataLoader`](DataLoader.md)、[`Optimizer`](Optimizer.md)、[`LossKind`](LossKind.md)。

不依赖日志、指标导出器或持久化格式。

---

## 11. 所有权与并发

不可变；可共享；`metrics()` 返回副本；无资源；无取消点。  
相等：没有 `equals`；`==` 是引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：训练 epoch 用 `new EpochStats(1, true, 100, 3200, 0.42, ["accuracy":0.91], 1200)`；空评估集用 `batchCount=0`、`sampleCount=0`、`meanLoss=null`；指标名用稳定小写。  
反例：空 epoch 用 `meanLoss=0.0`；非空 epoch 用 null 表示“未计算”；sampleCount 与 meanLoss 不一致；指标值 NaN/Inf；把 epochIndex 当全局 step；在统计里保存参数引用；修改 `metrics()` 返回值并期望统计变化。

---

## 13. 测试/场景义务

epochIndex 0/负值；空/非空 epoch 一致性；batchCount/sampleCount 边界；meanLoss null/有限/NaN/Inf；指标空/非空/键空/值 NaN/Inf；`metric` 命中/缺失/null/空串；`elapsedMillis` 0/负值；映射复制独立性；`describe` 稳定；多任务共享。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class EpochStats {
    final Int _epochIndex
    final Bool _training
    final Long _batchCount
    final Long _sampleCount
    final Double? _meanLoss
    final Map<String, Double> _metrics
    final Long _elapsedMillis

    EpochStats(Int epochIndex, Bool training, Long batchCount,
               Long sampleCount, Double? meanLoss,
               Map<String, Double> metrics, Long elapsedMillis) {
        if epochIndex < 0 || batchCount < 0 || sampleCount < 0 {
            throw "EpochStats: negative count"
        }
        if elapsedMillis < 0 {
            throw "EpochStats: negative elapsed time"
        }
        if metrics == null {
            throw "EpochStats: null metrics"
        }
        if sampleCount == 0 {
            if batchCount != 0 || meanLoss != null {
                throw "EpochStats: empty epoch inconsistency"
            }
        } else {
            if batchCount == 0 || meanLoss == null {
                throw "EpochStats: non-empty epoch missing loss"
            }
            Double lossValue = meanLoss as Double
            if !isFinite(lossValue) {
                throw "EpochStats: non-finite mean loss"
            }
        }
        Map<String, Double> copiedMetrics = [:]
        List<String> keys = metrics.keys()
        Int keyIndex = 0
        while keyIndex < keys.length() {
            String key = keys.get(keyIndex)
            Double metricValue = metrics.get(key)
            if key == null || key == "" {
                throw "EpochStats: empty metric name"
            }
            if metricValue == null || !isFinite(metricValue) {
                throw "EpochStats: invalid metric value"
            }
            copiedMetrics.put(key, metricValue)
            keyIndex = keyIndex + 1
        }
        _epochIndex = epochIndex
        _training = training
        _batchCount = batchCount
        _sampleCount = sampleCount
        _meanLoss = meanLoss
        _metrics = copiedMetrics
        _elapsedMillis = elapsedMillis
    }

    Int epochIndex() { return _epochIndex }
    Bool isTraining() { return _training }
    Long batchCount() { return _batchCount }
    Long sampleCount() { return _sampleCount }
    Double? meanLoss() { return _meanLoss }
    Map<String, Double> metrics() { return _metrics.copy() }
    Long elapsedMillis() { return _elapsedMillis }

    Double? metric(String name) {
        if name == null { throw "EpochStats.metric: null name" }
        if name == "" { return null }
        return _metrics.get(name)
    }

    String describe() {
        String lossText = "null"
        if _meanLoss != null {
            Double lossValue = _meanLoss as Double
            lossText = str(lossValue)
        }
        return "epoch=" + str(_epochIndex)
            + " training=" + str(_training)
            + " samples=" + str(_sampleCount)
            + " loss=" + lossText
            + " elapsedMs=" + str(_elapsedMillis)
    }
}
```
