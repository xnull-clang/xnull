# `DataLoader`

| 项 | 值 |
| --- | --- |
| 类型 | `class DataLoader` |
| 包 | `xdk.ml` |
| 稳定性 | `preview` |
| 依赖 | `Dataset`、`MlBatch`、`Transform`、`Random`、`Context`、`Error` |

---

## 1. 定位

顺序批次加载器：从 `Dataset` 按索引取单样本，按 `transforms` 顺序变换，按 `batchSize` 拼批，可选按 epoch 洗牌。

只做单线程、按需、可复现的批流水线；不做多进程/多线程预取、异步队列、分布式采样、缓存、设备传输或自动 padding。

不做：数据下载、格式解码、tokenizer、图像解码、变长 padding、bucket/curriculum 采样、梯度累积、训练循环。

---

## 2. 设计逻辑

- 用 `class`：需要持有游标、当前 epoch 的顺序表、随机源和配置；不是一次性纯函数。
- `Dataset.size()` 用 `Long`；`batchSize` 用 `Int`；`batchCount` 用 `Long`，因为批次数由样本总数派生。
- 单样本批约定：`Dataset.get` 返回 `sampleCount == 1` 的 `MlBatch`；变换后仍必须为 1；拼批后样本数为实际收集数。
- 洗牌由调用方注入 `Random`；无全局 RNG。随机序列由注入的 `Random` 状态决定；同一 `Random` 状态 + 同一 `beginEpoch` 顺序可复现。
- 顺序模式不物化 `_order`，用 `Long` 游标直接索引，支持超过 `Int` 样本数；洗牌模式需要 `List<Long>` 顺序表，因此构造时要求 `size <= 2147483647`，否则 panic。这是基线的显式限制。
- `next` 在本地收集样本；只有成功拼批后才推进游标。失败不消耗样本，调用方可重试或 `beginEpoch`。
- `beginEpoch` 重置游标并按配置重新洗牌；调用方在每个 epoch 开始时显式调用。未调用时 `next` 首次调用会自动 `beginEpoch`。
- 默认拼批沿第 0 维拼接；所有样本的张量 dtype、rank、尾部维度必须一致。变长序列必须用自定义 `collate` 或前置 `Transform` 做 padding/截断。
- 自定义 `collate` 是构造器注入的函数；null 表示默认沿第 0 维拼接。
- `DataLoader` 不关闭借用的 `Dataset` 或 `Transform`；调用方负责它们的生命周期。
- 非线程安全；一个实例只由一个任务顺序驱动。没有全局 DataLoader 注册表。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_dataset` | `Dataset` | final | 非 null；非拥有引用 |
| `_batchSize` | `Int` | final | >0 |
| `_shuffle` | `Bool` | final | 是否按 epoch 洗牌 |
| `_transforms` | `List<Transform>` | final | 非 null；元素非 null；副本 |
| `_randomSource` | `Random?` | final | shuffle 为 true 时非 null；非拥有 |
| `_collate` | `Result<MlBatch,Error>(Context,List<MlBatch>)?` | final | null = 默认拼批 |
| `_order` | `List<Long>` | 内部 | 洗牌顺序；顺序模式为空 |
| `_cursor` | `Long` | 内部 | 已消费样本数；0..size |
| `_started` | `Bool` | 内部 | 是否已开始当前 epoch |

不变量：dataset 非 null；batchSize >0；transforms 元素非 null；shuffle true ⇒ randomSource 非 null；shuffle true ⇒ dataset.size() ≤ 2147483647；started 且洗牌模式 ⇒ order 长度等于 size；cursor 在 `[0, size]`；started 后 cursor 单调不减。

---

## 4. 生命周期

由构造器创建；无 close；不拥有 dataset/transform/random。可长期复用；每个 epoch 调用 `beginEpoch`。

`next` 到达末尾返回 `NotFound`；再次 `next` 仍返回 `NotFound`，直到 `beginEpoch` 重置。

`Dataset` 必须比 `DataLoader` 活得久；`DataLoader` 不关闭它。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `DataLoader(Dataset dataset, Int batchSize, Bool shuffle, List<Transform> transforms, Random? randomSource, Result<MlBatch,Error>(Context,List<MlBatch>)? collate)` | 数据集、批大小、洗牌、变换、随机源、拼批函数 | dataset/transforms 非 null；batchSize >0；transform 元素非 null；shuffle true 时 randomSource 非 null 且 dataset.size() ≤ 2147483647 | 违约 → panic |

构造器复制 `transforms` 列表；不复制 dataset/randomSource/collate。`collate == null` 表示默认拼批。

---

## 6. 字段表

见 §3；字段私有。不暴露 dataset 内部、随机源句柄或拼批实现。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `dataset` | 借用的数据集 | 无 | `Dataset` | 无 | 非拥有 |
| `batchSize` | 批大小 | 无 | `Int` | 无 | >0 |
| `shuffle` | 是否洗牌 | 无 | `Bool` | 无 | 配置 |
| `transforms` | 变换副本 | 无 | `List<Transform>` | 无 | 顺序即应用顺序 |
| `batchCount` | 批次数 | 无 | `Long` | 无 | 由 size/batchSize 派生 |
| `beginEpoch` | 开始新 epoch | 无 | `void` | 无 | 重置游标并按需洗牌 |
| `next` | 取下一批 | `Context context` | `Result<MlBatch, Error>` | `InvalidArgument`/`Cancelled`/`NotFound`/数据集/变换/拼批错误 | 阻塞；失败不推进游标 |
| `describe` | 单行描述 | 无 | `String` | 无 | 不含样本内容 |

说明：

- `batchCount`：`size == 0` 时为 0；否则为 `ceil(size / batchSize)`；用 `Long` 除法与余数计算，避免加法溢出。
- `beginEpoch`：`_cursor=0`、`_started=true`；顺序模式清空 `_order`；洗牌模式重建 `[0, size)` 并用注入的 `Random.shuffle` 打乱。`size` 必须稳定。
- `next`：未 started 时先调用 `beginEpoch`；`cursor >= size` → `NotFound`；每次最多取 `min(batchSize, size - cursor)` 个样本；对每个样本调用 `dataset.get`，再按顺序调用 `transforms`；变换后 `sampleCount` 必须为 1；收集完调用 `collate`；成功后才 `cursor += collected`。
- `next` 失败不改变游标、不改变 `_order`；已读取的样本不写回任何缓存。
- 默认拼批：所有样本的输入/目标数量一致；逐张量沿第 0 维拼接；dtype/rank/尾部维度必须一致，否则 `InvalidArgument`。拼接结果由 `MlBatch` 构造器再次校验。
- 自定义 `collate`：接收 `Context` 与样本列表；返回 `MlBatch`；返回样本数必须等于收集数，否则 `InvalidArgument`。
- `next` 的 `Context` 在每个样本/变换/拼批前检查；取消返回 `Cancelled`。
- `transforms()` 返回副本；修改不影响加载器。
- 不提供 `reset`/`skip`/`setEpoch`；epoch 语义只由 `beginEpoch` 表达。
- `DataLoader` 不拥有/关闭 dataset、transform、randomSource。

---

## 8. 使用的技术

- 随机访问数据集 + 顺序批次化；
- 显式 epoch 游标；
- 注入随机源洗牌；
- 变换顺序组合；
- 默认张量拼接；
- `Long` 样本/批次计数；
- 失败不推进游标；
- `Context` 取消。

---

## 9. 需要的支撑

- 语言：class、final 字段、Long、Int、Bool、List、Result、void；
- 运行时/包内原语：
  - `mlConcatTensors(List<Tensor> tensors) -> Result<Tensor, Error>`：同 dtype/rank/尾部维度，沿第 0 维拼接；由  `Tensor` 构造与元素读写组合实现，不新增公共类型；
  - `Random.shuffle(List<Long> values) -> void`；
  - `nowMono` 不需要；
- 接口：[`Dataset`](Dataset.md)、[`MlBatch`](MlBatch.md)、[`Transform`](Transform.md)、[`Tensor`](../../platform/tensor/Tensor.md)、`Random`、`Context`、`Error`、`BasicError`、`ErrorKind`、`cancelledError`。

---

## 10. 依赖的特性/接口/类

[`Dataset`](Dataset.md)、[`MlBatch`](MlBatch.md)、[`Transform`](Transform.md)、[`Tensor`](../../platform/tensor/Tensor.md)、[`TensorShape`](../../platform/tensor/TensorShape.md)、[`Random`](../../utils/random/Random.md)、`Context`、`Error`。

不依赖 `xdk.io`、`xdk.fs`、`xdk.net` 或任何模型运行时。

---

## 11. 所有权与并发

引用语义；`DataLoader` 由调用方拥有；dataset/transform/randomSource 都是非拥有引用；构造器复制变换列表。

非线程安全：`beginEpoch`/`next` 不得并发；一个实例由一个任务驱动。`next` 返回的 `MlBatch` 独立于加载器，可安全共享。

无 `equals`/`copy`；`==` 是引用身份；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：每个 epoch 调用 `beginEpoch()`，循环 `next(context)` 直到 `NotFound`；用注入的 `Random(42)` 做可复现洗牌；变长文本先用 padding 变换，再用自定义 collate；失败后重试同一批（游标未推进）。  
反例：不调用 `beginEpoch` 就期望自动换 epoch（只会在首次 next 初始化一次）；在 `next` 失败后假设样本已消费；用全局 RNG 洗牌；默认 collate 处理不同长度序列；在多个任务间共享一个 DataLoader；让 DataLoader 关闭 dataset；把 `Random` 状态当作可跨实例共享。

---

## 13. 测试/场景义务

batchSize 1/大于数据集/等于数据集；size 0/1/大值；顺序/洗牌；同 Random 状态可复现；`beginEpoch` 重置；next 末尾 `NotFound`；失败不推进游标；变换顺序；变换改变形状但保持 sampleCount；默认拼批同形状/不同形状；自定义 collate；返回样本数不符；取消；null context；关闭 dataset 后 next 返回 `Unavailable`；不关闭 dataset；batchCount 边界。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class DataLoader {
    final Dataset _dataset
    final Int _batchSize
    final Bool _shuffle
    final List<Transform> _transforms
    final Random? _randomSource
    final Result<MlBatch, Error>(Context, List<MlBatch>)? _collate
    List<Long> _order
    Long _cursor
    Bool _started

    DataLoader(Dataset dataset, Int batchSize, Bool shuffle,
               List<Transform> transforms, Random? randomSource,
               Result<MlBatch, Error>(Context, List<MlBatch>)? collate) {
        if dataset == null || transforms == null {
            throw "DataLoader: null dataset or transforms"
        }
        if batchSize <= 0 {
            throw "DataLoader: batch size must be positive"
        }
        if shuffle && randomSource == null {
            throw "DataLoader: shuffle requires random source"
        }
        if shuffle && dataset.size() > 2147483647 {
            throw "DataLoader: shuffle requires dataset size within Int"
        }
        _transforms = transforms.copy()
        Int transformIndex = 0
        while transformIndex < _transforms.length() {
            if _transforms.get(transformIndex) == null {
                throw "DataLoader: null transform"
            }
            transformIndex = transformIndex + 1
        }
        _dataset = dataset
        _batchSize = batchSize
        _shuffle = shuffle
        _randomSource = randomSource
        _collate = collate
        _order = []
        _cursor = 0
        _started = false
    }

    Dataset dataset() { return _dataset }
    Int batchSize() { return _batchSize }
    Bool shuffle() { return _shuffle }
    List<Transform> transforms() { return _transforms.copy() }

    Long batchCount() {
        Long size = _dataset.size()
        Long batchSizeLong = _batchSize as Long
        Long count = size / batchSizeLong
        if size % batchSizeLong != 0 {
            count = count + 1
        }
        return count
    }

    void beginEpoch() {
        _cursor = 0
        _started = true
        _order = []
        if !_shuffle {
            return
        }
        Long size = _dataset.size()
        Long sampleIndex = 0
        while sampleIndex < size {
            _order.push(sampleIndex)
            sampleIndex = sampleIndex + 1
        }
        Random? randomSource = _randomSource
        if randomSource == null {
            throw "DataLoader: null random source"
        }
        Random activeRandom = randomSource as Random
        activeRandom.shuffle(_order)
    }

    Result<MlBatch, Error> next(Context context) {
        if context == null { throw "DataLoader.next: null context" }
        if !_started {
            self.beginEpoch()
        }
        Long size = _dataset.size()
        if _cursor >= size {
            return Err(new BasicError(ErrorKind.NotFound,
                "data loader exhausted"))
        }
        Long remaining = size - _cursor
        Long wanted = remaining
        if wanted > (_batchSize as Long) {
            wanted = _batchSize as Long
        }
        List<MlBatch> samples = []
        Long offset = 0
        while offset < wanted {
            if context.isCancelled() {
                return Err(cancelledError("data loader next"))
            }
            Long sampleIndex = _cursor + offset
            if _shuffle {
                sampleIndex = _order.get(sampleIndex as Int)
            }
            Result<MlBatch, Error> sampleResult =
                _dataset.get(context, sampleIndex)
            if sampleResult.isErr() {
                return Err(sampleResult.error())
            }
            MlBatch sample = sampleResult.value()
            if sample == null || sample.sampleCount() != 1 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "dataset sample must have sample count 1"))
            }
            Int transformIndex = 0
            while transformIndex < _transforms.length() {
                if context.isCancelled() {
                    return Err(cancelledError("data loader transform"))
                }
                Result<MlBatch, Error> transformed =
                    _transforms.get(transformIndex).apply(context, sample)
                if transformed.isErr() {
                    return Err(transformed.error())
                }
                sample = transformed.value()
                if sample == null || sample.sampleCount() != 1 {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "transform must preserve sample count 1"))
                }
                transformIndex = transformIndex + 1
            }
            samples.push(sample)
            offset = offset + 1
        }
        if context.isCancelled() {
            return Err(cancelledError("data loader collate"))
        }
        Result<MlBatch, Error> collateResult = self.collateBatch(context, samples)
        if collateResult.isErr() {
            return Err(collateResult.error())
        }
        MlBatch batch = collateResult.value()
        if batch == null || batch.sampleCount() != (wanted as Int) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "collate returned wrong sample count"))
        }
        _cursor = _cursor + wanted
        return Ok(batch)
    }

    Result<MlBatch, Error> collateBatch(Context context,
                                      List<MlBatch> samples) {
        if _collate == null {
            return self.collateSamples(samples)
        }
        return _collate(context, samples)
    }

    Result<MlBatch, Error> collateSamples(List<MlBatch> samples) {
        if samples.length() == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "cannot collate empty sample list"))
        }
        Int inputCount = samples.get(0).inputCount()
        Int targetCount = samples.get(0).targetCount()
        Int sampleIndex = 1
        while sampleIndex < samples.length() {
            if samples.get(sampleIndex).inputCount() != inputCount
                    || samples.get(sampleIndex).targetCount() != targetCount {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "sample tensor count mismatch"))
            }
            sampleIndex = sampleIndex + 1
        }
        List<Tensor> inputs = []
        Int inputIndex = 0
        while inputIndex < inputCount {
            List<Tensor> inputTensors = []
            Int cursorIndex = 0
            while cursorIndex < samples.length() {
                inputTensors.push(samples.get(cursorIndex).input(inputIndex))
                cursorIndex = cursorIndex + 1
            }
            Result<Tensor, Error> concatenated = mlConcatTensors(inputTensors)
            if concatenated.isErr() {
                return Err(concatenated.error())
            }
            inputs.push(concatenated.value())
            inputIndex = inputIndex + 1
        }
        List<Tensor> targets = []
        Int targetIndex = 0
        while targetIndex < targetCount {
            List<Tensor> targetTensors = []
            Int cursorIndex = 0
            while cursorIndex < samples.length() {
                targetTensors.push(samples.get(cursorIndex).target(targetIndex))
                cursorIndex = cursorIndex + 1
            }
            Result<Tensor, Error> concatenated = mlConcatTensors(targetTensors)
            if concatenated.isErr() {
                return Err(concatenated.error())
            }
            targets.push(concatenated.value())
            targetIndex = targetIndex + 1
        }
        return Ok(new MlBatch(samples.length(), inputs, targets))
    }

    String describe() {
        return "data loader batchSize=" + str(_batchSize)
            + " batches=" + str(self.batchCount())
            + " shuffle=" + str(_shuffle)
            + " transforms=" + str(_transforms.length())
    }
}
```
