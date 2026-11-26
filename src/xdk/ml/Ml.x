// xdk.ml —— 模型合同与推理会话（M24.1）
//
// 实现 ModelFormat/MlTask/ExecutionProvider/ModelInput/ModelOutput/ModelMetadata/
// Model/SessionOptions/InferenceSession/InferenceResult/Ml 的推理子集；
// 数据管道/损失/Trainer/运行时适配器留 M24.2。
package xdk.ml
import xdk.errors
import xdk.tensor

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

    Long handle() { return self._handle }
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
