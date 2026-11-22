# `xdk.ml` 机器学习设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.ml` |
| 层 | L8 solutions |
| 依赖 | `xdk.core`、`xdk.tensor`、`xdk.random`；按需 `xdk.linalg`、`xdk.codec` |
| 被依赖 | 应用、服务、Agent、嵌入式/计算产品 |
| 稳定性 | `preview` |
| 状态 | 设计基线；不含实现 |

> 本目录只定义模型、推理、数据管道与训练抽象；不包含模型运行时、ONNX/TFLite 解析器、GPU/NPU 内核或自动微分引擎。运行时适配器由宿主注入。

---

## 1. 包定位

`xdk.ml` 把“模型是什么、如何推理、数据如何成批、训练抽象如何组合”收敛成稳定合同：

- **推理优先**：`Model` 描述格式/元数据/输入/输出，`InferenceSession` 执行 `List<Tensor>`，`InferenceResult` 承载输出；
- **提供者显式**：`SessionOptions` 用有序 `ExecutionProvider` 列表表达优先级，不读全局环境；
- **数据管道**：`Dataset` 随机访问单样本，`DataLoader` 负责批大小/洗牌/变换/拼批，`MlBatch` 统一带批维；
- **训练抽象**：`Optimizer`/`LossKind`/`Trainer`/`EpochStats` 只定义合同；自动微分、参数更新和优化器状态属于 X，本包不伪造；
- **复用底层**：所有数值数据是 [`xdk.tensor.Tensor`](../../platform/tensor/Tensor.md)，二维桥接用 [`xdk.linalg`](../../platform/linalg/README.md)，不重复定义 `Tensor`/`Matrix`；
- **平台透明**：公共 API 不出现 ONNX Runtime/TFLite/Torch/CUDA/ROCm/DirectML/OpenVINO 类型、句柄或头文件。

不定义 `ModelRuntime` 公共类型：运行时适配器由宿主以 `mlSessionCreateRaw` 等原语注入，公共 API 不暴露运行时对象，也不维护全局注册表。

不做：模型下载/缓存、容器解析、图优化、算子内核、Tokenizer、图像/音频解码、分布式训练、量化、模型签名、指标导出、全局会话/提供者/数据集注册表。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 推理优先 | 先保证模型描述、输入/输出合同和会话生命周期；训练只给抽象 |
| 显式格式 | `ModelFormat` 由调用方声明；不按扩展名/魔数猜测 |
| 显式提供者 | `SessionOptions.providers` 是有序列表；CPU 回退是独立布尔开关 |
| 线程显式 | `SessionOptions` 的线程数由调用方决定；可用 [`CpuTopology`](../../platform/os/cpu/CpuTopology.md) 作为上限输入，本包不自动探测/绑核 |
| 动态维度显式 | `ModelInput`/`ModelOutput` 用并行布尔列表标记动态轴，不用负数哨兵 |
| 位置合同 | `run` 的第 i 个输入对应 `Model.inputs().get(i)`；输出同序 |
| 批维统一 | `MlBatch.sampleCount` 与每个张量第 0 维一致；单样本也带批维 1 |
| 运行时注入 | `Ml.openSession` 调用宿主注入的 `mlSessionCreateRaw`；本包不链接运行时 |
| 不伪造训练 | 本包无自动微分；`Trainer` 是协议，基线无实现；`Ml.computeLoss` 只做前向 |
| 可取消 | 阻塞方法首参 `Context`；取消返回 `Cancelled`，不返回部分结果 |
| 可恢复失败 | 运行时/数据/适配器失败用 `Result`；调用方违约用 panic |
| 资源显式 | 会话/数据集有幂等 `close`；关闭后操作返回 `Unavailable` |
| 无全局状态 | 无全局会话、提供者、数据集、Trainer 或默认设备注册表 |
| 计数宽度 | 样本总数/元素数/耗时用 `Long`；批大小/线程数/epoch 序号用 `Int` |
| 列表复制 | 值对象构造时复制列表/映射；读接口返回副本 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `ModelFormat` | enum | ONNX/TFLite/TorchScript/Other | [`ModelFormat.md`](ModelFormat.md) |
| `MlTask` | enum | 文本/视觉/音频/表格任务 | [`MlTask.md`](MlTask.md) |
| `ExecutionProvider` | enum | CPU/CUDA/ROCm/DirectML/OpenVINO/NPU/DSP/FPGA/Other | [`ExecutionProvider.md`](ExecutionProvider.md) |
| `ModelMetadata` | class | 不可变模型描述 | [`ModelMetadata.md`](ModelMetadata.md) |
| `ModelInput` | class | 输入名称/dtype/维度/动态轴 | [`ModelInput.md`](ModelInput.md) |
| `ModelOutput` | class | 输出名称/dtype/维度/动态轴 | [`ModelOutput.md`](ModelOutput.md) |
| `Model` | class | 格式/元数据/输入输出/不透明字节 | [`Model.md`](Model.md) |
| `InferenceSession` | class | 已打开推理会话 | [`InferenceSession.md`](InferenceSession.md) |
| `SessionOptions` | class | 提供者/线程/优化/回退/选项 | [`SessionOptions.md`](SessionOptions.md) |
| `InferenceResult` | class | 输出张量/名称/耗时 | [`InferenceResult.md`](InferenceResult.md) |
| `Dataset` | protocol | 随机访问单样本 | [`Dataset.md`](Dataset.md) |
| `MlBatch` | class | 带批维的样本集合 | [`MlBatch.md`](MlBatch.md) |
| `DataLoader` | class | 批大小/洗牌/变换/拼批 | [`DataLoader.md`](DataLoader.md) |
| `Transform` | protocol | 批次变换合同 | [`Transform.md`](Transform.md) |
| `OptimizerKind` | enum | SGD/Adam/AdamW/RMSprop/AdaGrad/Other | [`OptimizerKind.md`](OptimizerKind.md) |
| `Optimizer` | class | 优化器超参数配置 | [`Optimizer.md`](Optimizer.md) |
| `LossKind` | enum | MSE/MAE/CE/BCE/NLL/Other | [`LossKind.md`](LossKind.md) |
| `Trainer` | protocol | 训练/评估循环合同 | [`Trainer.md`](Trainer.md) |
| `EpochStats` | class | epoch 统计快照 | [`EpochStats.md`](EpochStats.md) |
| `Ml` | class（静态入口） | openSession/run/computeLoss | [`Ml.md`](Ml.md) |

