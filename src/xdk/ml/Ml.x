// xdk.ml —— 模型合同与推理会话（M24.1）
//
// 实现 ModelFormat/MlTask/ExecutionProvider/ModelInput/ModelOutput/ModelMetadata/
// Model/SessionOptions/InferenceSession/InferenceResult/Ml 的推理子集；
// 数据管道/损失/Trainer/运行时适配器留 M24.2。
package xdk.ml
import xdk.errors
import xdk.tensor
import xdk.random

// ---------- ModelFormat ----------
// Unknown 为哨兵且放在首位：编译器把枚举 0 当作 null，放在首位可让真实取值非 0。
enum ModelFormat {
    Unknown,
    Onnx,
    TensorFlowLite,
    TorchScript,
    Other,
}

String modelFormatName(ModelFormat modelFormat) {
    if modelFormat == ModelFormat.Onnx { return "onnx" }
    if modelFormat == ModelFormat.TensorFlowLite { return "tflite" }
    if modelFormat == ModelFormat.TorchScript { return "torchscript" }
    if modelFormat == ModelFormat.Other { return "other" }
    return "unknown"
}

ModelFormat modelFormatFromName(String name) {
    if name == null { return ModelFormat.Unknown }
    String normalized = name.trim().toLower()
    if normalized == "onnx" { return ModelFormat.Onnx }
    if normalized == "tflite" { return ModelFormat.TensorFlowLite }
    if normalized == "torchscript" { return ModelFormat.TorchScript }
    if normalized == "other" { return ModelFormat.Other }
    return ModelFormat.Unknown
}

Bool modelFormatIsOnnxFamily(ModelFormat modelFormat) {
    return modelFormat == ModelFormat.Onnx
}

// ---------- MlTask ----------
enum MlTask {
    Unknown,
    TextClassification,
    TokenClassification,
    QuestionAnswering,
    TextGeneration,
    Summarization,
    Translation,
    FillMask,
    FeatureExtraction,
    SentenceSimilarity,
    ImageClassification,
    ObjectDetection,
    ImageSegmentation,
    AutomaticSpeechRecognition,
    AudioClassification,
    TabularClassification,
    TabularRegression,
    Other,
}

String mlTaskName(MlTask mlTask) {
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
    if mlTask == MlTask.AutomaticSpeechRecognition { return "automatic-speech-recognition" }
    if mlTask == MlTask.AudioClassification { return "audio-classification" }
    if mlTask == MlTask.TabularClassification { return "tabular-classification" }
    if mlTask == MlTask.TabularRegression { return "tabular-regression" }
    if mlTask == MlTask.Other { return "other" }
    return "unknown"
}

MlTask mlTaskFromName(String name) {
    if name == null { return MlTask.Unknown }
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
    if normalized == "tabular-classification" { return MlTask.TabularClassification }
    if normalized == "tabular-regression" { return MlTask.TabularRegression }
    if normalized == "other" { return MlTask.Other }
    return MlTask.Unknown
}

Bool mlTaskIsText(MlTask mlTask) {
    if mlTask == MlTask.TextClassification { return true }
    if mlTask == MlTask.TokenClassification { return true }
    if mlTask == MlTask.QuestionAnswering { return true }
    if mlTask == MlTask.TextGeneration { return true }
    if mlTask == MlTask.Summarization { return true }
    if mlTask == MlTask.Translation { return true }
    if mlTask == MlTask.FillMask { return true }
    if mlTask == MlTask.FeatureExtraction { return true }
    return mlTask == MlTask.SentenceSimilarity
}

Bool mlTaskIsVision(MlTask mlTask) {
    return mlTask == MlTask.ImageClassification || mlTask == MlTask.ObjectDetection ||
        mlTask == MlTask.ImageSegmentation
}

Bool mlTaskIsAudio(MlTask mlTask) {
    return mlTask == MlTask.AutomaticSpeechRecognition ||
        mlTask == MlTask.AudioClassification
}

Bool mlTaskIsTabular(MlTask mlTask) {
    return mlTask == MlTask.TabularClassification || mlTask == MlTask.TabularRegression
}

// ---------- ExecutionProvider ----------
enum ExecutionProvider {
    Unknown,
    Cpu,
    Cuda,
    Rocm,
    DirectMl,
    OpenVino,
    Npu,
    Dsp,
    Fpga,
    Other,
}

String executionProviderName(ExecutionProvider executionProvider) {
    if executionProvider == ExecutionProvider.Cpu { return "cpu" }
    if executionProvider == ExecutionProvider.Cuda { return "cuda" }
    if executionProvider == ExecutionProvider.Rocm { return "rocm" }
    if executionProvider == ExecutionProvider.DirectMl { return "directml" }
    if executionProvider == ExecutionProvider.OpenVino { return "openvino" }
    if executionProvider == ExecutionProvider.Npu { return "npu" }
    if executionProvider == ExecutionProvider.Dsp { return "dsp" }
    if executionProvider == ExecutionProvider.Fpga { return "fpga" }
    if executionProvider == ExecutionProvider.Other { return "other" }
    return "unknown"
}

ExecutionProvider executionProviderFromName(String name) {
    if name == null { return ExecutionProvider.Unknown }
    String normalized = name.trim().toLower()
    if normalized == "cpu" { return ExecutionProvider.Cpu }
    if normalized == "cuda" { return ExecutionProvider.Cuda }
    if normalized == "rocm" { return ExecutionProvider.Rocm }
    if normalized == "directml" { return ExecutionProvider.DirectMl }
    if normalized == "openvino" { return ExecutionProvider.OpenVino }
    if normalized == "npu" { return ExecutionProvider.Npu }
    if normalized == "dsp" { return ExecutionProvider.Dsp }
    if normalized == "fpga" { return ExecutionProvider.Fpga }
    if normalized == "other" { return ExecutionProvider.Other }
    return ExecutionProvider.Unknown
}

Bool executionProviderIsCpu(ExecutionProvider executionProvider) {
    return executionProvider == ExecutionProvider.Cpu
}

// ---------- ModelInput ----------
class ModelInput {
    final String _name
    final TensorDType _tensorDType
    final List<Int> _dimensions
    final List<Bool> _dimensionDynamic

