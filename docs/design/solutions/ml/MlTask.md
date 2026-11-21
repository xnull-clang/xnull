# `MlTask`

| 项 | 值 |
| --- | --- |
| 类型 | `enum MlTask` |
| 包 | `xdk.ml` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

模型任务家族：文本、视觉、音频、表格的常见推理任务，以及适配器自定义任务。

只说明“模型输出应如何被上层解释”，不定义预处理、分词、解码、后处理或精度指标。任务标签用于选路、诊断和 `ModelMetadata` 声明。

不做：Tokenizer、图像解码、音频重采样、后处理、NMS、beam search、指标计算、训练目标函数选择。

---

## 2. 设计逻辑

- 任务必须显式：`ModelMetadata` 携带 `MlTask`；不从输入/输出形状猜测任务。
- 名称对齐 Hugging Face pipeline 的稳定任务 ID，便于跨生态映射；不复制其 Python 类型。
- 枚举只覆盖跨领域基线；细分任务（零样本分类、视觉问答、文档问答、文生图等）用 `Other` 或后续扩展。
- 任务与 `ModelFormat`、`ExecutionProvider` 正交；同一任务可由不同格式/提供者运行。
- 成员只允许追加；序号固定；名称是日志/配置合同。
- 分类谓词只做粗粒度分组，不表示输入模态唯一；多模态任务可归 `Other`。

---

## 3. 表示与不变量

| 成员 | 序号 | 稳定名 | 分组 | 典型输出 |
| --- | ---: | --- | --- | --- |
| `TextClassification` | 0 | `"text-classification"` | 文本 | 类别/分数 |
| `TokenClassification` | 1 | `"token-classification"` | 文本 | 每 token 类别 |
| `QuestionAnswering` | 2 | `"question-answering"` | 文本 | 答案跨度/分数 |
| `TextGeneration` | 3 | `"text-generation"` | 文本 | token/文本序列 |
| `Summarization` | 4 | `"summarization"` | 文本 | 摘要 token/文本 |
| `Translation` | 5 | `"translation"` | 文本 | 译文 token/文本 |
| `FillMask` | 6 | `"fill-mask"` | 文本 | 候选 token/分数 |
| `FeatureExtraction` | 7 | `"feature-extraction"` | 文本 | 隐状态/嵌入 |
| `SentenceSimilarity` | 8 | `"sentence-similarity"` | 文本 | 相似度分数 |
| `ImageClassification` | 9 | `"image-classification"` | 视觉 | 类别/分数 |
| `ObjectDetection` | 10 | `"object-detection"` | 视觉 | 框/类别/分数 |
| `ImageSegmentation` | 11 | `"image-segmentation"` | 视觉 | 掩码/类别 |
| `AutomaticSpeechRecognition` | 12 | `"automatic-speech-recognition"` | 音频 | 文本/token |
| `AudioClassification` | 13 | `"audio-classification"` | 音频 | 类别/分数 |
| `TabularClassification` | 14 | `"tabular-classification"` | 表格 | 类别/分数 |
| `TabularRegression` | 15 | `"tabular-regression"` | 表格 | 数值预测 |
| `Other` | 16 | `"other"` | 其他 | 适配器定义 |

不变量：成员固定；序号 0..16 固定；稳定名唯一；`Other` 合法；任务不隐含格式、提供者、张量布局或后处理库。

---

## 4. 生命周期

值类型；无构造器、无 close；可自由复制、共享、作为 `Map`/`Set` 键。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| 枚举成员 | 无 | 十七个成员之一 | 不存在非法成员 |
| `mlTaskFromName` | `String name` | 任意文本 | null/未知/空白 → `null` |

枚举成员直接使用；不允许 `new MlTask()`，不允许应用扩展成员。

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

`MlTask` 没有实例方法。相关顶层函数：

| 方法 | 用途 | 参数 | 返回 | 失败 | 备注 |
| --- | --- | --- | --- | --- | --- |
| `mlTaskName` | 稳定任务 ID | `MlTask mlTask` | `String` | null → panic | 与 HF 任务 ID 对齐 |
| `mlTaskFromName` | 名称解析 | `String name` | `MlTask?` | 无 | 去空白、忽略大小写；未知 → `null` |
| `mlTaskIsText` | 文本分组 | `MlTask mlTask` | `Bool` | null → panic | 0..8 |
| `mlTaskIsVision` | 视觉分组 | `MlTask mlTask` | `Bool` | null → panic | 9..11 |
| `mlTaskIsAudio` | 音频分组 | `MlTask mlTask` | `Bool` | null → panic | 12..13 |
| `mlTaskIsTabular` | 表格分组 | `MlTask mlTask` | `Bool` | null → panic | 14..15 |

说明：

- 分组谓词互斥且不覆盖 `Other`；`Other` 对四个谓词都返回 false。
- 任务 ID 是交换合同；不得把 `"sentiment-analysis"` 自动映射为 `TextClassification`，上层应显式选择。
- 文本生成/摘要/翻译都是序列任务，但后处理不同；枚举不合并它们。

---

## 8. 使用的技术

- 简单枚举 + 固定序号；
- 与生态任务 ID 对齐的名称表；
- 分组谓词；
- 任务与格式/提供者解耦。

---

## 9. 需要的支撑

- 语言：enum、String、Bool；
- 运行时：字符串去空白、小写；
- 接口：[`ModelMetadata`](ModelMetadata.md)、[`Model`](Model.md)、[`Ml`](Ml.md)。

---

## 10. 依赖的特性/接口/类

[`ModelMetadata`](ModelMetadata.md)、[`Model`](Model.md)、[`Ml`](Ml.md)。

不依赖 Hugging Face、ONNX Runtime、TensorFlow Lite 或 PyTorch 的运行时类型。

