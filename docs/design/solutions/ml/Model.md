# `Model`

| 项 | 值 |
| --- | --- |
| 类型 | `class Model` |
| 包 | `xdk.ml` |
| 稳定性 | `preview` |
| 依赖 | `ModelFormat`、`ModelMetadata`、`ModelInput`、`ModelOutput`、`Bytes` |

---

## 1. 定位

模型包描述：容器格式、元数据、输入/输出声明和不透明模型字节。

只做“把模型资产与推理合同放在一起”，不解析容器、不校验图、不加载运行时、不持有会话、不做设备放置。

不做：ONNX/TFLite/TorchScript 解析、图优化、权重解包、格式转换、模型下载、签名校验、内存映射、跨进程共享。

---

## 2. 设计逻辑

- 用 `class`：需要持有较大的不透明 `Bytes`、复制输入/输出列表、校验名称唯一性。
- `_payload` 是“构造时接管所有权”的模型字节：构造器不复制大缓冲区，调用方在构造后不得修改原 `Bytes`；这是为模型体积做的显式例外。
- 不提供公有不透明字节 getter；只提供 `payloadCopy()`，避免调用方改写内部缓冲。`Ml.openSession` 通过包内路径读取。
- 输入/输出声明是推理合同：[`ModelInput`](ModelInput.md) / [`ModelOutput`](ModelOutput.md) 负责 dtype/rank/动态轴，`Model` 只负责列表非空、名称唯一和顺序。
- `Model` 不是资源：没有运行时句柄、没有 close；`InferenceSession` 才拥有运行时资源，并借用 `Model`。
- 同一 `Model` 可创建多个会话；会话关闭不影响 `Model`。
- `payloadLength` 用 `Long` 表达模型体积；底层 `Bytes` 长度仍是 `Int`。
- 不提供 `copy`：复制大模型字节代价高且容易误用；需要独立副本时显式 `payloadCopy()` 后重新构造。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_format` | `ModelFormat` | final | 非 null |
| `_metadata` | `ModelMetadata` | final | 非 null |
| `_inputs` | `List<ModelInput>` | final | 非空；元素非 null；名称唯一；副本 |
| `_outputs` | `List<ModelOutput>` | final | 非空；元素非 null；名称唯一；副本 |
| `_payload` | `Bytes` | final | 非 null；长度 >0；构造时接管 |

不变量：格式/元数据非 null；输入/输出列表非空且元素非 null；各自名称唯一；payload 非空；payload 在构造后不被本包写入；列表私有且返回副本。

---

## 4. 生命周期

构造后不可变（不透明字节按“接管所有权”约定只读）；无 close；无运行时资源；GC 管理内存；可跨任务共享。

`Model` 必须比使用它的 `InferenceSession` 活得久；会话只持有非拥有引用。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Model(ModelFormat modelFormat, ModelMetadata metadata, List<ModelInput> inputs, List<ModelOutput> outputs, Bytes payload)` | 格式、元数据、输入声明、输出声明、模型字节 | 全部非 null；inputs/outputs 非空、元素非 null、名称各自唯一；payload 长度 >0 | 违约 → panic |

`payload` 是所有权接管：构造成功后调用方不得再修改该 `Bytes`。构造器复制输入/输出列表；不复制 payload。

---

## 6. 字段表

见 §3；字段私有。不暴露内部 `Bytes`、图结构、权重布局或运行时句柄。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `format` | 容器格式 | 无 | `ModelFormat` | 无 | O(1) |
| `metadata` | 元数据 | 无 | `ModelMetadata` | 无 | 不可变共享 |
| `inputs` | 输入声明副本 | 无 | `List<ModelInput>` | 无 | O(n) 复制 |
| `outputs` | 输出声明副本 | 无 | `List<ModelOutput>` | 无 | O(n) 复制 |
| `inputCount` | 输入数 | 无 | `Int` | 无 | ≥1 |
| `outputCount` | 输出数 | 无 | `Int` | 无 | ≥1 |
| `input` | 按名查输入 | `String name` | `ModelInput?` | null name → panic | 缺失 → null |
| `output` | 按名查输出 | `String name` | `ModelOutput?` | null name → panic | 缺失 → null |
| `payloadLength` | 模型字节数 | 无 | `Long` | 无 | >0 |
| `payloadCopy` | 模型字节副本 | 无 | `Bytes` | 无 | O(n)；独立副本 |
| `describe` | 单行描述 | 无 | `String` | 无 | 不含 payload 内容 |

说明：

- `input`/`output` 只做精确名称匹配；空串返回 `null`；不做大小写折叠或别名。
- 输入名与输出名允许重叠；两个查找入口分别只查各自列表。
- `payloadCopy` 返回独立 `Bytes`，调用方可修改副本，不影响模型。
- 不提供 `payload` 借用 getter；需要把模型交给外部运行时由 `Ml.openSession` 完成。
- 不提供 `withMetadata`/`withInputs`；变更时重新构造 `Model`。
- 不提供 `equals`/`copy`；模型身份由引用 + 元数据描述表达。

---

## 8. 使用的技术