    ModelInput(String name, TensorDType tensorDType, List<Int> dimensions,
               List<Bool> dimensionDynamic) {
        if name == null || name == "" { throw "ModelInput: empty name" }
        if dimensions == null || dimensionDynamic == null {
            throw "ModelInput: null dimensions"
        }
        if dimensions.length() != dimensionDynamic.length() {
            throw "ModelInput: dimension/flag length mismatch"
        }
        List<Int> dimensionCopy = []
        List<Bool> flagCopy = []
        Int index = 0
        while index < dimensions.length() {
            Int dimension = dimensions.get(index)
            if dimension < 0 { throw "ModelInput: negative dimension" }
            Bool dynamic = dimensionDynamic.get(index)
            if dynamic && dimension != 0 {
                throw "ModelInput: dynamic dimension must be zero"
            }
            dimensionCopy.push(dimension)
            flagCopy.push(dynamic)
            index = index + 1
        }
        self._name = name
        self._tensorDType = tensorDType
        self._dimensions = dimensionCopy
        self._dimensionDynamic = flagCopy
    }

    String name() { return self._name }
    TensorDType tensorDType() { return self._tensorDType }
    List<Int> dimensions() { return self._dimensions.copy() }
    List<Bool> dimensionDynamic() { return self._dimensionDynamic.copy() }
    Int rank() { return self._dimensions.length() }

    Bool hasDynamicDimensions() {
        Int index = 0
        while index < self._dimensionDynamic.length() {
            if self._dimensionDynamic.get(index) { return true }
            index = index + 1
        }
        return false
    }

    TensorShape? fixedShape() {
        if self.hasDynamicDimensions() { return null }
        return new TensorShape(self._dimensions)
    }

    Bool accepts(Tensor tensor) {
        if tensor == null { return false }
        if tensor.tensorDType() != self._tensorDType { return false }
        if tensor.rank() != self.rank() { return false }
        List<Int> actual = tensor.tensorShape().dimensions()
        Int index = 0
        while index < self._dimensions.length() {
            if !self._dimensionDynamic.get(index) {
                if actual.get(index) != self._dimensions.get(index) { return false }
            }
            index = index + 1
        }
        return true
    }

    String describe() {
        String shapeText = mlShapeText(self._dimensions, self._dimensionDynamic)
        return "input " + self._name + " dtype=" + tensorDTypeName(self._tensorDType) +
            " shape=" + shapeText
    }

    Bool equals(ModelInput other) {
        if other == null { return false }
        return self._name == other.name() &&
            self._tensorDType == other.tensorDType() &&
            mlSameInts(self._dimensions, other.dimensions()) &&
            mlSameBools(self._dimensionDynamic, other.dimensionDynamic())
    }

    ModelInput copy() {
        return new ModelInput(self._name, self._tensorDType, self._dimensions,
            self._dimensionDynamic)
    }
}

// ---------- ModelOutput ----------
class ModelOutput {
    final String _name
    final TensorDType _tensorDType
    final List<Int> _dimensions
    final List<Bool> _dimensionDynamic

    ModelOutput(String name, TensorDType tensorDType, List<Int> dimensions,
                List<Bool> dimensionDynamic) {
        if name == null || name == "" { throw "ModelOutput: empty name" }
        if dimensions == null || dimensionDynamic == null {
            throw "ModelOutput: null dimensions"
        }
        if dimensions.length() != dimensionDynamic.length() {
            throw "ModelOutput: dimension/flag length mismatch"
        }
        List<Int> dimensionCopy = []
        List<Bool> flagCopy = []
        Int index = 0
        while index < dimensions.length() {
            Int dimension = dimensions.get(index)
            if dimension < 0 { throw "ModelOutput: negative dimension" }
            Bool dynamic = dimensionDynamic.get(index)
            if dynamic && dimension != 0 {
                throw "ModelOutput: dynamic dimension must be zero"
            }
            dimensionCopy.push(dimension)
            flagCopy.push(dynamic)
            index = index + 1
        }
        self._name = name
        self._tensorDType = tensorDType
        self._dimensions = dimensionCopy
        self._dimensionDynamic = flagCopy
    }

    String name() { return self._name }
    TensorDType tensorDType() { return self._tensorDType }
    List<Int> dimensions() { return self._dimensions.copy() }
    List<Bool> dimensionDynamic() { return self._dimensionDynamic.copy() }
    Int rank() { return self._dimensions.length() }

    Bool hasDynamicDimensions() {
        Int index = 0
        while index < self._dimensionDynamic.length() {
            if self._dimensionDynamic.get(index) { return true }
            index = index + 1
        }
        return false
    }

    TensorShape? fixedShape() {
        if self.hasDynamicDimensions() { return null }
        return new TensorShape(self._dimensions)
    }

    Bool accepts(Tensor tensor) {
        if tensor == null { return false }
        if tensor.tensorDType() != self._tensorDType { return false }
        if tensor.rank() != self.rank() { return false }
        List<Int> actual = tensor.tensorShape().dimensions()
        Int index = 0
        while index < self._dimensions.length() {
            if !self._dimensionDynamic.get(index) {
                if actual.get(index) != self._dimensions.get(index) { return false }
            }
            index = index + 1
        }
        return true
    }

    String describe() {
        String shapeText = mlShapeText(self._dimensions, self._dimensionDynamic)
        return "output " + self._name + " dtype=" + tensorDTypeName(self._tensorDType) +
            " shape=" + shapeText
    }

    Bool equals(ModelOutput other) {
        if other == null { return false }
        return self._name == other.name() &&
            self._tensorDType == other.tensorDType() &&
            mlSameInts(self._dimensions, other.dimensions()) &&
            mlSameBools(self._dimensionDynamic, other.dimensionDynamic())
    }

    ModelOutput copy() {
        return new ModelOutput(self._name, self._tensorDType, self._dimensions,
            self._dimensionDynamic)
    }
}

// ---------- ModelMetadata ----------
class ModelMetadata {
    final String _name
    final String _version
    final String _producer
    final String _description
    final String _domain
    final MlTask _mlTask
    final String _license
    final Map<String, String> _customMetadata