---

## 11. 所有权与并发

值语义；可共享；无资源；无取消点。  
相等：按枚举值比较；可作 `Map`/`Set` 键。

---

## 12. 示例与反例

正确：`new ModelMetadata("sentiment", "1.0", "acme", "情感分类", "nlp", MlTask.TextClassification, "Apache-2.0", [:])`；用 `mlTaskIsText` 做粗分组；未知任务用 `MlTask.Other` 并记录在自定义元数据。  
反例：用输出张量形状猜任务；把 `FillMask` 当 `TextGeneration`；把 `Other` 当“无任务”；让 `mlTaskFromName("sentiment-analysis")` 返回 `TextClassification`；假设 `ImageSegmentation` 的输出布局固定。

---

## 13. 测试/场景义务

十七个成员的名称/序号；`mlTaskFromName` 的大小写、空白、未知、空串；四个分组谓词互斥且覆盖 0..15；`Other` 四个谓词均为 false；任务与 `ModelFormat`/`ExecutionProvider` 组合；枚举值可作 `Map` 键；不出现第十八个成员。

---

## 14. XNull 伪代码

以下为设计伪代码，非可执行。

```xnull
enum MlTask {
    TextClassification = 0,
    TokenClassification = 1,
    QuestionAnswering = 2,
    TextGeneration = 3,
    Summarization = 4,
    Translation = 5,
    FillMask = 6,
    FeatureExtraction = 7,
    SentenceSimilarity = 8,
    ImageClassification = 9,
    ObjectDetection = 10,
    ImageSegmentation = 11,
    AutomaticSpeechRecognition = 12,
    AudioClassification = 13,
    TabularClassification = 14,
    TabularRegression = 15,
    Other = 16,
}

String mlTaskName(MlTask mlTask) {
    if mlTask == null { throw "mlTaskName: null task" }
    if mlTask == MlTask.TextClassification { return "text-classification" }
    if mlTask == MlTask.TokenClassification { return "token-classification" }
    if mlTask == MlTask.QuestionAnswering { return "question-answering" }
    if mlTask == MlTask.TextGeneration { return "text-generation" }
    if mlTask == MlTask.Summarization { return "summarization" }
    if mlTask == MlTask.Translation { return "translation" }
    if mlTask == MlTask.FillMask { return "fill-mask" }
    if mlTask == MlTask.FeatureExtraction { return "feature-extraction" }
    if mlTask == MlTask.SentenceSimilarity { return "sentence-similarity" }
    if mlTask == MlTask.ImageClassification { return "image-classification" }
    if mlTask == MlTask.ObjectDetection { return "object-detection" }
    if mlTask == MlTask.ImageSegmentation { return "image-segmentation" }
    if mlTask == MlTask.AutomaticSpeechRecognition {
        return "automatic-speech-recognition"
    }
    if mlTask == MlTask.AudioClassification { return "audio-classification" }
    if mlTask == MlTask.TabularClassification { return "tabular-classification" }
    if mlTask == MlTask.TabularRegression { return "tabular-regression" }
    return "other"
}

MlTask? mlTaskFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "text-classification" { return MlTask.TextClassification }
    if normalized == "token-classification" { return MlTask.TokenClassification }
    if normalized == "question-answering" { return MlTask.QuestionAnswering }
    if normalized == "text-generation" { return MlTask.TextGeneration }
    if normalized == "summarization" { return MlTask.Summarization }
    if normalized == "translation" { return MlTask.Translation }
    if normalized == "fill-mask" { return MlTask.FillMask }
    if normalized == "feature-extraction" { return MlTask.FeatureExtraction }
    if normalized == "sentence-similarity" { return MlTask.SentenceSimilarity }
    if normalized == "image-classification" { return MlTask.ImageClassification }
    if normalized == "object-detection" { return MlTask.ObjectDetection }
    if normalized == "image-segmentation" { return MlTask.ImageSegmentation }
    if normalized == "automatic-speech-recognition" {
        return MlTask.AutomaticSpeechRecognition
    }
    if normalized == "audio-classification" { return MlTask.AudioClassification }
    if normalized == "tabular-classification" {
        return MlTask.TabularClassification
    }
    if normalized == "tabular-regression" { return MlTask.TabularRegression }
    if normalized == "other" { return MlTask.Other }
    return null
}

Bool mlTaskIsText(MlTask mlTask) {
    if mlTask == null { throw "mlTaskIsText: null task" }
    if mlTask == MlTask.Other { return false }
    return mlTask == MlTask.TextClassification
        || mlTask == MlTask.TokenClassification
        || mlTask == MlTask.QuestionAnswering
        || mlTask == MlTask.TextGeneration
        || mlTask == MlTask.Summarization
        || mlTask == MlTask.Translation
        || mlTask == MlTask.FillMask
        || mlTask == MlTask.FeatureExtraction
        || mlTask == MlTask.SentenceSimilarity
}

Bool mlTaskIsVision(MlTask mlTask) {
    if mlTask == null { throw "mlTaskIsVision: null task" }
    return mlTask == MlTask.ImageClassification
        || mlTask == MlTask.ObjectDetection
        || mlTask == MlTask.ImageSegmentation
}

Bool mlTaskIsAudio(MlTask mlTask) {
    if mlTask == null { throw "mlTaskIsAudio: null task" }
    return mlTask == MlTask.AutomaticSpeechRecognition
        || mlTask == MlTask.AudioClassification
}

Bool mlTaskIsTabular(MlTask mlTask) {
    if mlTask == null { throw "mlTaskIsTabular: null task" }
    return mlTask == MlTask.TabularClassification
        || mlTask == MlTask.TabularRegression
}
```