索引共 20 个类型文件；每个类型一个 PascalCase 文件。`README.md` 只做索引与包级规则，不重复类型的方法表/伪代码。

---

## 4. 跨类型规则

1. **格式、提供者、任务正交**：`ModelFormat` 说明容器；`ExecutionProvider` 说明执行后端；`MlTask` 说明输出解释。三者互不推断。
2. **模型与会话分离**：`Model` 不持有运行时资源；`InferenceSession` 才持有句柄并借用 `Model`。会话关闭不关闭模型。
3. **位置而非名称**：`run` 按 `Model.inputs()` 顺序收 `List<Tensor>`；输出按 `Model.outputs()` 顺序返回。名称只用于查找/诊断。
4. **动态维度**：`ModelInput`/`ModelOutput` 的 `dimensionDynamic` 为 true 的轴接受任意非负长度；固定轴精确匹配。动态轴声明值必须为 0，不表示空张量。
5. **批维统一**：`MlBatch` 的每个张量 rank ≥1，且 `dim(0) == sampleCount`；`Dataset.get` 返回 `sampleCount == 1` 的单样本。
6. **DataLoader 借用**：`DataLoader` 不关闭 `Dataset`、`Transform` 或随机源；`next` 失败不推进游标；`beginEpoch` 重置并洗牌。
7. **拼批边界**：默认拼批只沿第 0 维拼接同 dtype/rank/尾部维度的张量；变长序列必须前置 padding/截断或自定义 `collate`。
8. **训练抽象不执行**：`Optimizer` 只是超参数配置；`Ml.computeLoss` 只算前向标量；`Trainer` 才定义训练循环，基线无实现。自动微分/参数更新是 X。
9. **梯度合同**：`Trainer` 实现必须用自动微分引擎产生梯度；不得用有限差分、数值扰动或静默 detach 冒充。缺失能力返回 `Unsupported`。
10. **生命周期**：`InferenceSession`/`Dataset` 的 `close` 幂等；关闭后 `run`/`get` 返回 `Unavailable`；`Model`/`MlBatch`/`InferenceResult`/`EpochStats` 无 close。
11. **计数宽度**：数据集样本数、批次数、耗时、元素数用 `Long`；批大小、维度、线程数、epoch 序号用 `Int`。
12. **无全局注册表**：会话、提供者、数据集、Trainer、随机源都由调用方显式持有；环境变量/默认设备不构成隐式输入。
13. **不重复底层**：不定义 `Tensor`/`Matrix`/`Vector`；需要矩阵运算时用 `xdk.linalg`，需要元素运算时用 `xdk.tensor.TensorOps`。

