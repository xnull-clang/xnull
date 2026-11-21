# `InferenceSession`

| 项 | 值 |
| --- | --- |
| 类型 | `class InferenceSession` |
| 包 | `xdk.ml` |
| 稳定性 | `preview` |
| 依赖 | `Model`、`SessionOptions`、`ExecutionProvider`、`InferenceResult`、`Context`、`Error` |

---

## 1. 定位

已打开的推理会话：持有运行时句柄，接收按模型输入顺序排列的 `List<Tensor>`，返回 `InferenceResult`，并负责幂等关闭。

只做会话生命周期、输入合同校验、调用注入的运行时原语、输出合同校验和耗时统计。不做模型解析、图优化实现、算子内核、设备分配、批调度、异步队列、缓存或指标导出。

---

## 2. 设计逻辑

- 用 `class`：拥有不透明运行时句柄，必须 `close`；不是值对象。
- `_handle` 是 `Long` 不透明句柄，不暴露原生 session 指针/地址；`>0` 是唯一合法域。
- 构造器内部使用：业务代码通过 [`Ml.openSession`](Ml.md) 创建；构造器只接收已打开句柄，便于宿主/测试。
- `_model` 与 `_sessionOptions` 是非拥有引用；会话不关闭/复制它们；`Model` 必须比会话活得久。
- `run` 的位置合同：第 `i` 个张量对应 `model.inputs().get(i)`；数量、dtype、rank、固定维度不匹配返回 `InvalidArgument`；动态维度接受任意非负长度。
- 提供者顺序来自 `SessionOptions.providers()`；会话不重新排序、不自动探测设备。
- `run` 调用宿主注入的 `mlSessionRunRaw`；适配器必须实现格式解析、图执行、提供者选择与设备管理。本包不链接任何模型运行时。
- 输出在返回前逐个用 `model.outputs().get(i).accepts` 校验；数量/声明不匹配视为适配器违约，返回 `DataCorrupted`。
- 耗时用 `nowMono()` 包裹原生调用；负差值钳制为 0，保证 `InferenceResult.elapsedMillis` 非负。
- `close` 标记关闭后调用一次原生关闭；失败作为诊断返回，但对象保持 closed；重复 close 返回 `Ok(unit)`。
- 会话可并发 `run`，前提是适配器线程安全；`close` 不得与 `run` 并发。没有全局会话注册表。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_handle` | `Long` | final | >0；不透明运行时句柄 |
| `_model` | `Model` | final | 非 null；非拥有引用 |
| `_sessionOptions` | `SessionOptions` | final | 非 null；不可变配置 |
| `_open` | `Bool` | 内部 | 构造后 true；close 后 false |

不变量：handle >0；model/options 非 null；options.providers 非空；model 的输入/输出声明非空；open 与生命周期一致；close 幂等；关闭后不再调用原生 run 原语。

---

## 4. 生命周期

由 `Ml.openSession(context, model, sessionOptions)` 创建；调用方拥有并必须 `close()`；close 幂等；无 `deinit` 依赖。

关闭后：

- `model()`、`sessionOptions()`、`providers()`、`inputCount()`、`outputCount()`、`isOpen()` 仍可读；
- `run` 返回 `Unavailable`；
- `close` 返回 `Ok(unit)`。

`Model` 必须先于会话创建，并在会话使用期间保持存活。会话不拥有 `Model` 的 payload。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `InferenceSession(Long handle, Model model, SessionOptions sessionOptions)` | 句柄、模型、选项 | handle >0；model/options 非 null；options.providers 非空 | 违约 → panic |

构造器仅供宿主/测试；业务代码使用 `Ml.openSession`。工厂在原生句柄 ≤0 时返回 `Internal`，不把非法句柄传给构造器。

---

## 6. 字段表

见 §3；字段私有。不暴露原生 session 句柄、分配器、设备指针或提供者内部状态。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `model` | 借用的模型 | 无 | `Model` | 无 | 非拥有 |
| `sessionOptions` | 会话配置 | 无 | `SessionOptions` | 无 | 不可变共享 |
| `providers` | 提供者优先级副本 | 无 | `List<ExecutionProvider>` | 无 | 委托 options |
| `inputCount` | 输入数 | 无 | `Int` | 无 | 委托 model |
| `outputCount` | 输出数 | 无 | `Int` | 无 | 委托 model |
| `run` | 执行一次推理 | `Context context, List<Tensor> inputs` | `Result<InferenceResult, Error>` | `InvalidArgument`/`Unavailable`/`Cancelled`/`DataCorrupted`/适配器错误 | 阻塞；可并发（适配器保证） |
| `close` | 关闭会话 | 无 | `Result<Unit, Error>` | `Io`（诊断） | 幂等 |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 | O(1) |
| `describe` | 单行描述 | 无 | `String` | 无 | 不含张量内容 |

说明：

- `run`：`context == null` 或 `inputs == null` → panic；输入数量不符 → `InvalidArgument`；任一输入不满足 `ModelInput.accepts` → `InvalidArgument`；关闭 → `Unavailable`；取消 → `Cancelled`。
- `run` 不修改输入张量；输入列表只借用；结果持有独立列表快照，张量不可变。
- `run` 成功返回 `InferenceResult`，其输出顺序与 `model.outputs()` 一致；输出名来自模型声明。
- `run` 的原生失败原样传播；适配器返回 `Cancelled` 时保留；取消后即使适配器返回张量，会话也丢弃结果并返回 `Cancelled`。
- 输出列表为 null、输出数量不符、dtype/rank/固定维不匹配 → `DataCorrupted`；动态维不检查长度。
- `close`：第一次调用标记 `_open=false`，再调用 `mlSessionCloseRaw`；原生关闭失败只作为 `Io` 诊断返回，不改变 closed 状态；后续调用返回 `Ok(unit)`。
- `model()`/`sessionOptions()` 返回不可变共享引用，调用方不得关闭它们（它们没有 close）。
- 不提供 `handle()`/`runAsync`/`runBatch`/`warmup`；批处理由调用方多次 `run` 或自定义调度完成。
- 不提供 `equals`/`copy`；会话是资源。

---

## 8. 使用的技术

- 不透明 `Long` 句柄；
- 输入/输出合同校验；
- 动态维度匹配；
- `Context`/`Result`；
- 单调时钟耗时；
- 幂等关闭；
- 运行时原语注入。

---

## 9. 需要的支撑

- 语言：class、final 字段、Long、Int、Bool、List、Result；
- 运行时/适配器（由宿主注入，不在本包实现）：
  - `mlSessionCreateRaw(Context context, ModelFormat modelFormat, ModelMetadata metadata, List<ModelInput> inputs, List<ModelOutput> outputs, Bytes payload, SessionOptions sessionOptions) -> Result<Long, Error>`；
  - `mlSessionRunRaw(Context context, Long sessionHandle, List<Tensor> inputs) -> Result<List<Tensor>, Error>`；
  - `mlSessionCloseRaw(Long sessionHandle) -> Result<Unit, Error>`；
  - `nowMono() -> Long`；
- 原生会话句柄必须 >0；0/负数由工厂映射为 `Internal`；
- `mlSessionCreateRaw` 必须在返回前完成模型解析或自行复制 `payload`，不得在返回后保留传入 `Bytes` 的引用；
- 接口：`Context`、`Error`、`BasicError`、`ErrorKind`、`unavailableError`、`cancelledError`、`Model`、`SessionOptions`、`ExecutionProvider`、`InferenceResult`、`Tensor`。

---

## 10. 依赖的特性/接口/类

[`Model`](Model.md)、[`ModelInput`](ModelInput.md)、[`ModelOutput`](ModelOutput.md)、[`SessionOptions`](SessionOptions.md)、[`ExecutionProvider`](ExecutionProvider.md)、[`InferenceResult`](InferenceResult.md)、[`Ml`](Ml.md)、[`Tensor`](../../platform/tensor/Tensor.md)、`Context`、`Error`。

不依赖 ONNX Runtime、TensorFlow Lite、PyTorch、CUDA/ROCm/DirectML/OpenVINO 头文件。

---

## 11. 所有权与并发

引用语义；会话由调用方拥有；`model`/`sessionOptions` 是非拥有引用；`run` 返回新结果；`close` 释放原生句柄。

`run` 可并发调用，前提是适配器线程安全；`close` 必须等待所有在途 `run` 完成。`isOpen` 可并发读取，但并发 close 与 run 的竞态由调用方避免。

无 `equals`/`copy`；`==` 是引用身份；不推荐作 `Map` 键；关闭后不得再 `run`。

---

## 12. 示例与反例

正确：`Result<InferenceSession, Error> opened = Ml.openSession(context, model, options); InferenceSession session = opened.value(); Result<InferenceResult, Error> result = session.run(context, inputs); session.close()`；输入顺序严格按 `model.inputs()`；输出按 `result.output("logits")` 或 `result.output(0)` 读取。  
反例：关闭后继续 `run`；用输入名称排序代替声明顺序；把动态维度当固定维度；忽略 `run` 的 `InvalidArgument`；在 `close` 同时并发 `run`；把会话当模型缓存；把原生句柄传出包外；认为 `run` 会自动做预处理。

---

## 13. 测试/场景义务

打开/关闭；`model`/`sessionOptions`/`providers`；输入数量不符；dtype/rank/固定维不匹配；动态维变化；关闭后 `run` 返回 `Unavailable`；取消 `Cancelled`；适配器错误传播；输出数量/声明不匹配 `DataCorrupted`；耗时非负；close 幂等；close 失败后仍 closed；并发 `run`（适配器支持时）；`Model` 在会话关闭后仍可读；null context/inputs panic。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class InferenceSession {
    final Long _handle
    final Model _model
    final SessionOptions _sessionOptions
    Bool _open

    InferenceSession(Long handle, Model model,
                     SessionOptions sessionOptions) {
        if handle == null || handle <= 0 {
            throw "InferenceSession: invalid handle"
        }
        if model == null || sessionOptions == null {
            throw "InferenceSession: null model or options"
        }
        _handle = handle
        _model = model
        _sessionOptions = sessionOptions
        _open = true
    }

    Model model() { return _model }
    SessionOptions sessionOptions() { return _sessionOptions }
    List<ExecutionProvider> providers() {
        return _sessionOptions.providers()
    }
    Int inputCount() { return _model.inputCount() }
    Int outputCount() { return _model.outputCount() }
    Bool isOpen() { return _open }

    Result<InferenceResult, Error> run(Context context,
                                       List<Tensor> inputs) {
        if context == null { throw "InferenceSession.run: null context" }
        if inputs == null { throw "InferenceSession.run: null inputs" }
        if !_open { return Err(unavailableError("inference session")) }
        if inputs.length() != _model.inputCount() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "input count mismatch"))
        }
        List<ModelInput> modelInputs = _model.inputs()
        Int inputIndex = 0
        while inputIndex < modelInputs.length() {
            if !modelInputs.get(inputIndex).accepts(inputs.get(inputIndex)) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "input contract mismatch"))
            }
            inputIndex = inputIndex + 1
        }
        if context.isCancelled() {
            return Err(cancelledError("inference session run"))
        }
        Long startedMillis = nowMono()
        Result<List<Tensor>, Error> rawResult =
            mlSessionRunRaw(context, _handle, inputs)
        if rawResult.isErr() {
            return Err(rawResult.error())
        }
        Long elapsedMillis = nowMono() - startedMillis
        if elapsedMillis < 0 {
            elapsedMillis = 0
        }
        if context.isCancelled() {
            return Err(cancelledError("inference session run"))
        }
        List<Tensor> outputs = rawResult.value()
        if outputs == null {
            return Err(new BasicError(ErrorKind.DataCorrupted,
                "null output list"))
        }
        if outputs.length() != _model.outputCount() {
            return Err(new BasicError(ErrorKind.DataCorrupted,
                "output count mismatch"))
        }
        List<ModelOutput> modelOutputs = _model.outputs()
        List<String> outputNames = []
        Int outputIndex = 0
        while outputIndex < outputs.length() {
            if !modelOutputs.get(outputIndex).accepts(outputs.get(outputIndex)) {
                return Err(new BasicError(ErrorKind.DataCorrupted,
                    "output contract mismatch"))
            }
            outputNames.push(modelOutputs.get(outputIndex).name())
            outputIndex = outputIndex + 1
        }
        return Ok(new InferenceResult(outputs, outputNames, elapsedMillis))
    }

    Result<Unit, Error> close() {
        if !_open { return Ok(unit) }
        _open = false
        return mlSessionCloseRaw(_handle)
    }

    String describe() {
        return "inference session model=" + _model.metadata().name()
            + " open=" + str(_open)
            + " providers=" + str(_sessionOptions.providers().length())
    }
}
```
