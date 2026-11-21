# `Batch`

| 项 | 值 |
| --- | --- |
| 类型 | `class Batch` |
| 包 | `xdk.ml` |
| 稳定性 | `preview` |
| 依赖 | `Tensor`、`List`、`Int` |

---

## 1. 定位

带批维的样本集合：`sampleCount` 个样本，每个输入/目标张量的第 0 维等于样本数。

只做批次容器与基础校验；不做拼接、填充、截断、洗牌、设备放置或标签解码。

不做：变长序列 padding、ragged tensor、稀疏张量、样本 ID、权重、掩码、元数据映射、批内排序。

---

## 2. 设计逻辑

- 用 `class`：需要复制输入/目标列表，并逐个校验张量的第 0 维与 `sampleCount` 一致。
- 单样本也用 `Batch` 表示：`sampleCount == 1`，张量形状仍带第 0 维 1；这样 Dataset 到 DataLoader 的合同一致，不需要“有无批维”的两套规则。
- 输入至少一个；目标可以为空，表示无监督/推理样本。目标非空时也必须满足批维合同。
- 张量必须 rank ≥1；标量不能作为批样本，因为无法表达批维。
- `Tensor` 不可变，批次共享张量引用；列表返回副本。
- 不提供 `slice`/`concat`；这些是 `DataLoader` 的内部拼批职责，避免在值对象上堆积数据管道算法。
- `withTargets` 返回新批次，用于给无标签样本补充目标；原批次不变。
- 不引入 `Sample` 类型：单样本就是 `sampleCount == 1` 的 `Batch`。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_sampleCount` | `Int` | final | ≥1 |
| `_inputs` | `List<Tensor>` | final | 非空；元素非 null；每个 rank ≥1；dim(0) == sampleCount |
| `_targets` | `List<Tensor>` | final | 可空；元素非 null；每个 rank ≥1；dim(0) == sampleCount |

不变量：sampleCount ≥1；输入列表非空；所有张量非 null；所有张量 rank ≥1；所有张量第 0 维等于 sampleCount；列表私有且返回副本。

---

## 4. 生命周期

构造后不可变；无 close；无资源；张量由 GC 管理；可跨任务共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Batch(Int sampleCount, List<Tensor> inputs, List<Tensor> targets)` | 样本数、输入、目标 | sampleCount ≥1；inputs 非空；targets 非 null；张量非 null、rank ≥1、dim(0) == sampleCount | 违约 → panic |

构造器复制两个列表；张量本身不可变，可共享。

---

## 6. 字段表

见 §3；字段私有。不暴露批内索引、设备指针或样本元数据。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `sampleCount` | 样本数 | 无 | `Int` | 无 | ≥1 |
| `inputs` | 输入张量副本 | 无 | `List<Tensor>` | 无 | 非空 |
| `targets` | 目标张量副本 | 无 | `List<Tensor>` | 无 | 可空 |
| `inputCount` | 输入数 | 无 | `Int` | 无 | ≥1 |
| `targetCount` | 目标数 | 无 | `Int` | 无 | 可为 0 |
| `hasTargets` | 是否有目标 | 无 | `Bool` | 无 | targetCount >0 |
| `input` | 按序号取输入 | `Int inputIndex` | `Tensor` | 越界 → panic | O(1) |
| `target` | 按序号取目标 | `Int targetIndex` | `Tensor` | 越界 → panic | O(1) |
| `withTargets` | 替换目标 | `List<Tensor> targets` | `Batch` | 非法 → panic | 新批次 |
| `describe` | 单行描述 | 无 | `String` | 无 | 不含张量内容 |

说明：

- `input`/`target` 的索引域分别是 `[0, inputCount)` 和 `[0, targetCount)`。
- `withTargets` 复用原输入与 `sampleCount`，只替换目标；传入列表被复制并重新校验。
- 不提供 `withInputs`；输入变化意味着新的批次语义。
- 不提供 `equals`；张量值比较容易昂贵，需要时逐张量比较。
- `describe` 输出样本数、输入数、目标数，不输出形状/数值。

---

## 8. 使用的技术

- 不可变批容器；
- 列表复制；
- 批维合同校验；
- 张量不可变共享；
- 目标替换工厂。

---

## 9. 需要的支撑

