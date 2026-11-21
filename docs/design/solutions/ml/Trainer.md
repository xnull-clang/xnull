# `Trainer`

| 项 | 值 |
| --- | --- |
| 类型 | `protocol Trainer` |
| 包 | `xdk.ml` |
| 稳定性 | `preview` |
| 依赖 | `Optimizer`、`LossKind`、`EpochStats`、`DataLoader`、`Context`、`Error` |

---

## 1. 定位

训练/评估循环合同：读取 `DataLoader` 批次、执行前向、计算损失、按显式梯度更新参数、返回 `EpochStats`。

只定义训练器的能力面与生命周期，不提供自动微分实现、优化器状态实现、模型结构、设备放置或分布式训练。基线 `xdk.ml` 不附带任何 `Trainer` 实现；实现属于 X 或生态。

不做：反向传播内核、数值梯度、参数初始化、学习率调度、梯度裁剪、混合精度、checkpoint、指标导出、早停。

---

## 2. 设计逻辑

- 非泛型协议：模型/参数/梯度类型不在协议签名中出现，由实现持有；这样避免把自动微分类型塞进推理包。
- 基线是推理优先：`Trainer` 只定义合同，`Ml` 不创建默认训练器；没有自动微分引擎时不能伪造训练。
- 梯度合同是显式的：`trainEpoch` 必须通过自动微分引擎得到梯度，再交给优化器更新；不得用有限差分、数值扰动、前向损失近似或“静默 detach”冒充梯度。
- 不支持的算子/损失/优化器必须返回 `Unsupported`；不得返回一个看似成功但没有更新参数的 epoch。
- `evaluate` 只前向、不更新参数/优化器状态；可以复用 `InferenceSession` 或实现自己的推理路径。
- `optimizer()`/`lossKind()` 返回配置快照；实现不得通过它们暴露可变优化器状态。
- `DataLoader` 是借用：Trainer 不关闭它；每个 epoch 调用 `beginEpoch`，循环 `next` 直到 `NotFound`。
- `close` 是终态，幂等；关闭后 `trainEpoch`/`evaluate` 返回 `Unavailable`。
- 没有全局 Trainer 注册表、默认模型或隐式设备选择。

---

## 3. 表示与不变量

协议无字段。实现保证：

- 实现持有模型、参数、自动微分引擎和优化器状态，但不通过协议暴露；
- `optimizer()`/`lossKind()` 返回非 null 配置快照；
- `trainEpoch` 返回的 `EpochStats.isTraining()` 为 true；
- `evaluate` 返回的 `EpochStats.isTraining()` 为 false；
- `trainEpoch`/`evaluate` 的 `epochIndex` 单调不减；训练 epoch 至少递增一次；
- `sampleCount == 0` 时 `meanLoss == null`，且不更新参数；
- `close` 幂等；关闭后不可重新打开；
- `isOpen` 与生命周期一致。
- 不修改传入 `DataLoader` 的配置；不关闭它。

---

## 4. 生命周期

实现创建后为 open；可 `trainEpoch`/`evaluate`；`close` 后为 closed；`close` 幂等；关闭后不可重新打开。

关闭后 `optimizer()`、`lossKind()`、`isOpen()`、`describe()` 仍可读；`trainEpoch`/`evaluate` 返回 `Unavailable`。

Trainer 拥有自动微分/优化器资源（若有），必须在 `close` 释放；`DataLoader`、`Dataset`、`Optimizer` 配置由调用方拥有。

---

## 5. 构造契约

协议无构造。实现类提供构造器，并在构造完成后处于 open；构造失败由实现决定，协议不规定。

实现构造器必须显式接收模型、优化器配置、损失种类、自动微分引擎（或内部创建）和随机源（若需要）；不得读取全局默认 Trainer/设备。

---

## 6. 字段表

无协议字段。实现可持有模型、参数、梯度缓冲、优化器状态、随机源、设备句柄和指标聚合器，但不得通过协议暴露可变引用。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `optimizer` | 优化器配置 | 无 | `Optimizer` | 无 |
| `lossKind` | 损失种类 | 无 | `LossKind` | 无 |
| `trainEpoch` | 训练一个 epoch | `Context context, DataLoader dataLoader` | `Result<EpochStats, Error>` | `InvalidArgument`/`Unavailable`/`Cancelled`/`Unsupported`/实现错误 |
| `evaluate` | 评估一个 epoch | `Context context, DataLoader dataLoader` | `Result<EpochStats, Error>` | 同上 |
| `isOpen` | 是否可训练 | 无 | `Bool` | 无 |
| `close` | 关闭 | 无 | `Result<Unit, Error>` | `Io`（诊断） |
| `describe` | 单行描述 | 无 | `String` | 无 |

说明：