---

## 5. 场景

### M1：一次推理

```xnull
Model model = new Model(ModelFormat.Onnx, metadata, inputs, outputs, payload)
Result<InferenceSession, Error> opened =
    Ml.openSession(context, model, SessionOptions.defaults())
if opened.isErr() { return 1 }
InferenceSession session = opened.value()
Result<InferenceResult, Error> inferred =
    session.run(context, [inputIds, attentionMask])
if inferred.isErr() { return 1 }
Tensor logits = inferred.value().output(0)
Result<Unit, Error> closed = session.close()
if closed.isErr() { return 1 }
```

### M2：批量推理

调用方把同一模型的多个输入批次分别 `run`；`InferenceSession` 不内置批调度。需要并发时由调用方在适配器线程安全的前提下并发调用，并避免与 `close` 竞争。

### M3：数据管道

```xnull
DataLoader loader = new DataLoader(dataset, 32, true,
    [normalizeTransform], new Random(42), null)
loader.beginEpoch()
Bool loading = true
while loading {
    Result<MlBatch, Error> nextBatch = loader.next(context)
    if nextBatch.isErr() {
        if nextBatch.error().kind() == ErrorKind.NotFound {
            loading = false
        } else {
            return 1
        }
    } else {
        MlBatch batch = nextBatch.value()
        Int batchSamples = batch.sampleCount()
    }
}
```

`NotFound` 表示 epoch 结束，不是数据损坏；`next` 失败不推进游标。

### M4：损失与训练计划

```xnull
Result<Tensor, Error> loss =
    Ml.computeLoss(context, LossKind.CrossEntropy, logits, classTargets)
```

`loss` 是标量张量，不含梯度。真正的训练循环由 `Trainer` 实现（X）完成：前向 → 损失 → 自动微分反向 → 优化器更新 → `EpochStats`。基线不提供 `Trainer` 实现，也不提供 `Optimizer.step`。

### M5：提供者优先级

```xnull
SessionOptions options = new SessionOptions(
    [ExecutionProvider.Cuda, ExecutionProvider.Cpu],
    4, 1, true, true, false, false, true, 0,
    ["cuda.device_id":"0"])
```

提供者顺序是优先级；`enableCpuFallback` 控制未覆盖算子是否允许隐式回退。不保证 CUDA 可用；适配器以 `Unsupported`/`Unavailable` 显式失败。

---

## 6. 缺口

| 缺口 | 归属 |
| --- | --- |
| ONNX/TFLite/TorchScript 解析、图校验、权重解包 | 运行时适配器/生态 |
| CPU/GPU/NPU/DSP/FPGA 算子内核、图优化、量化 | X 或运行时 |
| 自动微分、参数初始化、优化器状态、梯度裁剪、混合精度 | X |
| `Trainer` 具体实现、checkpoint、恢复训练 | X |
| Tokenizer、图像解码/增强、音频重采样、文本后处理 | 领域包/生态 |
| 变长序列 padding/bucketing、动态批调度 | X |
| 模型下载、缓存、签名校验、内存映射 | X |
| 分布式训练、all-reduce、参数服务器 | X |
| 指标导出、实验跟踪、可视化 | 应用/`xdk.metrics` |
| 模型格式自动探测、跨格式转换 | 不在基线 |
| 可选输入、稀疏/ragged 张量、量化 dtype | X |

---

## 7. 研究来源

以下来源用于对齐模型/推理/数据/训练的能力面；本包只吸收抽象，不绑定其运行时或 API 名称。访问日期：2026-11-22。

