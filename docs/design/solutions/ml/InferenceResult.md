# `InferenceResult`

| 项 | 值 |
| --- | --- |
| 类型 | `class InferenceResult` |
| 包 | `xdk.ml` |
| 稳定性 | `preview` |
| 依赖 | `Tensor`、`List`、`Long` |

---

## 1. 定位

一次推理的不可变结果：按模型输出顺序排列的张量、对应输出名和耗时。

只做结果承载与按名/按序读取；不做后处理、解码、阈值过滤、设备拷贝或异步等待。

不做：分类标签、NMS、beam search、tokenizer 解码、置信度校准、结果缓存、跨请求合并。

---

## 2. 设计逻辑

- 用 `class`：需要复制输出列表和名称列表、校验长度/唯一性，并保持顺序合同。
- 输出张量按 [`Model.outputs()`](Model.md) 的顺序排列；`InferenceSession.run` 保证该顺序。
- 名称与张量并行保存，使结果自包含；名称必须唯一且非空。
- `Tensor` 不可变，因此 `outputs()` 返回列表副本即可，张量本身可安全共享。
- `elapsedMillis` 是 `nowMono` 差值，`Long`，非负；时钟回退时由 `InferenceSession` 钳制为 0，本类只接受非负值。
- 结果是值快照，不是资源；无 close；可跨任务共享。
- 不提供 `Map` 形式输出：名称顺序与模型声明一致；按名查找是 O(n) 线性扫描。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_outputs` | `List<Tensor>` | final | 非空；元素非 null；副本 |
| `_outputNames` | `List<String>` | final | 非空；元素非空；唯一；与 outputs 等长 |
| `_elapsedMillis` | `Long` | final | ≥0 |

不变量：两个列表非 null、等长且非空；张量非 null；名称非空且唯一；耗时非负；构造后不可变；列表返回副本。

---

## 4. 生命周期

构造后不可变；无 close；无资源；可跨任务共享；GC 管理张量内存。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `InferenceResult(List<Tensor> outputs, List<String> outputNames, Long elapsedMillis)` | 输出张量、输出名、耗时 | 列表非 null、非空、等长；张量非 null；名称非空且唯一；耗时 ≥0 | 违约 → panic |

构造器复制两个列表；调用方之后修改原列表不影响结果。

---

## 6. 字段表

见 §3；字段私有。不暴露运行时句柄、输出分配器或设备信息。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `outputs` | 输出张量副本 | 无 | `List<Tensor>` | 无 | 张量不可变 |
| `outputNames` | 输出名副本 | 无 | `List<String>` | 无 | 与 outputs 同序 |
| `outputCount` | 输出数 | 无 | `Int` | 无 | ≥1 |
| `output` | 按序号取张量 | `Int outputIndex` | `Tensor` | 越界 → panic | O(1) |
| `output` | 按名取张量 | `String name` | `Tensor?` | null name → panic | 缺失 → null |
| `outputName` | 按序号取名 | `Int outputIndex` | `String` | 越界 → panic | O(1) |
| `elapsedMillis` | 耗时 | 无 | `Long` | 无 | ≥0 |
| `describe` | 单行描述 | 无 | `String` | 无 | 不输出张量内容 |

说明：

- `output(Int)` 与 `output(String)` 是重载；参数类型不同，调用方必须显式。
- `output(String)` 只做精确匹配；空串返回 `null`；不做大小写折叠。
- `outputs()` 返回新列表，元素是共享的不可变 `Tensor`；修改列表不影响结果。
- `outputNames()` 返回新列表；名称顺序与 `Model.outputs()` 一致。
- 不提供 `withOutput`/`map`；后处理应在结果外显式进行。
- 不提供 `equals`；张量值比较容易昂贵，需要时逐张量调用 `Tensor.equals`。

---

## 8. 使用的技术

- 不可变结果快照；
- 并行列表 + 长度/唯一性校验；
- 按序/按名查找；
- `Long` 毫秒耗时；
- 不可变张量共享。

---

## 9. 需要的支撑

- 语言：class、final 字段、List、Int、Long、String、Bool；
- 张量：[`Tensor`](../../platform/tensor/Tensor.md)；
- 运行时：`nowMono` 由调用方（`InferenceSession`）使用，本类只接收耗时；
- 接口：[`ModelOutput`](ModelOutput.md)、[`Model`](Model.md)、[`InferenceSession`](InferenceSession.md)。

---

## 10. 依赖的特性/接口/类

[`Tensor`](../../platform/tensor/Tensor.md)、[`TensorShape`](../../platform/tensor/TensorShape.md)、[`ModelOutput`](ModelOutput.md)、[`Model`](Model.md)、[`InferenceSession`](InferenceSession.md)。

不重复定义张量；不依赖解码器或后处理库。

---

## 11. 所有权与并发

不可变值快照；可共享；`outputs()`/`outputNames()` 返回副本；张量不可变；无资源；无取消点。  
相等：没有 `equals`；`==` 是引用身份；需要比较时逐输出调用 `Tensor.equals`；不推荐作 `Map` 键。

---

## 12. 示例与反例

正确：`InferenceResult result = session.run(context, inputs).value()`；`result.output("logits")` 取主输出；`result.output(0)` 取第一个输出；用 `elapsedMillis()` 记录延迟。  
反例：假设 `output(0)` 一定是分类结果；在结果里原地改张量；用 `outputNames()` 的列表顺序猜模型输出名；把 `elapsedMillis == 0` 当“没有执行”；用空名称查输出；修改返回的列表并期望结果变化。

---

## 13. 测试/场景义务

空 outputs/outputNames panic；长度不等 panic；张量 null panic；名称空串/重复 panic；耗时负值 panic；单输出/多输出；按序/按名/null/缺失/空串；列表复制独立性；`describe` 稳定；多任务共享；结果在会话关闭后仍可读。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
class InferenceResult {
    final List<Tensor> _outputs
    final List<String> _outputNames
    final Long _elapsedMillis

    InferenceResult(List<Tensor> outputs, List<String> outputNames,
                    Long elapsedMillis) {
        if outputs == null || outputNames == null {
            throw "InferenceResult: null output list"
        }
        if outputs.length() == 0 || outputNames.length() == 0 {
            throw "InferenceResult: empty output list"
        }
        if outputs.length() != outputNames.length() {
            throw "InferenceResult: output name count mismatch"
        }
        if elapsedMillis < 0 {
            throw "InferenceResult: negative elapsed time"
        }
        _outputs = outputs.copy()
        _outputNames = outputNames.copy()
        Int outputIndex = 0
        while outputIndex < _outputs.length() {
            if _outputs.get(outputIndex) == null {
                throw "InferenceResult: null output tensor"
            }
            String outputName = _outputNames.get(outputIndex)
            if outputName == null || outputName == "" {
                throw "InferenceResult: empty output name"
            }
            Int scanIndex = outputIndex + 1
            while scanIndex < _outputNames.length() {
                if _outputNames.get(scanIndex) == outputName {
                    throw "InferenceResult: duplicate output name"
                }
                scanIndex = scanIndex + 1
            }
            outputIndex = outputIndex + 1
        }
        _elapsedMillis = elapsedMillis
    }

    List<Tensor> outputs() { return _outputs.copy() }
    List<String> outputNames() { return _outputNames.copy() }
    Int outputCount() { return _outputs.length() }
    Long elapsedMillis() { return _elapsedMillis }

    Tensor output(Int outputIndex) {
        if outputIndex < 0 || outputIndex >= _outputs.length() {
            throw "InferenceResult.output: output index out of range"
        }
        return _outputs.get(outputIndex)
    }

    Tensor? output(String name) {
        if name == null { throw "InferenceResult.output: null name" }
        Int outputIndex = 0
        while outputIndex < _outputNames.length() {
            if _outputNames.get(outputIndex) == name {
                return _outputs.get(outputIndex)
            }
            outputIndex = outputIndex + 1
        }
        return null
    }

    String outputName(Int outputIndex) {
        if outputIndex < 0 || outputIndex >= _outputNames.length() {
            throw "InferenceResult.outputName: output index out of range"
        }
        return _outputNames.get(outputIndex)
    }

    String describe() {
        return "inference outputs=" + str(_outputs.length())
            + " elapsedMs=" + str(_elapsedMillis)
    }
}
```