- `trainEpoch`：`context`/`dataLoader` null → panic；关闭 → `Unavailable`；取消 → `Cancelled`；数据/模型/梯度合同错误 → `InvalidArgument`；不支持的算子/损失/优化器 → `Unsupported`。
- `trainEpoch` 步骤：调用 `dataLoader.beginEpoch()`；循环 `next(context)`；对每批执行前向、`Ml.computeLoss` 或等价损失、自动微分反向、优化器更新；累计样本/批次/损失；遇到 `NotFound` 正常结束。
- `trainEpoch` 不得用 `Ml.computeLoss` 的标量结果假装梯度；`Ml.computeLoss` 只做前向损失。
- `trainEpoch` 成功时返回非空/空 epoch 一致的统计；失败时不得返回部分 `EpochStats`。参数可能已部分更新时，错误必须显式，调用方需重建/恢复状态。
- `evaluate`：不调用优化器 `step`、不改变参数/优化器状态、不启用训练专用随机增强；返回 `isTraining == false`。评估应传入 `shuffle == false` 的 `DataLoader`；实现不得擅自改变其配置。
- `evaluate` 可以使用 `InferenceSession` 或实现自己的只前向路径；不得为了评估偷偷做梯度更新。
- `epochIndex` 由实现维护：训练 epoch 从 1 开始（或实现声明的非负起点）单调递增；`evaluate` 返回当前训练 epoch 序号，不递增。
- `close`：第一次调用释放资源并标记 closed；后续返回 `Ok(unit)`；关闭失败作为诊断返回但保持 closed。
- `describe` 不输出参数、梯度、样本内容或敏感路径。
- 不提供 `step`/`fit`/`save`/`load`/`resume`；这些是 X 或生态。

---

## 8. 使用的技术

- 非泛型协议；
- 显式梯度合同；
- epoch 循环 + DataLoader 借用；
- 优化器配置快照；
- 自动微分引擎委托；
- 取消/幂等关闭；
- 训练/评估路径分离。

---

## 9. 需要的支撑

- 语言：protocol、class、Bool、Result、Unit、void；
- 运行时/实现：
  - 自动微分引擎（X）：前向图、反向传播、参数/梯度布局、`noGrad` 评估；
  - 优化器状态与参数更新（X 或实现）；
  - 指标聚合；
  - `nowMono` 计时（实现可选）；
- 接口：[`Optimizer`](Optimizer.md)、[`LossKind`](LossKind.md)、[`EpochStats`](EpochStats.md)、[`DataLoader`](DataLoader.md)、[`Batch`](Batch.md)、[`Ml`](Ml.md)、`Context`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`、`cancelledError`。

---

## 10. 依赖的特性/接口/类

[`Optimizer`](Optimizer.md)、[`LossKind`](LossKind.md)、[`EpochStats`](EpochStats.md)、[`DataLoader`](DataLoader.md)、[`Batch`](Batch.md)、[`Ml`](Ml.md)、[`Tensor`](../../platform/tensor/Tensor.md)、`Context`、`Error`。

不依赖 PyTorch、TensorFlow、ONNX Runtime 或任何自动微分实现。

---

## 11. 所有权与并发

实现拥有模型/梯度/优化器状态与自动微分资源；调用方拥有 `DataLoader` 及其 `Dataset`。`optimizer()`/`lossKind()` 返回配置快照，不转移状态所有权。

协议不承诺线程安全：一个 Trainer 由一个训练任务驱动；`trainEpoch`/`evaluate`/`close` 不得并发。关闭必须等待在途 epoch 完成。

无 `equals`/`copy`；Trainer 是行为/资源对象，不是值对象。

---

## 12. 示例与反例

正确：实现持有显式参数列表和自动微分引擎；每个 batch 先 `zeroGrad`，前向，`Ml.computeLoss`，反向，优化器 `step`；评估时关闭梯度并只前向；不支持的损失返回 `Unsupported`；`close` 释放引擎。  
反例：用有限差分算梯度；把 `Ml.computeLoss` 的返回值当梯度；在 `evaluate` 中更新参数；遇到不支持算子时静默跳过；用全局 Trainer 单例；Trainer 关闭 `DataLoader`；返回 `isTraining == false` 的训练统计；没有更新任何参数却返回成功 epoch。

---

## 13. 测试/场景义务

`optimizer`/`lossKind` 非 null；训练/评估标志；空/非空 DataLoader；`NotFound` 正常结束；取消；关闭后 `Unavailable`；重复 close；不支持损失/优化器/算子 → `Unsupported`；评估不改变参数/优化器状态；epochIndex 单调；批次/样本计数；平均损失；失败不返回部分统计；DataLoader 不被关闭；并发声明。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
protocol Trainer {
    Optimizer optimizer();
    LossKind lossKind();
    Result<EpochStats, Error> trainEpoch(Context context,
                                         DataLoader dataLoader);
    Result<EpochStats, Error> evaluate(Context context,
                                       DataLoader dataLoader);
    Bool isOpen();
    Result<Unit, Error> close();
    String describe();
}
```