| 来源 | 对齐点 |
| --- | --- |
| [ONNX Runtime C++ `Ort::Session`](https://onnxruntime.ai/docs/api/c/struct_ort_1_1_session.html) | 会话打开、输入/输出、Run、并发语义 |
| [ONNX Runtime C++ `Ort::SessionOptions`](https://onnxruntime.ai/docs/api/c/struct_ort_1_1_session_options.html) | 线程数、图优化、执行提供者、选项 |
| [ONNX Runtime `Ort::ModelMetadata`](https://onnxruntime.ai/docs/api/c/struct_ort_1_1_model_metadata.html) | 名称/版本/生产者/描述/自定义元数据 |
| [ONNX Runtime Execution Providers](https://onnxruntime.ai/docs/execution-providers/) | 提供者优先级、CPU 回退、设备选项 |
| [PyTorch C++ Frontend](https://docs.pytorch.org/cppdocs/frontend.html) | 训练循环、优化器、数据加载器组合 |
| [PyTorch C++ Data Loading](https://docs.pytorch.org/cppdocs/api/data/index.html) | Dataset/DataLoader/Transform/Sampler 分层 |
| [PyTorch C++ Optimizers](https://docs.pytorch.org/cppdocs/api/optim/index.html) | SGD/Adam/AdamW 等优化器超参数面 |
| [TensorFlow Lite Inference](https://www.tensorflow.org/lite/guide/inference) | Interpreter、AllocateTensors、Invoke、输入/输出 |
| [TensorFlow Lite Delegates](https://www.tensorflow.org/lite/performance/delegates) | CPU/GPU/NPU 委托与提供者边界 |
| [Hugging Face Pipeline Tutorial](https://huggingface.co/docs/transformers/en/pipeline_tutorial) | 任务 ID、批推理、设备选择 |
| [Hugging Face Pipelines](https://huggingface.co/docs/transformers/en/main_classes/pipelines) | Pipeline 组成、任务参数、输出后处理边界 |

对齐结论：

- ONNX Runtime 的 Session/SessionOptions/EP 说明“格式 + 提供者 + 选项”必须分开；本包用 `ModelFormat`、`ExecutionProvider`、`SessionOptions` 三分。
- PyTorch C++ 的 `Dataset`→`DataLoader`→`Transform` 说明数据管道应独立于模型；本包沿用该分层，但样本统一为 `MlBatch`。
- TFLite 的 delegate 说明后端能力不是容器格式的属性；本包的提供者/格式正交。
- Hugging Face pipeline 的任务 ID 说明任务标签应稳定且可映射；本包用 `MlTask`，但不内置 tokenizer/后处理。

---

## 8. 安全与资源

- **不可信模型字节**：`Model` 不解析 payload；`Ml.openSession` 把字节交给宿主适配器。适配器必须在沙箱/权限边界内处理不可信模型，防止路径穿越、任意代码执行和内存破坏。
- **内存上限**：`SessionOptions.maximumMemoryBytes` 是请求而非保证；适配器应拒绝超过运行时能力的值。大模型 `payloadCopy()` 会复制，基线不提供 mmap。
- **提供者选项**：`providerOptions` 可能包含设备/路径/环境相关值；不要放密钥。适配器应拒绝未知/危险选项。
- **元数据**：`ModelMetadata.customMetadata` 可能来自外部模型；不要在日志中输出全部映射，避免泄露 token/路径。
- **数据集**：`Dataset.get` 的样本可能含恶意内容；解码/预处理由实现负责，本包不做边界检查之外的信任假设。
- **生命周期**：会话/数据集关闭后必须拒绝新操作；`close` 幂等；并发 `close` 与 `run`/`get` 由调用方避免。
- **无全局状态**：不存在可由第三方替换的全局会话/提供者注册表，降低跨租户串扰风险。

---

## 9. 验收状态

- 20 个类型文件均有 14 段；README 只做索引与包级说明；
- 公开签名只使用 XNull 语法；无泛型协议/泛型枚举；
- 阻塞方法首参 `Context`；失败用 `Result`；会话/数据集 `close` 幂等；
- 不重复定义 `Tensor`/`Matrix`/`Vector`；
- 不包含模型运行时二进制、ONNX 解析器实现或 GPU 内核；
- 所有相对链接可达；参数命名检查通过；
- 本轮只改 `docs/design/solutions/ml`，未修改 `docs/design/platform/README.md`、`docs/design/README.md`，未改代码/测试/脚本。

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | `@ModelSpec`、`@MlPipeline` |
| 本包消费 | `@Value`、`@Builder`、`@TensorSpec` |
| 处理器 | MlAnnotationProcessor（Validate/Generate） |
| 生成物 | 模型/流水线目录、输入输出 spec |
| 状态 | 领域注解 planned；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| 模型类 | `@ModelSpec` | 模型目录 |
| 流水线类 | `@MlPipeline` | 流水线目录 |
| 输入/输出字段 | `@TensorSpec` | shape/dtype 校验 |

### 声明

```x
@Target(Type)
@Retention(Runtime)
@annotation ModelSpec {
    final String name
}

@Target(Type)
@Retention(Runtime)
@annotation MlPipeline {
    final String name
}
```

声明文件：每个注解单独一个 PascalCase 文件；处理器为构建期类型；生成代码在 `<package>/generated/`。

### 使用

```x
@ModelSpec("sentiment")
class SentimentModel {
    // ...
}

@MlPipeline("batch-infer")
class BatchInference {
    // ...
}
```

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
