package xdk2.ml
import xdk.ml
import xdk.tensor
import xdk.errors
import xdk.random

static Tensor mlTensor(TensorDType dtype, List<Int> dims, Int byteCount) {
    return new Tensor(dtype, new TensorShape(dims), Bytes.alloc(byteCount))
}

static Error mlErrUnavailable() {
    return new BasicError(ErrorKind.Unavailable, "dataset closed")
}

static Error mlErrInvalid() {
    return new BasicError(ErrorKind.InvalidArgument, "sample index")
}

static Error mlErrIo() {
    return new BasicError(ErrorKind.Io, "dataset failure")
}

class MemoryDataset implements Dataset {
    final List<MlBatch> _samples
    Bool _open
    MemoryDataset(List<MlBatch> samples) {
        self._samples = samples.copy()
        self._open = true
    }
    Long size() { return self._samples.length() as Long }
    Result<MlBatch, Error> get(Context context, Long sampleIndex) {
        if !self._open {
            return Err(mlErrUnavailable())
        }
        if sampleIndex < 0 as Long || sampleIndex >= self._samples.length() as Long {
            return Err(mlErrInvalid())
        }
        return Ok(self._samples.get(sampleIndex as Int))
    }
    Bool isOpen() { return self._open }
    Result<Unit, Error> close() { self._open = false; return Ok() }
    String describe() { return "memory dataset size=" + str(self._samples.length()) }
}

class TraceTransform implements Transform {
    final String _label
    final List<String> _trace
    TraceTransform(String label, List<String> trace) {
        self._label = label
        self._trace = trace
    }
    Result<MlBatch, Error> apply(Context context, MlBatch batch) {
        self._trace.push(self._label)
        return Ok(batch)
    }
    String describe() { return "trace transform " + self._label }
}

class FlakyDataset implements Dataset {
    final MlBatch _sample
    Bool _fail
    FlakyDataset(MlBatch sample) { self._sample = sample; self._fail = true }
    Long size() { return 1 as Long }
    Result<MlBatch, Error> get(Context context, Long sampleIndex) {
        if self._fail {
            return Err(mlErrIo())
        }
        return Ok(self._sample)
    }
    Bool isOpen() { return true }
    Result<Unit, Error> close() { return Ok() }
    String describe() { return "flaky dataset" }
}

static MlBatch mlSample(Double value) {
    List<Int> dims = [1]
    List<Double> inputValue = []
    inputValue.push(value)
    Tensor input = TensorOps.fromDoubles(TensorDType.Float64, new TensorShape(dims),
        inputValue)
    List<Double> targetValue = []
    targetValue.push(value)
    Tensor target = TensorOps.fromDoubles(TensorDType.Float64, new TensorShape(dims),
        targetValue)
    List<Tensor> inputs = []
    inputs.push(input)
    List<Tensor> targets = []
    targets.push(target)
    return new MlBatch(1, inputs, targets)
}