    ModelMetadata(String name, String version, String producer, String description,
                  String domain, MlTask mlTask, String license,
                  Map<String, String> customMetadata) {
        if name == null || name == "" { throw "ModelMetadata: empty name" }
        if version == null || producer == null || description == null ||
            domain == null || license == null || customMetadata == null {
            throw "ModelMetadata: null field"
        }
        Map<String, String> metadataCopy = [:]
        List<String> keys = customMetadata.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            if key == null || key == "" { throw "ModelMetadata: empty metadata key" }
            if customMetadata.getOr(key, "") == null {
                throw "ModelMetadata: null metadata value"
            }
            metadataCopy.put(key, customMetadata.getOr(key, ""))
            index = index + 1
        }
        self._name = name
        self._version = version
        self._producer = producer
        self._description = description
        self._domain = domain
        self._mlTask = mlTask
        self._license = license
        self._customMetadata = metadataCopy
    }

    String name() { return self._name }
    String version() { return self._version }
    String producer() { return self._producer }
    String description() { return self._description }
    String domain() { return self._domain }
    MlTask mlTask() { return self._mlTask }
    String license() { return self._license }
    Map<String, String> customMetadata() { return mlCopyStringMap(self._customMetadata) }

    String? customValue(String key) {
        if key == null { throw "ModelMetadata.customValue: null key" }
        if !self._customMetadata.has(key) { return null }
        return self._customMetadata.getOr(key, "")
    }

    String describe() {
        return "metadata name=" + self._name + " task=" + mlTaskName(self._mlTask) +
            " version=" + self._version
    }

    ModelMetadata copy() {
        return new ModelMetadata(self._name, self._version, self._producer,
            self._description, self._domain, self._mlTask, self._license,
            self._customMetadata)
    }
}

// ---------- Model ----------
class Model {
    final ModelFormat _format
    final ModelMetadata _metadata
    final List<ModelInput> _inputs
    final List<ModelOutput> _outputs
    final Bytes _payload

    Model(ModelFormat modelFormat, ModelMetadata metadata, List<ModelInput> inputs,
          List<ModelOutput> outputs, Bytes payload) {
        if metadata == null || inputs == null || outputs == null || payload == null {
            throw "Model: null argument"
        }
        if inputs.length() == 0 || outputs.length() == 0 {
            throw "Model: empty inputs or outputs"
        }
        if payload.length() == 0 { throw "Model: empty payload" }
        List<ModelInput> inputCopy = []
        List<String> inputNames = []
        Int index = 0
        while index < inputs.length() {
            ModelInput input = inputs.get(index)
            if input == null { throw "Model: null input" }
            if mlContainsString(inputNames, input.name()) {
                throw "Model: duplicate input name"
            }
            inputNames.push(input.name())
            inputCopy.push(input.copy())
            index = index + 1
        }
        List<ModelOutput> outputCopy = []
        List<String> outputNames = []
        index = 0
        while index < outputs.length() {
            ModelOutput output = outputs.get(index)
            if output == null { throw "Model: null output" }
            if mlContainsString(outputNames, output.name()) {
                throw "Model: duplicate output name"
            }
            outputNames.push(output.name())
            outputCopy.push(output.copy())
            index = index + 1
        }
        self._format = modelFormat
        self._metadata = metadata
        self._inputs = inputCopy
        self._outputs = outputCopy
        self._payload = payload
    }

    ModelFormat format() { return self._format }
    ModelMetadata metadata() { return self._metadata }

    List<ModelInput> inputs() {
        List<ModelInput> result = []
        Int index = 0
        while index < self._inputs.length() {
            result.push(self._inputs.get(index).copy())
            index = index + 1
        }
        return result
    }

    List<ModelOutput> outputs() {
        List<ModelOutput> result = []
        Int index = 0
        while index < self._outputs.length() {
            result.push(self._outputs.get(index).copy())
            index = index + 1
        }
        return result
    }

    Int inputCount() { return self._inputs.length() }
    Int outputCount() { return self._outputs.length() }

    ModelInput? input(String name) {
        if name == null { throw "Model.input: null name" }
        Int index = 0
        while index < self._inputs.length() {
            if self._inputs.get(index).name() == name {
                return self._inputs.get(index).copy()
            }
            index = index + 1
        }
        return null
    }

    ModelOutput? output(String name) {
        if name == null { throw "Model.output: null name" }
        Int index = 0
        while index < self._outputs.length() {
            if self._outputs.get(index).name() == name {
                return self._outputs.get(index).copy()
            }
            index = index + 1
        }
        return null
    }

    Long payloadLength() { return self._payload.length() as Long }
    Bytes payloadCopy() { return copy(self._payload) }

    String describe() {
        return "model format=" + modelFormatName(self._format) + " name=" +
            self._metadata.name() + " inputs=" + str(self._inputs.length()) +
            " outputs=" + str(self._outputs.length()) + " bytes=" +
            str(self.payloadLength())
    }
}

// ---------- SessionOptions ----------
class SessionOptions {
    final List<ExecutionProvider> _providers
    final Int _intraOpThreadCount
    final Int _interOpThreadCount
    final Bool _enableGraphOptimization
    final Bool _enableMemoryPattern
    final Bool _enableProfiling
    final Bool _deterministicCompute
    final Bool _enableCpuFallback
    final Long _maximumMemoryBytes
    final Map<String, String> _providerOptions

    SessionOptions(List<ExecutionProvider> providers, Int intraOpThreadCount,
                   Int interOpThreadCount, Bool enableGraphOptimization,
                   Bool enableMemoryPattern, Bool enableProfiling,
                   Bool deterministicCompute, Bool enableCpuFallback,
                   Long maximumMemoryBytes, Map<String, String> providerOptions) {
        if providers == null || providers.length() == 0 {
            throw "SessionOptions: empty providers"
        }
        if providerOptions == null { throw "SessionOptions: null options" }
        List<ExecutionProvider> providerCopy = []
        Int index = 0
        while index < providers.length() {
            ExecutionProvider provider = providers.get(index)
            if provider == ExecutionProvider.Unknown {
                throw "SessionOptions: unknown provider"
            }
            if mlContainsProvider(providerCopy, provider) {
                throw "SessionOptions: duplicate provider"
            }
            providerCopy.push(provider)
            index = index + 1
        }
        if intraOpThreadCount < 0 || interOpThreadCount < 0 {
            throw "SessionOptions: negative thread count"
        }
        if maximumMemoryBytes < 0 as Long {
            throw "SessionOptions: negative memory limit"
        }
        Map<String, String> optionsCopy = [:]
        List<String> keys = providerOptions.keys()
        index = 0
        while index < keys.length() {
            String key = keys.get(index)
            if key == null || key == "" || key.trim() != key {
                throw "SessionOptions: invalid provider option key"
            }
            optionsCopy.put(key, providerOptions.getOr(key, ""))
            index = index + 1
        }
        self._providers = providerCopy
        self._intraOpThreadCount = intraOpThreadCount
        self._interOpThreadCount = interOpThreadCount
        self._enableGraphOptimization = enableGraphOptimization
        self._enableMemoryPattern = enableMemoryPattern
        self._enableProfiling = enableProfiling
        self._deterministicCompute = deterministicCompute
        self._enableCpuFallback = enableCpuFallback
        self._maximumMemoryBytes = maximumMemoryBytes
        self._providerOptions = optionsCopy
    }