- 所有权接管的大字节缓冲；
- 列表复制与名称唯一性校验；
- 不可变描述对象；
- 不透明 payload 封装；
- 名称查找。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Int、Long、List、Bool；
- 运行时：`Bytes` 长度/复制；
- 接口：[`ModelFormat`](ModelFormat.md)、[`ModelMetadata`](ModelMetadata.md)、[`ModelInput`](ModelInput.md)、[`ModelOutput`](ModelOutput.md)、[`InferenceSession`](InferenceSession.md)、[`Ml`](Ml.md)。

---

## 10. 依赖的特性/接口/类

[`ModelFormat`](ModelFormat.md)、[`ModelMetadata`](ModelMetadata.md)、[`ModelInput`](ModelInput.md)、[`ModelOutput`](ModelOutput.md)、[`InferenceSession`](InferenceSession.md)、[`Ml`](Ml.md)、[`Bytes`](../../core/bytes/Bytes.md)。

不依赖解析器、模型运行时、`xdk.fs` 或 `xdk.io`。

---

## 11. 所有权与并发

引用语义；`Model` 不可变；payload 由构造器接管并只读；`inputs`/`outputs` 返回副本；`payloadCopy` 返回新缓冲。  
可跨任务共享；可被多个会话借用；无 close；无取消点。  
相等：`==` 是引用身份；没有 `equals`；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：先构造 `ModelFormat`、`ModelMetadata`、`ModelInput`/`ModelOutput`，再构造 `Model`；同一模型打开两个不同 `SessionOptions` 的会话；模型字节只通过 `payloadCopy` 导出。  
反例：构造后继续修改传入的 `payload`；把 `Model` 当已打开会话；期望 `Model` 自动解析 ONNX；用空 payload 表示“仅图”；用输入名重叠猜输出；在多个会话之间共享可变 payload；把 `Model` 当 `Map` 键。

---

## 13. 测试/场景义务

格式/元数据 null panic；输入/输出空列表 panic；元素 null panic；输入名重复 panic；输出名重复 panic；payload null/空 panic；payload 接管后不复制但只读；列表复制独立性；`input`/`output` 命中/缺失/null/空串；`inputCount`/`outputCount`；`payloadLength`；`payloadCopy` 独立；多会话共享；`describe` 稳定。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class Model {
    final ModelFormat _format
    final ModelMetadata _metadata
    final List<ModelInput> _inputs
    final List<ModelOutput> _outputs
    final Bytes _payload

    Model(ModelFormat modelFormat, ModelMetadata metadata,
          List<ModelInput> inputs, List<ModelOutput> outputs, Bytes payload) {
        if modelFormat == null || metadata == null {
            throw "Model: null format or metadata"
        }
        if inputs == null || outputs == null || payload == null {
            throw "Model: null input, output, or payload"
        }
        if inputs.length() == 0 || outputs.length() == 0 {
            throw "Model: empty input or output list"
        }
        if payload.length() == 0 {
            throw "Model: empty payload"
        }
        _inputs = inputs.copy()
        _outputs = outputs.copy()
        List<String> inputNames = []
        Int inputIndex = 0
        while inputIndex < _inputs.length() {
            ModelInput modelInput = _inputs.get(inputIndex)
            if modelInput == null {
                throw "Model: null input"
            }
            Int scanIndex = 0
            while scanIndex < inputNames.length() {
                if inputNames.get(scanIndex) == modelInput.name() {
                    throw "Model: duplicate input name"
                }
                scanIndex = scanIndex + 1
            }
            inputNames.push(modelInput.name())
            inputIndex = inputIndex + 1
        }
        List<String> outputNames = []
        Int outputIndex = 0
        while outputIndex < _outputs.length() {
            ModelOutput modelOutput = _outputs.get(outputIndex)
            if modelOutput == null {
                throw "Model: null output"
            }
            Int scanIndex = 0
            while scanIndex < outputNames.length() {
                if outputNames.get(scanIndex) == modelOutput.name() {
                    throw "Model: duplicate output name"
                }
                scanIndex = scanIndex + 1
            }
            outputNames.push(modelOutput.name())
            outputIndex = outputIndex + 1
        }
        _format = modelFormat
        _metadata = metadata
        _payload = payload
    }

    ModelFormat format() { return _format }
    ModelMetadata metadata() { return _metadata }
    List<ModelInput> inputs() { return _inputs.copy() }
    List<ModelOutput> outputs() { return _outputs.copy() }
    Int inputCount() { return _inputs.length() }
    Int outputCount() { return _outputs.length() }

    ModelInput? input(String name) {
        if name == null { throw "Model.input: null name" }
        Int inputIndex = 0
        while inputIndex < _inputs.length() {
            if _inputs.get(inputIndex).name() == name {
                return _inputs.get(inputIndex)
            }
            inputIndex = inputIndex + 1
        }
        return null
    }

    ModelOutput? output(String name) {
        if name == null { throw "Model.output: null name" }
        Int outputIndex = 0
        while outputIndex < _outputs.length() {
            if _outputs.get(outputIndex).name() == name {
                return _outputs.get(outputIndex)
            }
            outputIndex = outputIndex + 1
        }
        return null
    }

    Long payloadLength() { return _payload.length() as Long }

    Bytes payloadCopy() { return copy(_payload) }

    String describe() {
        return "model format=" + modelFormatName(_format)
            + " name=" + _metadata.name()
            + " inputs=" + str(_inputs.length())
            + " outputs=" + str(_outputs.length())
            + " bytes=" + str(self.payloadLength())
    }
}
```
