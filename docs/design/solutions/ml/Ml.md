# `Ml`

| 项 | 值 |
| --- | --- |
| 类型 | `class Ml`（静态入口） |
| 包 | `xdk.ml` |
| 稳定性 | `preview` |
| 依赖 | `Model`、`SessionOptions`、`InferenceSession`、`LossKind`、`Tensor` |

---

## 1. 定位

`xdk.ml` 的静态门面：打开推理会话、执行一次推理、计算前向标量损失。

只做薄编排：调用注入的运行时原语、委托会话、分派损失计算。不创建模型、不解析容器、不训练、不管理全局会话/提供者。

不做：模型加载/解析、自动微分、参数更新、训练循环、数据加载、设备枚举、全局注册表、缓存。

---

## 2. 设计逻辑

- 无实例状态；私有构造器禁止 `new Ml()`；全部方法为静态。
- `openSession` 是唯一会话创建入口：把 `ModelFormat`、元数据、输入/输出声明、payload 和 `SessionOptions` 交给宿主注入的 `mlSessionCreateRaw`；本包不链接运行时。
- 运行时适配器由宿主按格式注入到原语；`Ml` 不查全局注册表，也不选择“默认运行时”。
- `run` 只委托 `InferenceSession.run`，保证输入/输出合同、取消和关闭语义集中在一处。
- `computeLoss` 是纯前向数值函数：返回标量 `Tensor`，不返回梯度；反向传播是 X，不在本类伪造。
- 损失分派显式：回归损失逐元素平均；BCE 逐元素平均；CE/NLL 按类别样本平均；`Other` 返回 `Unsupported`。
- 损失输入非有限/形状不符返回 `InvalidArgument`；计算溢出等内部不一致返回 `Internal`；取消返回 `Cancelled`。
- 不提供 `createTrainer`/`fit`/`step`；训练抽象见 [`Trainer`](Trainer.md)，基线无实现。
- `openSession` 会调用 `model.payloadCopy()` 取模型字节；大模型复制是基线限制，X 再引入流式/内存映射。

---

## 3. 表示与不变量

无实例字段；类不可实例化。

不变量：

- 所有方法不修改输入；
- 返回的会话/结果是新对象；输入张量只读；
- `openSession` 成功时句柄 >0；
- `computeLoss` 成功时返回 0 维浮点 `Tensor`，dtype 与预测一致；
- 不缓存会话、不持有全局提供者、不创建全局默认配置。

---

## 4. 生命周期