    static SessionOptions defaults() {
        List<ExecutionProvider> providers = [ExecutionProvider.Cpu]
        Map<String, String> options = [:]
        return new SessionOptions(providers, 0, 0, true, true, false, false, true,
            0 as Long, options)
    }

    List<ExecutionProvider> providers() { return self._providers.copy() }
    Int intraOpThreadCount() { return self._intraOpThreadCount }
    Int interOpThreadCount() { return self._interOpThreadCount }
    Bool enableGraphOptimization() { return self._enableGraphOptimization }
    Bool enableMemoryPattern() { return self._enableMemoryPattern }
    Bool enableProfiling() { return self._enableProfiling }
    Bool deterministicCompute() { return self._deterministicCompute }
    Bool enableCpuFallback() { return self._enableCpuFallback }
    Long maximumMemoryBytes() { return self._maximumMemoryBytes }
    Map<String, String> providerOptions() { return mlCopyStringMap(self._providerOptions) }

    String? providerOption(String key) {
        if key == null { throw "SessionOptions.providerOption: null key" }
        if !self._providerOptions.has(key) { return null }
        return self._providerOptions.getOr(key, "")
    }

    SessionOptions copy() {
        return new SessionOptions(self._providers, self._intraOpThreadCount,
            self._interOpThreadCount, self._enableGraphOptimization,
            self._enableMemoryPattern, self._enableProfiling,
            self._deterministicCompute, self._enableCpuFallback,
            self._maximumMemoryBytes, self._providerOptions)
    }

    String describe() {
        return "session options providers=" + str(self._providers.length()) +
            " intra=" + str(self._intraOpThreadCount) + " inter=" +
            str(self._interOpThreadCount) + " cpuFallback=" +
            str(self._enableCpuFallback) + " memoryLimit=" +
            str(self._maximumMemoryBytes)
    }
}

// ---------- InferenceSession ----------
class InferenceSession {
    final Long _handle
    final Model _model
    final SessionOptions _sessionOptions
    Bool _open

    InferenceSession(Long handle, Model model, SessionOptions sessionOptions) {
        if handle <= 0 as Long { throw "InferenceSession: invalid handle" }
        if model == null || sessionOptions == null {
            throw "InferenceSession: null argument"
        }
        self._handle = handle
        self._model = model
        self._sessionOptions = sessionOptions
        self._open = true
    }

    Model model() { return self._model }
    SessionOptions sessionOptions() { return self._sessionOptions }
    List<ExecutionProvider> providers() { return self._sessionOptions.providers() }
    Int inputCount() { return self._model.inputCount() }
    Int outputCount() { return self._model.outputCount() }
    Bool isOpen() { return self._open }

    Result<InferenceResult, Error> run(Context context, List<Tensor> inputs) {
        if context == null || inputs == null {
            throw "InferenceSession.run: null argument"
        }
        if !self._open {
            return Err(new BasicError(ErrorKind.Unavailable, "inference session closed"))
        }
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "inference cancelled"))
        }
        if inputs.length() != self._model.inputCount() {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "input count mismatch"))
        }
        List<ModelInput> declarations = self._model.inputs()
        Int index = 0
        while index < inputs.length() {
            if !declarations.get(index).accepts(inputs.get(index)) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "input does not match model declaration"))
            }
            index = index + 1
        }
        return Err(new BasicError(ErrorKind.Unsupported,
            "no ml runtime adapter is installed"))
    }

    Result<Unit, Error> close() {
        self._open = false
        return Ok()
    }

    String describe() {
        return "inference session model=" + self._model.metadata().name() +
            " providers=" + str(self._sessionOptions.providers().length())
    }
}

// ---------- InferenceResult ----------
class InferenceResult {
    final List<Tensor> _outputs
    final List<String> _outputNames
    final Long _elapsedMillis

    InferenceResult(List<Tensor> outputs, List<String> outputNames, Long elapsedMillis) {
        if outputs == null || outputNames == null {
            throw "InferenceResult: null argument"
        }
        if outputs.length() == 0 || outputs.length() != outputNames.length() {
            throw "InferenceResult: output/name length mismatch"
        }
        if elapsedMillis < 0 as Long { throw "InferenceResult: negative elapsed" }
        List<Tensor> outputCopy = []
        List<String> nameCopy = []
        Int index = 0
        while index < outputs.length() {
            Tensor output = outputs.get(index)
            if output == null { throw "InferenceResult: null tensor" }
            String name = outputNames.get(index)
            if name == null || name == "" { throw "InferenceResult: empty output name" }
            if mlContainsString(nameCopy, name) {
                throw "InferenceResult: duplicate output name"
            }
            outputCopy.push(output)
            nameCopy.push(name)
            index = index + 1
        }
        self._outputs = outputCopy
        self._outputNames = nameCopy
        self._elapsedMillis = elapsedMillis
    }

    List<Tensor> outputs() { return self._outputs.copy() }
    List<String> outputNames() { return self._outputNames.copy() }
    Int outputCount() { return self._outputs.length() }

    Tensor output(Int outputIndex) {
        if outputIndex < 0 || outputIndex >= self._outputs.length() {
            throw "InferenceResult.output: index out of range"
        }
        return self._outputs.get(outputIndex)
    }

    Tensor? outputByName(String name) {
        if name == null { throw "InferenceResult.outputByName: null name" }
        Int index = 0
        while index < self._outputNames.length() {
            if self._outputNames.get(index) == name { return self._outputs.get(index) }
            index = index + 1
        }
        return null
    }

    String outputName(Int outputIndex) {
        if outputIndex < 0 || outputIndex >= self._outputNames.length() {
            throw "InferenceResult.outputName: index out of range"
        }
        return self._outputNames.get(outputIndex)
    }

    Long elapsedMillis() { return self._elapsedMillis }

    String describe() {
        return "inference result outputs=" + str(self._outputs.length()) +
            " elapsedMillis=" + str(self._elapsedMillis)
    }

    InferenceResult copy() {
        return new InferenceResult(self._outputs, self._outputNames, self._elapsedMillis)
    }
}

enum LossKind {
    Unknown,
    MeanSquaredError,
    MeanAbsoluteError,
    CrossEntropy,
    BinaryCrossEntropy,
    NegativeLogLikelihood,
    Other,
}