- 语言：class、final 字段、Int、Bool、List；
- 张量：`Tensor.rank()`、`Tensor.tensorShape().dim(0)`；
- 接口：[`Dataset`](Dataset.md)、[`DataLoader`](DataLoader.md)、[`Transform`](Transform.md)、[`InferenceSession`](InferenceSession.md)。

---

## 10. 依赖的特性/接口/类

[`Tensor`](../../platform/tensor/Tensor.md)、[`TensorShape`](../../platform/tensor/TensorShape.md)、[`Dataset`](Dataset.md)、[`DataLoader`](DataLoader.md)、[`Transform`](Transform.md)。

不重复定义张量；不依赖具体数据集或模型格式。

---

## 11. 所有权与并发

不可变；可共享；`inputs()`/`targets()` 返回副本；张量不可变；无资源；无取消点。  
相等：没有 `equals`；`==` 是引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：`new Batch(32, [images], [labels])`，其中 `images` 形状 `[32, 3, 224, 224]`、`labels` 形状 `[32]`；单样本用 `new Batch(1, [image], [label])`；无标签样本用空目标列表。  
反例：输入张量形状 `[3, 224, 224]` 却声明 `sampleCount == 32`；用标量目标且无批维；把 `sampleCount` 当特征数；构造后修改传入列表并期望批次变化；用空输入表示无监督样本；在批次上做 padding。

---

## 13. 测试/场景义务

sampleCount 0/负数 panic；输入空列表 panic；目标 null panic；张量 null panic；rank 0 张量 panic；dim(0) 不等于 sampleCount panic；单样本/多样本；无目标/有目标；`withTargets` 独立；`input`/`target` 越界 panic；列表复制独立性；`describe` 稳定；共享张量读取。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class Batch {
    final Int _sampleCount
    final List<Tensor> _inputs
    final List<Tensor> _targets

    Batch(Int sampleCount, List<Tensor> inputs, List<Tensor> targets) {
        if sampleCount < 1 {
            throw "Batch: sample count must be positive"
        }
        if inputs == null || targets == null {
            throw "Batch: null tensor list"
        }
        if inputs.length() == 0 {
            throw "Batch: empty input list"
        }
        Int tensorIndex = 0
        while tensorIndex < inputs.length() {
            Tensor tensor = inputs.get(tensorIndex)
            if tensor == null {
                throw "Batch: null input tensor"
            }
            if tensor.rank() < 1 {
                throw "Batch: input tensor must have rank >= 1"
            }
            if tensor.tensorShape().dim(0) != sampleCount {
                throw "Batch: input batch dimension mismatch"
            }
            tensorIndex = tensorIndex + 1
        }
        tensorIndex = 0
        while tensorIndex < targets.length() {
            Tensor tensor = targets.get(tensorIndex)
            if tensor == null {
                throw "Batch: null target tensor"
            }
            if tensor.rank() < 1 {
                throw "Batch: target tensor must have rank >= 1"
            }
            if tensor.tensorShape().dim(0) != sampleCount {
                throw "Batch: target batch dimension mismatch"
            }
            tensorIndex = tensorIndex + 1
        }
        _sampleCount = sampleCount
        _inputs = inputs.copy()
        _targets = targets.copy()
    }

    Int sampleCount() { return _sampleCount }
    List<Tensor> inputs() { return _inputs.copy() }
    List<Tensor> targets() { return _targets.copy() }
    Int inputCount() { return _inputs.length() }
    Int targetCount() { return _targets.length() }
    Bool hasTargets() { return _targets.length() > 0 }

    Tensor input(Int inputIndex) {
        if inputIndex < 0 || inputIndex >= _inputs.length() {
            throw "Batch.input: input index out of range"
        }
        return _inputs.get(inputIndex)
    }

    Tensor target(Int targetIndex) {
        if targetIndex < 0 || targetIndex >= _targets.length() {
            throw "Batch.target: target index out of range"
        }
        return _targets.get(targetIndex)
    }

    Batch withTargets(List<Tensor> targets) {
        return new Batch(_sampleCount, _inputs, targets)
    }

    String describe() {
        return "batch samples=" + str(_sampleCount)
            + " inputs=" + str(_inputs.length())
            + " targets=" + str(_targets.length())
    }
}
```