类本身无生命周期；静态调用；无 close；无资源；无取消点（方法内部按 `Context` 取消）。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Ml()` | 无 | 私有；禁止外部实例化 | 外部 `new` 不可用 |

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `openSession` | 打开推理会话 | `Context context, Model model, SessionOptions sessionOptions` | `Result<InferenceSession, Error>` | `InvalidArgument`/`Unsupported`/`Unavailable`/`Cancelled`/`OutOfMemory`/`DataCorrupted`/`Internal` | 阻塞；适配器注入 |
| `run` | 执行一次推理 | `Context context, InferenceSession session, List<Tensor> inputs` | `Result<InferenceResult, Error>` | 同 `InferenceSession.run` | 委托 |
| `computeLoss` | 计算前向标量损失 | `Context context, LossKind lossKind, Tensor predictions, Tensor targets` | `Result<Tensor, Error>` | `InvalidArgument`/`Unsupported`/`Cancelled`/`Internal` | 不产生梯度 |

说明：

- `openSession`：null 参数 → panic；取消 → `Cancelled`；格式/提供者/算子不支持 → `Unsupported`；模型字节损坏 → `DataCorrupted`；句柄 ≤0 → `Internal`。成功后调用方拥有会话并必须 `close`。
- `run`：null context/session/inputs → panic；其余委托 `session.run`；不重复做输入合同校验。
- `computeLoss`：null 参数 → panic；`Other` → `Unsupported`；空张量/形状不符/非有限输入 → `InvalidArgument`；结果非有限 → `Internal`；取消 → `Cancelled`。
- `computeLoss` 的 `predictions` 必须是 `Float32`/`Float64`；回归目标同 dtype；分类目标必须是 `Int32`/`Int64`。
- `computeLoss` 的 BCE 对 `p == 0`/`p == 1` 使用固定内部裁剪 `[1e-7, 1-1e-7]` 避免 `log(0)`；调用方仍应传概率。
- `computeLoss` 的 CE 接收 logits 并做稳定 log-sum-exp；NLL 接收对数概率，不再做 softmax。
- `openSession` 不校验 `ModelMetadata` 与 payload 的语义一致性；适配器负责。
- 不提供 `describeProvider`/`providerFromName`；这些顶层函数属于 `ExecutionProvider` 文档。
- 不提供 `closeSession`；调用 `InferenceSession.close`。

---

## 8. 使用的技术

- 静态门面；
- 运行时原语委托；
- 会话工厂；
- 损失分派；
- 稳定 log-sum-exp；
- `Context` 取消；
- `Result` 错误映射；
- 无全局状态。

---

## 9. 需要的支撑

- 语言：class、静态方法、私有构造器、List、Int、Long、Double、Bool、Result；
- 运行时/适配器（宿主注入）：
  - `mlSessionCreateRaw(Context context, ModelFormat modelFormat, ModelMetadata metadata, List<ModelInput> inputs, List<ModelOutput> outputs, Bytes payload, SessionOptions sessionOptions) -> Result<Long, Error>`；
  - `mlSessionCreateRaw` 必须在返回前完成解析或自行复制 `payload`，不得保留传入 `Bytes` 引用；
  - `mlSessionRunRaw`/`mlSessionCloseRaw` 由 [`InferenceSession`](InferenceSession.md) 使用；
- 数学：`isFinite`、`abs`、`exp`、`log`；
- 张量：`TensorOps.fromDoubles`、`TensorShape`、`TensorDType`；
- 错误：`BasicError`、`ErrorKind`、`cancelledError`；
- 接口：`Context`、`Model`、`ModelFormat`、`ModelMetadata`、`ModelInput`、`ModelOutput`、`SessionOptions`、`InferenceSession`、`InferenceResult`、`LossKind`、`Tensor`、`Bytes`。

---

## 10. 依赖的特性/接口/类

[`Model`](Model.md)、[`ModelFormat`](ModelFormat.md)、[`ModelMetadata`](ModelMetadata.md)、[`ModelInput`](ModelInput.md)、[`ModelOutput`](ModelOutput.md)、[`SessionOptions`](SessionOptions.md)、[`InferenceSession`](InferenceSession.md)、[`InferenceResult`](InferenceResult.md)、[`LossKind`](LossKind.md)、[`Tensor`](../../platform/tensor/Tensor.md)、[`TensorOps`](../../platform/tensor/TensorOps.md)、[`TensorShape`](../../platform/tensor/TensorShape.md)、[`TensorDType`](../../platform/tensor/TensorDType.md)、`Context`、`Error`、`Bytes`。

不依赖解析器、模型运行时、自动微分引擎、PyTorch/TensorFlow/ONNX Runtime 头文件。

---

## 11. 所有权与并发

静态；无共享可变状态；输入只读；`openSession` 返回调用方拥有的会话；`run` 返回调用方拥有的结果；损失返回新张量。

可并发调用（无全局状态）；每个会话的并发语义由 `InferenceSession`/适配器决定。无 close；方法内部按 `Context` 检查取消。

相等：类不可实例化，无实例相等语义。

---

## 12. 示例与反例

正确：`Result<InferenceSession, Error> opened = Ml.openSession(context, model, SessionOptions.defaults())`；`Ml.run(context, session, inputs)`；`Ml.computeLoss(context, LossKind.CrossEntropy, logits, classTargets)` 得到标量损失并交给 X 反向引擎。  
反例：期望 `Ml.computeLoss` 返回梯度；把 `Ml.openSession` 当模型解析器；在 `Other` 损失上期望数值；用空 payload 打开会话；让 `Ml` 维护全局默认会话；在没有适配器时把 `Unsupported` 当成功；把 `run` 的输入顺序按名称排序。

---

## 13. 测试/场景义务

`openSession` 成功/格式不支持/提供者不支持/取消/句柄 ≤0/空 payload；`run` 委托一致性；`computeLoss` 五种损失的正常/空张量/形状不符/非有限/目标越界/取消；`Other` → `Unsupported`；标量输出 dtype/形状；BCE 0/1 裁剪；CE 数值稳定；NLL 对数概率；null 参数 panic；并发静态调用；无全局状态。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class Ml {
    private Ml() {}

    static Result<InferenceSession, Error> openSession(
            Context context, Model model, SessionOptions sessionOptions) {
        if context == null || model == null || sessionOptions == null {
            throw "Ml.openSession: null argument"
        }
        if context.isCancelled() {
            return Err(cancelledError("ml open session"))
        }
        Bytes payload = model.payloadCopy()
        Result<Long, Error> created = mlSessionCreateRaw(
            context, model.format(), model.metadata(), model.inputs(),
            model.outputs(), payload, sessionOptions)
        if created.isErr() {
            return Err(created.error())
        }
        Long handle = created.value()
        if handle == null || handle <= 0 {
            return Err(new BasicError(ErrorKind.Internal,
                "invalid session handle"))
        }
        return Ok(new InferenceSession(handle, model, sessionOptions))
    }

    static Result<InferenceResult, Error> run(
            Context context, InferenceSession session, List<Tensor> inputs) {
        if context == null || session == null || inputs == null {
            throw "Ml.run: null argument"
        }
        return session.run(context, inputs)
    }

    static Result<Tensor, Error> computeLoss(
            Context context, LossKind lossKind, Tensor predictions,
            Tensor targets) {
        if context == null || lossKind == null {
            throw "Ml.computeLoss: null context or loss kind"
        }
        if predictions == null || targets == null {
            throw "Ml.computeLoss: null tensor"
        }
        if context.isCancelled() {
            return Err(cancelledError("ml compute loss"))
        }
        if lossKind == LossKind.MeanSquaredError
                || lossKind == LossKind.MeanAbsoluteError {
            return Ml.computeElementwiseLoss(context, lossKind,
                predictions, targets)
        }
        if lossKind == LossKind.BinaryCrossEntropy {
            return Ml.computeBinaryCrossEntropy(context, predictions, targets)
        }
        if lossKind == LossKind.CrossEntropy {
            return Ml.computeClassLoss(context, predictions, targets, false)
        }
        if lossKind == LossKind.NegativeLogLikelihood {
            return Ml.computeClassLoss(context, predictions, targets, true)
        }
        return Err(new BasicError(ErrorKind.Unsupported,
            "unsupported loss kind"))
    }

    static Result<Tensor, Error> computeElementwiseLoss(
            Context context, LossKind lossKind, Tensor predictions,
            Tensor targets) {
        if predictions.tensorDType() != targets.tensorDType() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "loss dtype mismatch"))
        }
        if !tensorDTypeIsFloatingPoint(predictions.tensorDType()) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "loss requires floating point"))
        }
        if !predictions.tensorShape().equals(targets.tensorShape()) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "loss shape mismatch"))
        }
        Long elementCount = predictions.elementCount()
        if elementCount == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "loss on empty tensor"))
        }
        Double total = 0.0
        Long elementIndex = 0
        while elementIndex < elementCount {
            if elementIndex % 4096 == 0 && context.isCancelled() {
                return Err(cancelledError("ml elementwise loss"))
            }
            Double predictionValue = predictions.atFlat(elementIndex)
            Double targetValue = targets.atFlat(elementIndex)
            if !isFinite(predictionValue) || !isFinite(targetValue) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "non-finite loss input"))
            }
            Double difference = predictionValue - targetValue
            if lossKind == LossKind.MeanSquaredError {
                total = total + difference * difference
            } else {
                total = total + abs(difference)
            }
            elementIndex = elementIndex + 1
        }
        Double mean = total / (elementCount as Double)
        if !isFinite(mean) {
            return Err(new BasicError(ErrorKind.Internal,
                "non-finite loss result"))
        }
        return Ok(TensorOps.fromDoubles(predictions.tensorDType(),
            new TensorShape([]), [mean]))
    }

    static Result<Tensor, Error> computeBinaryCrossEntropy(
            Context context, Tensor predictions, Tensor targets) {
        if predictions.tensorDType() != targets.tensorDType() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "bce dtype mismatch"))
        }
        if !tensorDTypeIsFloatingPoint(predictions.tensorDType()) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "bce requires floating point"))
        }
        if !predictions.tensorShape().equals(targets.tensorShape()) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "bce shape mismatch"))
        }
        Long elementCount = predictions.elementCount()
        if elementCount == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "bce on empty tensor"))
        }
        Double total = 0.0
        Long elementIndex = 0
        while elementIndex < elementCount {
            if elementIndex % 4096 == 0 && context.isCancelled() {
                return Err(cancelledError("ml binary cross entropy"))
            }
            Double probability = predictions.atFlat(elementIndex)
            Double targetValue = targets.atFlat(elementIndex)
            if !isFinite(probability) || !isFinite(targetValue) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "non-finite bce input"))
            }
            if probability < 0.0 || probability > 1.0 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "bce probability out of range"))
            }
            if targetValue != 0.0 && targetValue != 1.0 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "bce target must be 0 or 1"))
            }
            Double clipped = probability
            if clipped < 0.0000001 {
                clipped = 0.0000001
            }
            if clipped > 0.9999999 {
                clipped = 0.9999999
            }
            Double positiveTerm = targetValue * log(clipped)
            Double negativeTerm = (1.0 - targetValue) * log(1.0 - clipped)
            total = total - (positiveTerm + negativeTerm)
            elementIndex = elementIndex + 1
        }
        Double mean = total / (elementCount as Double)
        if !isFinite(mean) {
            return Err(new BasicError(ErrorKind.Internal,
                "non-finite bce result"))
        }
        return Ok(TensorOps.fromDoubles(predictions.tensorDType(),
            new TensorShape([]), [mean]))
    }

    static Result<Tensor, Error> computeClassLoss(
            Context context, Tensor predictions, Tensor targets,
            Bool useLogProbabilities) {
        if predictions.rank() != 2 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "class loss requires rank 2 predictions"))
        }
        if targets.rank() != 1 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "class loss requires rank 1 targets"))
        }
        if !tensorDTypeIsFloatingPoint(predictions.tensorDType()) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "class loss requires floating point predictions"))
        }
        if !tensorDTypeIsInteger(targets.tensorDType()) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "class loss requires integer targets"))
        }
        Int batchCount = predictions.tensorShape().dim(0)
        Int classCount = predictions.tensorShape().dim(1)
        if batchCount == 0 || classCount == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "class loss on empty tensor"))
        }
        if targets.tensorShape().dim(0) != batchCount {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "class target count mismatch"))
        }
        Double total = 0.0
        Int sampleIndex = 0
        while sampleIndex < batchCount {
            if context.isCancelled() {
                return Err(cancelledError("ml class loss"))
            }
            Long targetIndex = targets.atFlatLong(sampleIndex as Long)
            if targetIndex < 0 || targetIndex >= (classCount as Long) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "class target out of range"))
            }
            Long rowOffset = (sampleIndex as Long) * (classCount as Long)
            Double sampleLoss = 0.0
            if useLogProbabilities {
                Double logProbability = predictions.atFlat(
                    rowOffset + targetIndex)
                if !isFinite(logProbability) {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "non-finite log probability"))
                }
                sampleLoss = -logProbability
            } else {
                Double maximumLogit = predictions.atFlat(rowOffset)
                if !isFinite(maximumLogit) {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "non-finite logit"))
                }
                Int classIndex = 1
                while classIndex < classCount {
                    Double logit = predictions.atFlat(
                        rowOffset + (classIndex as Long))
                    if !isFinite(logit) {
                        return Err(new BasicError(ErrorKind.InvalidArgument,
                            "non-finite logit"))
                    }
                    if logit > maximumLogit {
                        maximumLogit = logit
                    }
                    classIndex = classIndex + 1
                }
                Double sumExp = 0.0
                classIndex = 0
                while classIndex < classCount {
                    sumExp = sumExp + exp(predictions.atFlat(
                        rowOffset + (classIndex as Long)) - maximumLogit)
                    classIndex = classIndex + 1
                }
                Double logSumExp = maximumLogit + log(sumExp)
                Double targetLogit = predictions.atFlat(
                    rowOffset + targetIndex)
                if !isFinite(targetLogit) {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "non-finite target logit"))
                }
                sampleLoss = logSumExp - targetLogit
            }
            if !isFinite(sampleLoss) {
                return Err(new BasicError(ErrorKind.Internal,
                    "non-finite class loss"))
            }
            total = total + sampleLoss
            sampleIndex = sampleIndex + 1
        }
        Double mean = total / (batchCount as Double)
        if !isFinite(mean) {
            return Err(new BasicError(ErrorKind.Internal,
                "non-finite class loss result"))
        }
        return Ok(TensorOps.fromDoubles(predictions.tensorDType(),
            new TensorShape([]), [mean]))
    }
}
```