// ---------- Ml ----------
class Ml {
    private Ml() { }

    static Result<InferenceSession, Error> openSession(Context context, Model model,
                                                        SessionOptions sessionOptions) {
        if context == null || model == null || sessionOptions == null {
            throw "Ml.openSession: null argument"
        }
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "open session cancelled"))
        }
        return Err(new BasicError(ErrorKind.Unsupported,
            "no ml runtime adapter is installed"))
    }

    static Result<InferenceResult, Error> run(Context context, InferenceSession session,
                                               List<Tensor> inputs) {
        if context == null || session == null || inputs == null {
            throw "Ml.run: null argument"
        }
        return session.run(context, inputs)
    }

    static Result<Tensor, Error> computeLoss(Context context, LossKind lossKind,
                                             Tensor predictions, Tensor targets) {
        if context == null || predictions == null || targets == null {
            throw "Ml.computeLoss: null argument"
        }
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "loss cancelled"))
        }
        if lossKind == LossKind.Other {
            return Err(new BasicError(ErrorKind.Unsupported, "loss kind is unsupported"))
        }
        if predictions.elementCount() == 0 || targets.elementCount() == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "empty loss input"))
        }
        Double loss = 0.0
        if lossKind == LossKind.MeanSquaredError ||
            lossKind == LossKind.MeanAbsoluteError ||
            lossKind == LossKind.BinaryCrossEntropy {
            if !tensorDTypeIsFloatingPoint(predictions.tensorDType()) ||
                !tensorDTypeIsFloatingPoint(targets.tensorDType()) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "loss requires floating tensors"))
            }
            if !mlSameInts(predictions.tensorShape().dimensions(),
                targets.tensorShape().dimensions()) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "loss tensor shape mismatch"))
            }
            Long count = predictions.elementCount()
            Long index = 0
            while index < count {
                if context.isCancelled() {
                    return Err(new BasicError(ErrorKind.Cancelled, "loss cancelled"))
                }
                Double predicted = predictions.atFlat(index)
                Double actual = targets.atFlat(index)
                if lossKind == LossKind.MeanSquaredError {
                    Double difference = predicted - actual
                    loss = loss + difference * difference
                } else if lossKind == LossKind.MeanAbsoluteError {
                    Double difference = predicted - actual
                    if difference < 0.0 { difference = -difference }
                    loss = loss + difference
                } else {
                    Double probability = predicted
                    if probability < 0.000000000001 { probability = 0.000000000001 }
                    if probability > 0.999999999999 { probability = 0.999999999999 }
                    loss = loss - (actual * log(probability) +
                        (1.0 - actual) * log(1.0 - probability))
                }
                index = index + 1
            }
            loss = loss / (count as Double)
        } else {
            if !tensorDTypeIsFloatingPoint(predictions.tensorDType()) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "classification loss requires floating logits"))
            }
            if !tensorDTypeIsInteger(targets.tensorDType()) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "classification targets must be integers"))
            }
            List<Int> predictionDims = predictions.tensorShape().dimensions()
            List<Int> targetDims = targets.tensorShape().dimensions()
            if predictionDims.length() != 2 || targetDims.length() != 1 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "classification loss requires [batch, classes] and [batch]"))
            }
            Int batch = predictionDims.get(0)
            Int classes = predictionDims.get(1)
            if batch != targetDims.get(0) || batch <= 0 || classes <= 0 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "classification loss batch mismatch"))
            }
            Int row = 0
            while row < batch {
                if context.isCancelled() {
                    return Err(new BasicError(ErrorKind.Cancelled, "loss cancelled"))
                }
                Long offset = (row as Long) * (classes as Long)
                List<Double> logits = []
                Double maximum = 0.0
                Int column = 0
                while column < classes {
                    Double value = predictions.atFlat(offset + (column as Long))
                    logits.push(value)
                    if column == 0 || value > maximum { maximum = value }
                    column = column + 1
                }
                Double targetValue = targets.atFlat(row as Long)
                Int target = targetValue as Int
                if target < 0 || target >= classes {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "loss target index out of range"))
                }
                Double rowLoss = 0.0
                if lossKind == LossKind.CrossEntropy {
                    Double sumExp = 0.0
                    column = 0
                    while column < classes {
                        sumExp = sumExp + exp(logits.get(column) - maximum)
                        column = column + 1
                    }
                    rowLoss = -(logits.get(target) - maximum - log(sumExp))
                } else {
                    Double logProbability = logits.get(target)
                    if logProbability > 0.0 {
                        return Err(new BasicError(ErrorKind.InvalidArgument,
                            "NLL inputs must be log probabilities"))
                    }
                    rowLoss = -logProbability
                }
                loss = loss + rowLoss
                row = row + 1
            }
            loss = loss / (batch as Double)
        }
        if !isFinite(loss) {
            return Err(new BasicError(ErrorKind.Internal, "loss is not finite"))
        }
        List<Int> scalarDims = []
        List<Double> values = []
        values.push(loss)
        Tensor scalar = TensorOps.fromDoubles(TensorDType.Float64,
            new TensorShape(scalarDims), values)
        return Ok(scalar)
    }
}

// ---------- helpers ----------
static String mlShapeText(List<Int> dimensions, List<Bool> dynamic) {
    String text = "["
    Int index = 0
    while index < dimensions.length() {
        if index > 0 { text = text + "," }
        if dynamic.get(index) {
            text = text + "?"
        } else {
            text = text + str(dimensions.get(index))
        }
        index = index + 1
    }
    return text + "]"
}

static Bool mlContainsString(List<String> values, String target) {
    Int index = 0
    while index < values.length() {
        if values.get(index) == target { return true }
        index = index + 1
    }
    return false
}

static Bool mlContainsProvider(List<ExecutionProvider> values, ExecutionProvider target) {
    Int index = 0
    while index < values.length() {
        if values.get(index) == target { return true }
        index = index + 1
    }
    return false
}

static Bool mlSameInts(List<Int> left, List<Int> right) {
    if left.length() != right.length() { return false }
    Int index = 0
    while index < left.length() {
        if left.get(index) != right.get(index) { return false }
        index = index + 1
    }
    return true
}

static Bool mlSameBools(List<Bool> left, List<Bool> right) {
    if left.length() != right.length() { return false }
    Int index = 0
    while index < left.length() {
        if left.get(index) != right.get(index) { return false }
        index = index + 1
    }
    return true
}

