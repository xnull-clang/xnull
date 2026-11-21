# `ModelFormat`

| 项 | 值 |
| --- | --- |
| 类型 | `enum ModelFormat` |
| 包 | `xdk.ml` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

模型容器格式家族：ONNX、TensorFlow Lite、TorchScript、适配器自定义。

只说明“模型字节按哪类容器解释”，不承诺本包能解析、校验或执行该格式。解析器、运行时和算子内核都由宿主注入的运行时适配器提供。

不做：格式探测（按扩展名/魔数猜测）、ONNX/TFLite/TorchScript 解析、算子覆盖判断、版本兼容性判断、模型转换、量化。

---

## 2. 设计逻辑

- 格式必须显式：`Model` 构造时由调用方声明，`Ml.openSession` 把格式交给运行时适配器，不做自动探测。
- 枚举只列基线能命名的容器；厂商私有格式用 `Other`，由适配器解释。
- 格式与执行提供者正交：ONNX 可以跑 CPU/CUDA/OpenVINO，TFLite 可以跑 CPU/NPU/DSP，TorchScript 可以跑 CPU/CUDA。
- `Other` 是合法值，不是错误；它要求调用方保证适配器理解该容器。
- 成员只允许追加，不允许改义/删除；序号固定。
- 名称是交换/日志合同；解析只接受稳定名，不做模糊匹配。

---

## 3. 表示与不变量

| 成员 | 序号 | 稳定名 | 典型载体 | 边界 |
| --- | ---: | --- | --- | --- |
| `Onnx` | 0 | `"onnx"` | `.onnx` | 只表示 ONNX 容器，不代表本包解析 ONNX |
| `TensorFlowLite` | 1 | `"tflite"` | `.tflite` FlatBuffer | 只表示 TFLite 容器，不代表本包解析 FlatBuffer |
| `TorchScript` | 2 | `"torchscript"` | TorchScript archive | 只表示 TorchScript 容器，不代表本包加载 Torch |
| `Other` | 3 | `"other"` | 适配器定义 | 语义由适配器与调用方约定 |

不变量：成员固定；序号 0..3 固定；稳定名唯一；`Other` 合法；格式不隐含执行提供者、模型任务或数据布局。

---

## 4. 生命周期

值类型；无构造器、无 close；可自由复制、共享、作为 `Map`/`Set` 键。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| 枚举成员 | 无 | 四个成员之一 | 不存在非法成员 |
| `modelFormatFromName` | `String name` | 任意文本 | null/未知/空白 → `null` |

枚举成员直接使用；不允许 `new ModelFormat()`，不允许应用扩展成员。

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

`ModelFormat` 没有实例方法。相关顶层函数：

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `modelFormatName` | 稳定小写名 | `ModelFormat modelFormat` | `String` | null → panic | 用于日志/配置 |
| `modelFormatFromName` | 名称解析 | `String name` | `ModelFormat?` | 无 | 去空白、忽略大小写；未知 → `null` |
| `modelFormatIsOnnxFamily` | 是否 ONNX 容器 | `ModelFormat modelFormat` | `Bool` | null → panic | 仅 `Onnx` 为真 |

说明：

- 稳定名是交换合同；不得把 `"onnxruntime"`、`"tensorflow"`、`"pt"` 解析为合法成员。
- `modelFormatIsOnnxFamily` 只帮助诊断/路由，不表示 ONNX 运行时可用。
- 不存在“从扩展名推断格式”的函数；扩展名不可信。

---

## 8. 使用的技术

- 简单枚举 + 固定序号；
- 名称双向映射；
- 容器家族谓词；
- 格式与运行时/提供者解耦。

---

## 9. 需要的支撑

- 语言：enum、String、Bool；
- 运行时：字符串去空白、小写；
- 接口：[`Model`](Model.md)、[`InferenceSession`](InferenceSession.md)、[`SessionOptions`](SessionOptions.md)、[`ExecutionProvider`](ExecutionProvider.md)。

---

## 10. 依赖的特性/接口/类

[`Model`](Model.md)、[`InferenceSession`](InferenceSession.md)、[`SessionOptions`](SessionOptions.md)、[`ExecutionProvider`](ExecutionProvider.md)。

不依赖任何解析器、运行时二进制、FFI 类型或厂商 SDK。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。  
相等：按枚举值比较；可作 `Map`/`Set` 键。

---

## 12. 示例与反例

正确：`new Model(ModelFormat.Onnx, metadata, inputs, outputs, payload)` 表示“这段字节是 ONNX 容器”；格式与 `SessionOptions.providers()` 分开声明；私有格式用 `ModelFormat.Other` 并显式选择适配器。  
反例：看到 `.onnx` 后缀就假定一定是 ONNX；把 `ModelFormat.Onnx` 当“ONNX Runtime 已安装”；用格式推断模型任务；把仅含权重的 safetensors 文件当可直接执行的模型格式；用 `Other` 掩盖错误的容器类型；让 `modelFormatFromName("onnxruntime")` 返回 `Onnx`。

---

## 13. 测试/场景义务

四个成员的稳定名/序号；`modelFormatFromName` 的大小写、空白、未知、空串；`Other` 不 panic；格式与执行提供者组合；格式与模型任务组合；枚举值可作 `Map` 键；不出现第五个成员。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
enum ModelFormat {
    Onnx = 0,
    TensorFlowLite = 1,
    TorchScript = 2,
    Other = 3,
}

String modelFormatName(ModelFormat modelFormat) {
    if modelFormat == null {
        throw "modelFormatName: null format"
    }
    if modelFormat == ModelFormat.Onnx { return "onnx" }
    if modelFormat == ModelFormat.TensorFlowLite { return "tflite" }
    if modelFormat == ModelFormat.TorchScript { return "torchscript" }
    return "other"
}

ModelFormat? modelFormatFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "onnx" { return ModelFormat.Onnx }
    if normalized == "tflite" { return ModelFormat.TensorFlowLite }
    if normalized == "torchscript" { return ModelFormat.TorchScript }
    if normalized == "other" { return ModelFormat.Other }
    return null
}

Bool modelFormatIsOnnxFamily(ModelFormat modelFormat) {
    if modelFormat == null {
        throw "modelFormatIsOnnxFamily: null format"
    }
    return modelFormat == ModelFormat.Onnx
}
```