static String mlValues(MlBatch batch) {
    List<Double> values = batch.input(0).toDoubles()
    String text = ""
    Int index = 0
    while index < values.length() {
        if index > 0 { text = text + "," }
        text = text + str(values.get(index))
        index = index + 1
    }
    return text
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

    List<MlBatch> samples = []
    samples.push(mlSample(0.0))
    samples.push(mlSample(1.0))
    samples.push(mlSample(2.0))
    samples.push(mlSample(3.0))
    MemoryDataset dataset = new MemoryDataset(samples)
    List<String> trace = []
    List<Transform> transforms = []
    transforms.push(new TraceTransform("t1", trace))
    transforms.push(new TraceTransform("t2", trace))
    DataLoader loader = new DataLoader(dataset, 2, false, transforms, null)
    print("loader=" + str(loader.batchCount()) + "," + loader.describe())
    MlBatch firstBatch = loader.next(Context.background()).value()
    String firstValues = mlValues(firstBatch)
    String firstTrace = trace.join(",")
    MlBatch secondBatch = loader.next(Context.background()).value()
    String secondValues = mlValues(secondBatch)
    Result<MlBatch, Error> exhausted = loader.next(Context.background())
    loader.beginEpoch()
    String restarted = mlValues(loader.next(Context.background()).value())
    print("loader-seq=" + firstValues + "," + secondValues + "," + firstTrace + "," +
        errorKindName(exhausted.error().kind()) + "," + restarted + "," +
        str(firstBatch.sampleCount()) + "," + str(firstBatch.hasTargets()) + "," +
        firstBatch.describe())

    List<Transform> noTransforms = []
    DataLoader shuffledOne = new DataLoader(dataset, 4, true, noTransforms,
        new Random(42 as Long))
    DataLoader shuffledTwo = new DataLoader(dataset, 4, true, noTransforms,
        new Random(42 as Long))
    shuffledOne.beginEpoch()
    shuffledTwo.beginEpoch()
    String shuffleOne = mlValues(shuffledOne.next(Context.background()).value())
    String shuffleTwo = mlValues(shuffledTwo.next(Context.background()).value())
    print("loader-shuffle=" + shuffleOne + "," + shuffleTwo + "," +
        str(shuffleOne == shuffleTwo))

    FlakyDataset flaky = new FlakyDataset(mlSample(9.0))
    DataLoader flakyLoader = new DataLoader(flaky, 1, false, noTransforms, null)
    Result<MlBatch, Error> failedOnce = flakyLoader.next(Context.background())
    Result<MlBatch, Error> failedTwice = flakyLoader.next(Context.background())
    flaky._fail = false
    Result<MlBatch, Error> recovered = flakyLoader.next(Context.background())
    print("loader-fail=" + errorKindName(failedOnce.error().kind()) + "," +
        errorKindName(failedTwice.error().kind()) + "," +
        mlValues(recovered.value()))

    List<Int> pairDims = [2]
    List<Double> pairValues = [7.0, 8.0]
    Tensor pair = TensorOps.fromDoubles(TensorDType.Float64, new TensorShape(pairDims),
        pairValues)
    List<Tensor> pairInputs = []
    pairInputs.push(pair)
    List<Tensor> noTargets = []
    MlBatch batch = new MlBatch(2, pairInputs, noTargets)
    MlBatch withTargets = batch.withTargets(pairInputs)
    print("batch=" + batch.describe() + "," + str(batch.inputCount()) + "," +
        str(batch.targetCount()) + "," + str(batch.hasTargets()) + "," +
        str(withTargets.hasTargets()) + "," +
        str(batch.input(0).tensorShape().dim(0)))

    Optimizer optimizer = new Optimizer(OptimizerKind.Adam, 0.001, 0.01, 0.9, 0.9,
        0.999, 0.00000001)
    print("optimizer=" + optimizer.describe() + "," +
        optimizerKindName(optimizer.kind()) + "," +
        str(optimizerKindUsesSecondMoment(optimizer.kind())) + "," +
        str(optimizerKindUsesSecondMoment(OptimizerKind.Sgd)) + "," +
        optimizerKindName(optimizerKindFromName(" RMSProp ")) + "," +
        optimizerKindName(optimizerKindFromName("bogus")) + "," +
        str(optimizer.copy().learningRate() == 0.001))

    Map<String, Double> metrics = [:]
    metrics.put("accuracy", 0.75)
    EpochStats stats = new EpochStats(3, true, 2 as Long, 4 as Long, 0.5, metrics,
        12 as Long)
    EpochStats emptyStats = new EpochStats(0, false, 0 as Long, 0 as Long, null,
        metrics, 0 as Long)
    print("epoch=" + stats.describe() + "," + str(stats.meanLossValue()) + "," +
        str(stats.metric("accuracy")) + "," + str(stats.metric("missing") == null) +
        "," + str(emptyStats.meanLoss() == null) + "," +
        str(emptyStats.hasMeanLoss()) + "," + lossKindName(LossKind.CrossEntropy) +
        "," + str(lossKindIsRegression(LossKind.MeanAbsoluteError)) + "," +
        lossKindName(lossKindFromName("bogus")))

    List<Int> lossShape = [2]
    List<Double> predictionValues = [1.0, 2.0]
    List<Double> targetValues = [3.0, 4.0]
    Tensor predictions = TensorOps.fromDoubles(TensorDType.Float64,
        new TensorShape(lossShape), predictionValues)
    Tensor lossTargets = TensorOps.fromDoubles(TensorDType.Float64,
        new TensorShape(lossShape), targetValues)
    Tensor mse = Ml.computeLoss(Context.background(), LossKind.MeanSquaredError,
        predictions, lossTargets).value()
    Tensor mae = Ml.computeLoss(Context.background(), LossKind.MeanAbsoluteError,
        predictions, lossTargets).value()
    List<Int> logitShape = [1, 2]
    List<Double> logitValues = [0.0, 0.0]
    Tensor logits = TensorOps.fromDoubles(TensorDType.Float64,
        new TensorShape(logitShape), logitValues)
    List<Int> indexShape = [1]
    List<Double> indexValues = [0.0]
    Tensor index = TensorOps.fromDoubles(TensorDType.Int64,
        new TensorShape(indexShape), indexValues)
    Tensor ce = Ml.computeLoss(Context.background(), LossKind.CrossEntropy,
        logits, index).value()
    List<Double> stableValues = [1000.0, 0.0]
    Tensor stableLogits = TensorOps.fromDoubles(TensorDType.Float64,
        new TensorShape(logitShape), stableValues)
    Tensor stableCe = Ml.computeLoss(Context.background(), LossKind.CrossEntropy,
        stableLogits, index).value()
    List<Double> probabilityValues = [0.5, 0.5]
    List<Double> binaryValues = [1.0, 0.0]
    Tensor probabilities = TensorOps.fromDoubles(TensorDType.Float64,
        new TensorShape(lossShape), probabilityValues)
    Tensor binaryTargets = TensorOps.fromDoubles(TensorDType.Float64,
        new TensorShape(lossShape), binaryValues)
    Tensor bce = Ml.computeLoss(Context.background(), LossKind.BinaryCrossEntropy,
        probabilities, binaryTargets).value()
    List<Double> nllValues = [-0.5, -1.5]
    Tensor nllPredictions = TensorOps.fromDoubles(TensorDType.Float64,
        new TensorShape(logitShape), nllValues)
    List<Double> nllIndexValues = [1.0]
    Tensor nllIndex = TensorOps.fromDoubles(TensorDType.Int64,
        new TensorShape(indexShape), nllIndexValues)
    Tensor nll = Ml.computeLoss(Context.background(), LossKind.NegativeLogLikelihood,
        nllPredictions, nllIndex).value()
    List<Int> emptyShape = [0]
    List<Double> emptyValues = []
    Tensor emptyTensor = TensorOps.fromDoubles(TensorDType.Float64,
        new TensorShape(emptyShape), emptyValues)
    Result<Tensor, Error> emptyLoss = Ml.computeLoss(Context.background(),
        LossKind.MeanSquaredError, emptyTensor, emptyTensor)
    Result<Tensor, Error> otherLoss = Ml.computeLoss(Context.background(),
        LossKind.Other, predictions, lossTargets)
    List<Double> badIndexValues = [5.0]
    Tensor badIndex = TensorOps.fromDoubles(TensorDType.Int64,
        new TensorShape(indexShape), badIndexValues)
    Result<Tensor, Error> badIndexLoss = Ml.computeLoss(Context.background(),
        LossKind.CrossEntropy, logits, badIndex)
    Context lossCancelled = Context.background()
    lossCancelled.cancel()
    Result<Tensor, Error> cancelledLoss = Ml.computeLoss(lossCancelled,
        LossKind.MeanSquaredError, predictions, lossTargets)
    print("loss=" + str(mse.atFlat(0)) + "," + str(mae.atFlat(0)) + "," +
        str(ce.atFlat(0)) + "," + str(stableCe.atFlat(0)) + "," +
        str(bce.atFlat(0)) + "," + str(nll.atFlat(0)) + "," +
        errorKindName(emptyLoss.error().kind()) + "," +
        errorKindName(otherLoss.error().kind()) + "," +
        errorKindName(badIndexLoss.error().kind()) + "," +
        errorKindName(cancelledLoss.error().kind()))
    return 0
}