static Map<String, String> mlCopyStringMap(Map<String, String> source) {
    Map<String, String> result = [:]
    List<String> keys = source.keys()
    Int index = 0
    while index < keys.length() {
        String key = keys.get(index)
        result.put(key, source.getOr(key, ""))
        index = index + 1
    }
    return result
}


// ---------- Dataset / Transform ----------
protocol Dataset {
    Long size();
    Result<MlBatch, Error> get(Context context, Long sampleIndex);
    Bool isOpen();
    Result<Unit, Error> close();
    String describe();
}

protocol Transform {
    Result<MlBatch, Error> apply(Context context, MlBatch batch);
    String describe();
}

// ---------- MlBatch ----------
class MlBatch {
    final Int _sampleCount
    final List<Tensor> _inputs
    final List<Tensor> _targets

    MlBatch(Int sampleCount, List<Tensor> inputs, List<Tensor> targets) {
        if sampleCount < 1 { throw "MlBatch: sampleCount must be positive" }
        if inputs == null || inputs.length() == 0 {
            throw "MlBatch: empty inputs"
        }
        List<Tensor> inputCopy = []
        Int index = 0
        while index < inputs.length() {
            Tensor input = inputs.get(index)
            if input == null { throw "MlBatch: null input" }
            if input.rank() < 1 { throw "MlBatch: input rank must be positive" }
            if input.tensorShape().dim(0) != sampleCount {
                throw "MlBatch: input dim0 does not match sampleCount"
            }
            inputCopy.push(input)
            index = index + 1
        }
        List<Tensor> targetCopy = []
        if targets != null {
            index = 0
            while index < targets.length() {
                Tensor target = targets.get(index)
                if target == null { throw "MlBatch: null target" }
                if target.rank() < 1 { throw "MlBatch: target rank must be positive" }
                if target.tensorShape().dim(0) != sampleCount {
                    throw "MlBatch: target dim0 does not match sampleCount"
                }
                targetCopy.push(target)
                index = index + 1
            }
        }
        self._sampleCount = sampleCount
        self._inputs = inputCopy
        self._targets = targetCopy
    }

    Int sampleCount() { return self._sampleCount }
    List<Tensor> inputs() { return self._inputs.copy() }
    List<Tensor> targets() { return self._targets.copy() }
    Int inputCount() { return self._inputs.length() }
    Int targetCount() { return self._targets.length() }
    Bool hasTargets() { return self._targets.length() > 0 }

    Tensor input(Int inputIndex) {
        if inputIndex < 0 || inputIndex >= self._inputs.length() {
            throw "MlBatch.input: index out of range"
        }
        return self._inputs.get(inputIndex)
    }

    Tensor target(Int targetIndex) {
        if targetIndex < 0 || targetIndex >= self._targets.length() {
            throw "MlBatch.target: index out of range"
        }
        return self._targets.get(targetIndex)
    }

    MlBatch withTargets(List<Tensor> newTargets) {
        return new MlBatch(self._sampleCount, self._inputs, newTargets)
    }

    String describe() {
        return "batch samples=" + str(self._sampleCount) + " inputs=" +
            str(self._inputs.length()) + " targets=" + str(self._targets.length())
    }
}

// ---------- OptimizerKind / Optimizer ----------
enum OptimizerKind {
    Unknown,
    Sgd,
    Adam,
    AdamW,
    RmsProp,
    AdaGrad,
    Other,
}

String optimizerKindName(OptimizerKind optimizerKind) {
    if optimizerKind == OptimizerKind.Sgd { return "sgd" }
    if optimizerKind == OptimizerKind.Adam { return "adam" }
    if optimizerKind == OptimizerKind.AdamW { return "adamw" }
    if optimizerKind == OptimizerKind.RmsProp { return "rmsprop" }
    if optimizerKind == OptimizerKind.AdaGrad { return "adagrad" }
    if optimizerKind == OptimizerKind.Other { return "other" }
    return "unknown"
}

OptimizerKind optimizerKindFromName(String name) {
    if name == null { return OptimizerKind.Unknown }
    String normalized = name.trim().toLower()
    if normalized == "sgd" { return OptimizerKind.Sgd }
    if normalized == "adam" { return OptimizerKind.Adam }
    if normalized == "adamw" { return OptimizerKind.AdamW }
    if normalized == "rmsprop" { return OptimizerKind.RmsProp }
    if normalized == "adagrad" { return OptimizerKind.AdaGrad }
    if normalized == "other" { return OptimizerKind.Other }
    return OptimizerKind.Unknown
}

Bool optimizerKindUsesSecondMoment(OptimizerKind optimizerKind) {
    return optimizerKind == OptimizerKind.Adam || optimizerKind == OptimizerKind.AdamW ||
        optimizerKind == OptimizerKind.RmsProp || optimizerKind == OptimizerKind.AdaGrad
}

class Optimizer {
    final OptimizerKind _kind
    final Double _learningRate
    final Double _weightDecay
    final Double _momentum
    final Double _beta1
    final Double _beta2
    final Double _epsilon

    Optimizer(OptimizerKind optimizerKind, Double learningRate, Double weightDecay,
              Double momentum, Double beta1, Double beta2, Double epsilon) {
        if !isFinite(learningRate) || learningRate <= 0.0 {
            throw "Optimizer: invalid learningRate"
        }
        if !isFinite(weightDecay) || weightDecay < 0.0 {
            throw "Optimizer: invalid weightDecay"
        }
        if !isFinite(momentum) || momentum < 0.0 || momentum >= 1.0 {
            throw "Optimizer: invalid momentum"
        }
        if !isFinite(beta1) || beta1 < 0.0 || beta1 >= 1.0 {
            throw "Optimizer: invalid beta1"
        }
        if !isFinite(beta2) || beta2 < 0.0 || beta2 >= 1.0 {
            throw "Optimizer: invalid beta2"
        }
        if !isFinite(epsilon) || epsilon <= 0.0 {
            throw "Optimizer: invalid epsilon"
        }
        self._kind = optimizerKind
        self._learningRate = learningRate
        self._weightDecay = weightDecay
        self._momentum = momentum
        self._beta1 = beta1
        self._beta2 = beta2
        self._epsilon = epsilon
    }

    OptimizerKind kind() { return self._kind }
    Double learningRate() { return self._learningRate }
    Double weightDecay() { return self._weightDecay }
    Double momentum() { return self._momentum }
    Double beta1() { return self._beta1 }
    Double beta2() { return self._beta2 }
    Double epsilon() { return self._epsilon }

