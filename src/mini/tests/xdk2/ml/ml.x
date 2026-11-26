package xdk2.ml
import xdk.ml
import xdk.tensor
import xdk.errors

static Tensor mlTensor(TensorDType dtype, List<Int> dims, Int byteCount) {
    return new Tensor(dtype, new TensorShape(dims), Bytes.alloc(byteCount))
}

static Int main() {
    print("format=" + modelFormatName(ModelFormat.Onnx) + "," +
        modelFormatName(modelFormatFromName(" TFLite ")) + "," +
        modelFormatName(modelFormatFromName("bogus")) + "," +
        str(modelFormatIsOnnxFamily(ModelFormat.Onnx)) + "," +
        str(modelFormatIsOnnxFamily(ModelFormat.TorchScript)))

    print("task=" + mlTaskName(MlTask.TextClassification) + "," +
        mlTaskName(mlTaskFromName("IMAGE-CLASSIFICATION")) + "," +
        mlTaskName(mlTaskFromName("bogus")) + "," +
        str(mlTaskIsText(MlTask.TextGeneration)) + "," +
        str(mlTaskIsVision(MlTask.ObjectDetection)) + "," +
        str(mlTaskIsAudio(MlTask.AudioClassification)) + "," +
        str(mlTaskIsTabular(MlTask.TabularRegression)) + "," +
        str(mlTaskIsText(MlTask.Other)))

    print("provider=" + executionProviderName(ExecutionProvider.Cuda) + "," +
        executionProviderName(executionProviderFromName(" CPU ")) + "," +
        executionProviderName(executionProviderFromName("gpu")) + "," +
        str(executionProviderIsCpu(ExecutionProvider.Cpu)) + "," +
        str(executionProviderIsCpu(ExecutionProvider.Npu)))

    List<Int> imageDims = [1, 3]
    List<Bool> imageDynamic = [false, false]
    ModelInput imageInput = new ModelInput("image", TensorDType.Float64, imageDims,
        imageDynamic)
    List<Int> seqDims = [0, 0]
    List<Bool> seqDynamic = [true, true]
    ModelInput textInput = new ModelInput("input_ids", TensorDType.Int64, seqDims,
        seqDynamic)
    List<Int> fixedDims = [1, 3]
    Tensor fixedTensor = mlTensor(TensorDType.Float64, fixedDims, 24)
    List<Int> wrongDims = [1, 4]
    Tensor wrongTensor = mlTensor(TensorDType.Float64, wrongDims, 32)
    List<Int> dynamicDims = [7, 11]
    Tensor dynamicTensor = mlTensor(TensorDType.Int64, dynamicDims, 616)
    print("input=" + str(imageInput.rank()) + "," +
        str(imageInput.hasDynamicDimensions()) + "," +
        str(imageInput.fixedShape() != null) + "," +
        imageInput.describe() + "," + str(imageInput.accepts(fixedTensor)) + "," +
        str(imageInput.accepts(wrongTensor)) + "," +
        str(imageInput.accepts(dynamicTensor)) + "," +
        str(textInput.hasDynamicDimensions()) + "," +
        str(textInput.fixedShape() == null) + "," +
        str(textInput.accepts(dynamicTensor)) + "," + textInput.describe())

    List<Bool> fixedFlags = [false, false]
    ModelOutput imageOutput = new ModelOutput("logits", TensorDType.Float64, imageDims,
        fixedFlags)
    print("output=" + imageOutput.describe() + "," +
        str(imageOutput.accepts(fixedTensor)) + "," +
        str(imageOutput.equals(imageOutput.copy())) + "," +
        str(imageOutput.fixedShape() != null))

    Map<String, String> metadataExtra = [:]
    metadataExtra.put("quantization", "fp32")
    ModelMetadata metadata = new ModelMetadata("classifier", "1.2.0", "xdk", "demo",
        "vision", MlTask.ImageClassification, "MIT", metadataExtra)
    String quantization = metadata.customValue("quantization") as String
    print("metadata=" + metadata.describe() + "," + quantization +
        "," + str(metadata.customValue("missing") == null) + "," +
        str(metadata.copy().name() == metadata.name()))

    Bytes payload = Bytes.fromString("fake-model-bytes")
    List<ModelInput> modelInputs = []
    modelInputs.push(imageInput)
    List<ModelOutput> modelOutputs = []
    modelOutputs.push(imageOutput)
    Model model = new Model(modelFormatFromName("onnx"), metadata, modelInputs,
        modelOutputs, payload)
    ModelInput? foundInput = model.input("image")
    ModelOutput? foundOutput = model.output("logits")
    print("model=" + model.describe() + "," + str(model.inputCount()) + "," +
        str(model.outputCount()) + "," + str(foundInput != null) + "," +
        str(foundOutput != null) + "," + str(model.input("missing") == null) + "," +
        str(model.payloadLength()) + "," + str(model.payloadCopy().length()) + "," +
        str(model.format() == ModelFormat.Onnx))

    SessionOptions defaults = SessionOptions.defaults()
    List<ExecutionProvider> providers = []
    providers.push(ExecutionProvider.Cuda)
    providers.push(ExecutionProvider.Cpu)
    Map<String, String> providerOptions = [:]
    providerOptions.put("cuda.device_id", "0")
    SessionOptions custom = new SessionOptions(providers, 2, 1, true, false, true,
        true, false, 4096 as Long, providerOptions)
    SessionOptions customCopy = custom.copy()
    print("options=" + defaults.describe() + "," + str(defaults.providers().length()) +
        "," + executionProviderName(defaults.providers().get(0)) + "," +
        custom.describe() + "," +
        (custom.providerOption("cuda.device_id") as String) + "," +
        str(custom.providerOption("missing") == null) + "," +
        str(customCopy.providerOptions().getOr("cuda.device_id", "")) + "," +
        str(customCopy.intraOpThreadCount() == 2))

    InferenceSession session = new InferenceSession(7 as Long, model, defaults)
    List<Tensor> emptyInputs = []
    Result<InferenceResult, Error> emptyRun = session.run(Context.background(), emptyInputs)
    List<Tensor> wrongInputs = []
    wrongInputs.push(wrongTensor)
    Result<InferenceResult, Error> wrongRun = session.run(Context.background(), wrongInputs)
    List<Tensor> validInputs = []
    validInputs.push(fixedTensor)
    Result<InferenceResult, Error> unsupportedRun = session.run(Context.background(),
        validInputs)
    Context cancelledContext = Context.background()
    cancelledContext.cancel()
    Result<InferenceResult, Error> cancelledRun = session.run(cancelledContext, validInputs)
    print("session=" + str(session.inputCount()) + "," + str(session.outputCount()) + "," +
        executionProviderName(session.providers().get(0)) + "," +
        errorKindName(emptyRun.error().kind()) + "," +
        errorKindName(wrongRun.error().kind()) + "," +
        errorKindName(unsupportedRun.error().kind()) + "," +
        errorKindName(cancelledRun.error().kind()) + "," +
        session.describe())

    Result<Unit, Error> firstClose = session.close()
    Result<InferenceResult, Error> closedRun = session.run(Context.background(),
        validInputs)
    print("session-close=" + str(firstClose.isOk()) + "," + str(session.isOpen()) + "," +
        errorKindName(closedRun.error().kind()) + "," + str(session.close().isOk()))

    List<Tensor> outputs = []
    outputs.push(fixedTensor)
    List<String> outputNames = ["logits"]
    InferenceResult result = new InferenceResult(outputs, outputNames, 12 as Long)
    print("result=" + result.describe() + "," + str(result.outputCount()) + "," +
        result.outputName(0) + "," + str(result.output(0).rank()) + "," +
        str(result.outputByName("logits") != null) + "," +
        str(result.outputByName("missing") == null) + "," +
        str(result.copy().elapsedMillis()))

    Result<InferenceSession, Error> opened = Ml.openSession(Context.background(), model,
        defaults)
    print("ml-open=" + errorKindName(opened.error().kind()))
    Result<InferenceResult, Error> delegated = Ml.run(Context.background(), session,
        validInputs)
    print("ml-run=" + errorKindName(delegated.error().kind()))
    return 0
}
