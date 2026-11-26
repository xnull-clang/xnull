#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ml-panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.ml
import xdk.ml
import xdk.tensor
import xdk.errors

static Tensor panicTensor() {
    List<Int> dims = [1]
    return new Tensor(TensorDType.Float64, new TensorShape(dims), Bytes.alloc(8))
}

static ModelMetadata panicMetadata() {
    Map<String, String> extra = [:]
    return new ModelMetadata("m", "1", "", "", "", MlTask.Other, "", extra)
}

static Model panicModel() {
    List<Int> dims = [1]
    List<Bool> flags = [false]
    ModelInput input = new ModelInput("x", TensorDType.Float64, dims, flags)
    ModelOutput output = new ModelOutput("y", TensorDType.Float64, dims, flags)
    List<ModelInput> inputs = []
    inputs.push(input)
    List<ModelOutput> outputs = []
    outputs.push(output)
    return new Model(ModelFormat.Onnx, panicMetadata(), inputs, outputs,
        Bytes.fromString("p"))
}

static InferenceSession panicSession() {
    return new InferenceSession(1 as Long, panicModel(), SessionOptions.defaults())
}

static Int main(String[] args) {
    String name = args.get(0)
    if name == "inputName" {
        List<Int> dims = [1]
        List<Bool> flags = [false]
        ModelInput value = new ModelInput("", TensorDType.Float64, dims, flags)
    } else if name == "inputNullDims" {
        List<Bool> flags = [false]
        ModelInput value = new ModelInput("x", TensorDType.Float64, null, flags)
    } else if name == "inputLength" {
        List<Int> dims = [1, 2]
        List<Bool> flags = [false]
        ModelInput value = new ModelInput("x", TensorDType.Float64, dims, flags)
    } else if name == "inputNegative" {
        List<Int> dims = [-1]
        List<Bool> flags = [false]
        ModelInput value = new ModelInput("x", TensorDType.Float64, dims, flags)
    } else if name == "inputDynamic" {
        List<Int> dims = [3]
        List<Bool> flags = [true]
        ModelInput value = new ModelInput("x", TensorDType.Float64, dims, flags)
    } else if name == "outputName" {
        List<Int> dims = [1]
        List<Bool> flags = [false]
        ModelOutput value = new ModelOutput("", TensorDType.Float64, dims, flags)
    } else if name == "outputDynamic" {
        List<Int> dims = [2]
        List<Bool> flags = [true]
        ModelOutput value = new ModelOutput("y", TensorDType.Float64, dims, flags)
    } else if name == "metadataName" {
        Map<String, String> extra = [:]
        ModelMetadata value = new ModelMetadata("", "1", "", "", "", MlTask.Other, "", extra)
    } else if name == "metadataNull" {
        Map<String, String> extra = [:]
        ModelMetadata value = new ModelMetadata("m", null, "", "", "", MlTask.Other, "", extra)
    } else if name == "metadataKey" {
        Map<String, String> extra = [:]
        extra.put("", "v")
        ModelMetadata value = new ModelMetadata("m", "1", "", "", "", MlTask.Other, "", extra)
    } else if name == "modelPayload" {
        List<Int> dims = [1]
        List<Bool> flags = [false]
        ModelInput input = new ModelInput("x", TensorDType.Float64, dims, flags)
        ModelOutput output = new ModelOutput("y", TensorDType.Float64, dims, flags)
        List<ModelInput> inputs = []
        inputs.push(input)
        List<ModelOutput> outputs = []
        outputs.push(output)
        Model value = new Model(ModelFormat.Onnx, panicMetadata(), inputs, outputs,
            Bytes.alloc(0))
    } else if name == "modelDuplicateInput" {
        List<Int> dims = [1]
        List<Bool> flags = [false]
        ModelInput one = new ModelInput("x", TensorDType.Float64, dims, flags)
        ModelInput two = new ModelInput("x", TensorDType.Float64, dims, flags)
        List<ModelInput> inputs = []
        inputs.push(one)
        inputs.push(two)
        List<ModelOutput> outputs = []
        outputs.push(new ModelOutput("y", TensorDType.Float64, dims, flags))
        Model value = new Model(ModelFormat.Onnx, panicMetadata(), inputs, outputs,
            Bytes.fromString("p"))
    } else if name == "optionsEmpty" {
        List<ExecutionProvider> providers = []
        Map<String, String> extra = [:]
        SessionOptions value = new SessionOptions(providers, 0, 0, true, true, false,
            false, true, 0 as Long, extra)
    } else if name == "optionsDuplicate" {
        List<ExecutionProvider> providers = []
        providers.push(ExecutionProvider.Cpu)
        providers.push(ExecutionProvider.Cpu)
        Map<String, String> extra = [:]
        SessionOptions value = new SessionOptions(providers, 0, 0, true, true, false,
            false, true, 0 as Long, extra)
    } else if name == "optionsThreads" {
        List<ExecutionProvider> providers = []
        providers.push(ExecutionProvider.Cpu)
        Map<String, String> extra = [:]
        SessionOptions value = new SessionOptions(providers, -1, 0, true, true, false,
            false, true, 0 as Long, extra)
    } else if name == "optionsMemory" {
        List<ExecutionProvider> providers = []
        providers.push(ExecutionProvider.Cpu)
        Map<String, String> extra = [:]
        SessionOptions value = new SessionOptions(providers, 0, 0, true, true, false,
            false, true, -1 as Long, extra)
    } else if name == "optionsKey" {
        List<ExecutionProvider> providers = []
        providers.push(ExecutionProvider.Cpu)
        Map<String, String> extra = [:]
        extra.put(" bad", "v")
        SessionOptions value = new SessionOptions(providers, 0, 0, true, true, false,
            false, true, 0 as Long, extra)
    } else if name == "optionsUnknown" {
        List<ExecutionProvider> providers = []
        providers.push(ExecutionProvider.Unknown)
        Map<String, String> extra = [:]
        SessionOptions value = new SessionOptions(providers, 0, 0, true, true, false,
            false, true, 0 as Long, extra)
    } else if name == "sessionHandle" {
        InferenceSession value = new InferenceSession(0 as Long, panicModel(),
            SessionOptions.defaults())
    } else if name == "sessionModel" {
        InferenceSession value = new InferenceSession(1 as Long, null,
            SessionOptions.defaults())
    } else if name == "resultEmpty" {
        List<Tensor> outputs = []
        List<String> names = []
        InferenceResult value = new InferenceResult(outputs, names, 0 as Long)
    } else if name == "resultLength" {
        List<Tensor> outputs = []
        outputs.push(panicTensor())
        List<String> names = []
        InferenceResult value = new InferenceResult(outputs, names, 0 as Long)
    } else if name == "resultName" {
        List<Tensor> outputs = []
        outputs.push(panicTensor())
        List<String> names = []
        names.push("")
        InferenceResult value = new InferenceResult(outputs, names, 0 as Long)
    } else if name == "resultElapsed" {
        List<Tensor> outputs = []
        outputs.push(panicTensor())
        List<String> names = []
        names.push("y")
        InferenceResult value = new InferenceResult(outputs, names, -1 as Long)
    } else if name == "resultIndex" {
        InferenceSession session = panicSession()
        List<Tensor> outputs = []
        outputs.push(panicTensor())
        List<String> names = []
        names.push("y")
        InferenceResult result = new InferenceResult(outputs, names, 0 as Long)
        Tensor value = result.output(3)
    } else if name == "openModel" {
        Result<InferenceSession, Error> value = Ml.openSession(Context.background(),
            null, SessionOptions.defaults())
    } else if name == "runSession" {
        List<Tensor> inputs = []
        Result<InferenceResult, Error> value = Ml.run(Context.background(), null, inputs)
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || { cat "$TMP/build.err" >&2; exit 1; }
check_panic() {
    name=$1; marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && { echo "ml panic: $name did not fail" >&2; exit 1; }
    grep -Fq "$marker" "$TMP/$name.err" || { echo "ml panic: $name missing '$marker'" >&2; cat "$TMP/$name.err" >&2; exit 1; }
}
check_panic inputName "ModelInput: empty name"
check_panic inputNullDims "ModelInput: null dimensions"
check_panic inputLength "ModelInput: dimension/flag length mismatch"
check_panic inputNegative "ModelInput: negative dimension"
check_panic inputDynamic "ModelInput: dynamic dimension must be zero"
check_panic outputName "ModelOutput: empty name"
check_panic outputDynamic "ModelOutput: dynamic dimension must be zero"
check_panic metadataName "ModelMetadata: empty name"
check_panic metadataNull "ModelMetadata: null field"
check_panic metadataKey "ModelMetadata: empty metadata key"
check_panic modelPayload "Model: empty payload"
check_panic modelDuplicateInput "Model: duplicate input name"
check_panic optionsEmpty "SessionOptions: empty providers"
check_panic optionsDuplicate "SessionOptions: duplicate provider"
check_panic optionsThreads "SessionOptions: negative thread count"
check_panic optionsMemory "SessionOptions: negative memory limit"
check_panic optionsKey "SessionOptions: invalid provider option key"
check_panic optionsUnknown "SessionOptions: unknown provider"
check_panic sessionHandle "InferenceSession: invalid handle"
check_panic sessionModel "InferenceSession: null argument"
check_panic resultEmpty "InferenceResult: output/name length mismatch"
check_panic resultLength "InferenceResult: output/name length mismatch"
check_panic resultName "InferenceResult: empty output name"
check_panic resultElapsed "InferenceResult: negative elapsed"
check_panic resultIndex "InferenceResult.output: index out of range"
check_panic openModel "Ml.openSession: null argument"
check_panic runSession "Ml.run: null argument"
echo "ml_panic: PASS"