    Optimizer copy() {
        return new Optimizer(self._kind, self._learningRate, self._weightDecay,
            self._momentum, self._beta1, self._beta2, self._epsilon)
    }

    String describe() {
        return "optimizer kind=" + optimizerKindName(self._kind) + " learningRate=" +
            str(self._learningRate) + " weightDecay=" + str(self._weightDecay)
    }
}

// ---------- LossKind ----------

String lossKindName(LossKind lossKind) {
    if lossKind == LossKind.MeanSquaredError { return "mean-squared-error" }
    if lossKind == LossKind.MeanAbsoluteError { return "mean-absolute-error" }
    if lossKind == LossKind.CrossEntropy { return "cross-entropy" }
    if lossKind == LossKind.BinaryCrossEntropy { return "binary-cross-entropy" }
    if lossKind == LossKind.NegativeLogLikelihood {
        return "negative-log-likelihood"
    }
    if lossKind == LossKind.Other { return "other" }
    return "unknown"
}

LossKind lossKindFromName(String name) {
    if name == null { return LossKind.Unknown }
    String normalized = name.trim().toLower()
    if normalized == "mean-squared-error" { return LossKind.MeanSquaredError }
    if normalized == "mean-absolute-error" { return LossKind.MeanAbsoluteError }
    if normalized == "cross-entropy" { return LossKind.CrossEntropy }
    if normalized == "binary-cross-entropy" { return LossKind.BinaryCrossEntropy }
    if normalized == "negative-log-likelihood" {
        return LossKind.NegativeLogLikelihood
    }
    if normalized == "other" { return LossKind.Other }
    return LossKind.Unknown
}

Bool lossKindIsRegression(LossKind lossKind) {
    return lossKind == LossKind.MeanSquaredError ||
        lossKind == LossKind.MeanAbsoluteError
}

// ---------- Trainer / EpochStats ----------
protocol Trainer {
    Optimizer optimizer();
    LossKind lossKind();
    Result<EpochStats, Error> trainEpoch(Context context, DataLoader dataLoader);
    Result<EpochStats, Error> evaluate(Context context, DataLoader dataLoader);
    Bool isOpen();
    Result<Unit, Error> close();
    String describe();
}

class EpochStats {
    final Int _epochIndex
    final Bool _training
    final Long _batchCount
    final Long _sampleCount
    final Bool _hasMeanLoss
    final Double _meanLossValue
    final Map<String, Double> _metrics
    final Long _elapsedMillis

    EpochStats(Int epochIndex, Bool training, Long batchCount, Long sampleCount,
               Double? meanLoss, Map<String, Double> metrics, Long elapsedMillis) {
        if epochIndex < 0 || batchCount < 0 as Long || sampleCount < 0 as Long ||
            elapsedMillis < 0 as Long {
            throw "EpochStats: negative counter"
        }
        if metrics == null { throw "EpochStats: null metrics" }
        Bool hasLoss = sampleCount > 0 as Long
        Double lossValue = 0.0
        if meanLoss != null { lossValue = meanLoss as Double }
        if !hasLoss && meanLoss != null {
            throw "EpochStats: empty epoch must have null meanLoss"
        }
        if hasLoss && !isFinite(lossValue) {
            throw "EpochStats: meanLoss is not finite"
        }
        Map<String, Double> metricCopy = [:]
        List<String> keys = metrics.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            if key == null || key == "" { throw "EpochStats: empty metric key" }
            Double value = metrics.getOr(key, 0.0)
            if !isFinite(value) { throw "EpochStats: metric is not finite" }
            metricCopy.put(key, value)
            index = index + 1
        }
        self._epochIndex = epochIndex
        self._training = training
        self._batchCount = batchCount
        self._sampleCount = sampleCount
        self._hasMeanLoss = hasLoss
        self._meanLossValue = lossValue
        self._metrics = metricCopy
        self._elapsedMillis = elapsedMillis
    }

    Int epochIndex() { return self._epochIndex }
    Bool isTraining() { return self._training }
    Long batchCount() { return self._batchCount }
    Long sampleCount() { return self._sampleCount }
    Bool hasMeanLoss() { return self._hasMeanLoss }
    Double meanLossValue() { return self._meanLossValue }

    Double? meanLoss() {
        if !self._hasMeanLoss { return null }
        return self._meanLossValue
    }
    Map<String, Double> metrics() { return mlCopyDoubleMap(self._metrics) }

    Double? metric(String name) {
        if name == null { throw "EpochStats.metric: null name" }
        if !self._metrics.has(name) { return null }
        return self._metrics.getOr(name, 0.0)
    }

    Long elapsedMillis() { return self._elapsedMillis }

    String describe() {
        return "epoch=" + str(self._epochIndex) + " training=" +
            str(self._training) + " batches=" + str(self._batchCount) +
            " samples=" + str(self._sampleCount) + " meanLoss=" +
            mlDoubleText(self._meanLossValue)
    }
}

// ---------- DataLoader ----------
class DataLoader {
    final Dataset _dataset
    final Int _batchSize
    final Bool _shuffle
    final List<Transform> _transforms
    final Random? _randomSource
    final List<Long> _order
    Long _cursor
    Bool _started

    DataLoader(Dataset dataset, Int batchSize, Bool shuffle,
               List<Transform> transforms, Random? randomSource) {
        if dataset == null || transforms == null {
            throw "DataLoader: null argument"
        }
        if batchSize <= 0 { throw "DataLoader: invalid batchSize" }
        if shuffle && randomSource == null {
            throw "DataLoader: shuffle requires randomSource"
        }
        if shuffle && dataset.size() > 2147483647 as Long {
            throw "DataLoader: dataset too large for shuffle"
        }
        List<Transform> transformCopy = []
        Int index = 0
        while index < transforms.length() {
            Transform transform = transforms.get(index)
            if transform == null { throw "DataLoader: null transform" }
            transformCopy.push(transform)
            index = index + 1
        }
        self._dataset = dataset
        self._batchSize = batchSize
        self._shuffle = shuffle
        self._transforms = transformCopy
        self._randomSource = randomSource
        List<Long> order = []
        self._order = order
        self._cursor = 0 as Long
        self._started = false
    }

    Dataset dataset() { return self._dataset }
    Int batchSize() { return self._batchSize }
    Bool shuffle() { return self._shuffle }
    List<Transform> transforms() { return self._transforms.copy() }

    Long batchCount() {
        Long size = self._dataset.size()
        if size == 0 as Long { return 0 as Long }
        Long quotient = size / (self._batchSize as Long)
        if size % (self._batchSize as Long) != 0 { quotient = quotient + 1 as Long }
        return quotient
    }

    Void beginEpoch() {
        self._cursor = 0 as Long
        self._started = true
        self._order.clear()
        if self._shuffle {
            Random random = self._randomSource as Random
            Long size = self._dataset.size()
            Long index = 0 as Long
            while index < size {
                self._order.push(index)
                index = index + 1 as Long
            }
            Long position = size - 1 as Long
            while position > 0 as Long {
                Long swapIndex = random.nextLongRange(0 as Long, position + 1 as Long)
                Long value = self._order.get(position as Int)
                self._order.set(position as Int, self._order.get(swapIndex as Int))
                self._order.set(swapIndex as Int, value)
                position = position - 1 as Long
            }
        }
    }

    Result<MlBatch, Error> next(Context context) {
        if context == null { throw "DataLoader.next: null context" }
        if !self._started { self.beginEpoch() }
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "data loader cancelled"))
        }
        Long size = self._dataset.size()
        if self._cursor >= size {
            return Err(new BasicError(ErrorKind.NotFound, "end of epoch"))
        }
        Long remaining = size - self._cursor
        Int count = self._batchSize
        if remaining < (count as Long) { count = remaining as Int }
        List<MlBatch> samples = []
        Int collected = 0
        while collected < count {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled, "data loader cancelled"))
            }
            Long index = self._cursor + (collected as Long)
            if self._shuffle { index = self._order.get(index as Int) }
            Result<MlBatch, Error> loaded = self._dataset.get(context, index)
            if loaded.isErr() { return Err(loaded.error()) }
            MlBatch sample = loaded.value()
            if sample.sampleCount() != 1 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "dataset sample must have sampleCount 1"))
            }
            Int transformIndex = 0
            while transformIndex < self._transforms.length() {
                if context.isCancelled() {
                    return Err(new BasicError(ErrorKind.Cancelled, "data loader cancelled"))
                }
                Result<MlBatch, Error> applied = self._transforms.get(transformIndex)
                    .apply(context, sample)
                if applied.isErr() { return Err(applied.error()) }
                sample = applied.value()
                if sample.sampleCount() != 1 {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "transform must keep sampleCount 1"))
                }
                transformIndex = transformIndex + 1
            }
            samples.push(sample)
            collected = collected + 1
        }
        Result<MlBatch, Error> collated = mlDefaultCollate(samples)
        if collated.isErr() { return Err(collated.error()) }
        self._cursor = self._cursor + (collected as Long)
        return collated
    }

    String describe() {
        return "data loader size=" + str(self._dataset.size()) + " batchSize=" +
            str(self._batchSize) + " shuffle=" + str(self._shuffle) + " transforms=" +
            str(self._transforms.length())
    }
}

// ---------- M24.2 helpers ----------
static Result<MlBatch, Error> mlDefaultCollate(List<MlBatch> samples) {
    if samples.length() == 0 {
        return Err(new BasicError(ErrorKind.InvalidArgument, "empty collate"))
    }
    Int sampleCount = samples.length()
    MlBatch first = samples.get(0)
    Int inputCount = first.inputCount()
    Int targetCount = first.targetCount()
    Int sampleIndex = 1
    while sampleIndex < samples.length() {
        MlBatch sample = samples.get(sampleIndex)
        if sample.inputCount() != inputCount || sample.targetCount() != targetCount {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "collate input/target count mismatch"))
        }
        sampleIndex = sampleIndex + 1
    }
    List<Tensor> inputs = []
    Int inputIndex = 0
    while inputIndex < inputCount {
        Result<Tensor, Error> merged = mlConcatTensor(samples, inputIndex, true)
        if merged.isErr() { return Err(merged.error()) }
        inputs.push(merged.value())
        inputIndex = inputIndex + 1
    }
    List<Tensor> targets = []
    Int targetIndex = 0
    while targetIndex < targetCount {
        Result<Tensor, Error> merged = mlConcatTensor(samples, targetIndex, false)
        if merged.isErr() { return Err(merged.error()) }
        targets.push(merged.value())
        targetIndex = targetIndex + 1
    }
    return Ok(new MlBatch(sampleCount, inputs, targets))
}

static Result<Tensor, Error> mlConcatTensor(List<MlBatch> samples, Int index,
                                            Bool input) {
    Tensor first = input ? samples.get(0).input(index) : samples.get(0).target(index)
    TensorDType dtype = first.tensorDType()
    List<Int> firstDims = first.tensorShape().dimensions()
    Int rank = firstDims.length()
    Int total = 0
    Int sampleIndex = 0
    while sampleIndex < samples.length() {
        Tensor current = input ? samples.get(sampleIndex).input(index) :
            samples.get(sampleIndex).target(index)
        List<Int> dims = current.tensorShape().dimensions()
        if current.tensorDType() != dtype || dims.length() != rank {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "collate dtype/rank mismatch"))
        }
        Int dimIndex = 1
        while dimIndex < rank {
            if dims.get(dimIndex) != firstDims.get(dimIndex) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "collate trailing dimension mismatch"))
            }
            dimIndex = dimIndex + 1
        }
        total = total + dims.get(0)
        sampleIndex = sampleIndex + 1
    }
    List<Int> mergedDims = []
    mergedDims.push(total)
    Int dimIndex = 1
    while dimIndex < rank {
        mergedDims.push(firstDims.get(dimIndex))
        dimIndex = dimIndex + 1
    }
    List<Double> values = []
    sampleIndex = 0
    while sampleIndex < samples.length() {
        Tensor current = input ? samples.get(sampleIndex).input(index) :
            samples.get(sampleIndex).target(index)
        List<Double> data = current.toDoubles()
        Int valueIndex = 0
        while valueIndex < data.length() {
            values.push(data.get(valueIndex))
            valueIndex = valueIndex + 1
        }
        sampleIndex = sampleIndex + 1
    }
    return Ok(TensorOps.fromDoubles(dtype, new TensorShape(mergedDims), values))
}

static Map<String, Double> mlCopyDoubleMap(Map<String, Double> source) {
    Map<String, Double> result = [:]
    List<String> keys = source.keys()
    Int index = 0
    while index < keys.length() {
        String key = keys.get(index)
        result.put(key, source.getOr(key, 0.0))
        index = index + 1
    }
    return result
}

static String mlDoubleText(Double? value) {
    if value == null { return "null" }
    return str(value as Double)
}
