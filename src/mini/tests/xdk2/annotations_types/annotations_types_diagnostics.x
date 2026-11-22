// B2 场景：元素视图、诊断、处理器上下文/结果与非泛型处理器协议。
import xdk.annotations

static Map<String, AnnotationValue> emptyValues() {
    Map<String, AnnotationValue> values = [:]
    return values
}

static AnnotationInfo marker() {
    return new AnnotationInfo(
        "app.Marker",
        AnnotationTarget.Type,
        "app.Device",
        emptyValues(),
        1
    )
}

static AnnotationSet markerSet() {
    List<AnnotationInfo> items = []
    items.push(marker())
    return new AnnotationSet(items)
}

static AnnotationElement deviceElement() {
    return new AnnotationElement(
        AnnotationTarget.Type,
        "app",
        "Device",
        "app.Device",
        markerSet(),
        "app/Device.x"
    )
}


static AnnotationProcessorPhase validatePhase() {
    return AnnotationProcessorPhase.Validate
}

static AnnotationProcessorPhase generatePhase() {
    return AnnotationProcessorPhase.Generate
}

static Bool isGenerateContext(AnnotationProcessorContext context) {
    return context.phase() == AnnotationProcessorPhase.Generate
}

static AnnotationProcessingResult emptyProcessingResult() {
    return AnnotationProcessingResult.empty()
}

static AnnotationProcessingResult generateResult() {
    List<AnnotationDiagnostic> diagnostics = []
    diagnostics.push(new AnnotationDiagnostic(
        AnnotationDiagnosticSeverity.Note,
        "ANN100",
        "generated device metadata",
        "app.Device"
    ))
    Map<String, String> sources = [:]
    sources.put("app/generated/DeviceMeta.x", "class DeviceMeta { }")
    return new AnnotationProcessingResult(diagnostics, sources)
}

class TestProcessor implements AnnotationProcessor {
    TestProcessor() {
    }

    String name() {
        return "test.processor"
    }

    List<AnnotationProcessorPhase> phases() {
        List<AnnotationProcessorPhase> phases = []
        phases.push(validatePhase())
        phases.push(generatePhase())
        return phases
    }

    AnnotationProcessingResult process(AnnotationProcessorContext context) {
        if isGenerateContext(context) {
            return generateResult()
        }
        return emptyProcessingResult()
    }
}

static Int main() {
    // 处理器阶段枚举：4 个成员。
    print(AnnotationProcessorPhase.Resolve == AnnotationProcessorPhase.Resolve)
    print(AnnotationProcessorPhase.Validate == AnnotationProcessorPhase.Validate)
    print(AnnotationProcessorPhase.Generate == AnnotationProcessorPhase.Generate)
    print(AnnotationProcessorPhase.Finalize == AnnotationProcessorPhase.Finalize)
    print(AnnotationProcessorPhase.Resolve != AnnotationProcessorPhase.Finalize)

    // 诊断级别枚举与 describe 文本。
    print(AnnotationDiagnosticSeverity.Error == AnnotationDiagnosticSeverity.Error)
    print(AnnotationDiagnosticSeverity.Warning == AnnotationDiagnosticSeverity.Warning)
    print(AnnotationDiagnosticSeverity.Note == AnnotationDiagnosticSeverity.Note)

    AnnotationDiagnostic error = new AnnotationDiagnostic(
        AnnotationDiagnosticSeverity.Error,
        "  ANN001  ",
        "  unknown annotation  ",
        "  app.Device  "
    )
    print(error.severity() == AnnotationDiagnosticSeverity.Error)
    print(error.code())
    print(error.message())
    print(error.elementName())
    print(error.describe())

    AnnotationDiagnostic warning = new AnnotationDiagnostic(
        AnnotationDiagnosticSeverity.Warning,
        "ANN010",
        "optional field omitted",
        ""
    )
    print(warning.describe())

    AnnotationDiagnostic note = new AnnotationDiagnostic(
        AnnotationDiagnosticSeverity.Note,
        "ANN020",
        "generated source",
        "app.Device"
    )
    print(note.describe())

    // 元素视图：类型元素与包元素。
    AnnotationElement device = deviceElement()
    print(device.target() == AnnotationTarget.Type)
    print(device.ownerName())
    print(device.name())
    print(device.typeName())
    print(device.sourceName())
    print(device.hasAnnotation("app.Marker"))
    print(device.hasAnnotation("app.Other"))
    print(device.annotations().length())
    AnnotationInfo? first = device.firstAnnotation("app.Marker")
    print(first != null)
    print(device.describe())

    AnnotationElement packageElement = new AnnotationElement(
        AnnotationTarget.Package,
        "",
        "app.device",
        "app.device",
        AnnotationSet.empty(),
        "app/Package.x"
    )
    print(packageElement.target() == AnnotationTarget.Package)
    print(packageElement.annotations().isEmpty())
    print(packageElement.describe())

    // 枚举 0 号成员不是 null：Resolve / Package / Error / Bool 均可构造。
    List<AnnotationElement> noElements = []
    Map<String, String> noOptions = [:]
    AnnotationProcessorContext resolveContext = new AnnotationProcessorContext(
        AnnotationProcessorPhase.Resolve,
        noElements,
        noOptions
    )
    print(resolveContext.phase() == AnnotationProcessorPhase.Resolve)
    print(resolveContext.elements().length() == 0)

    // 处理器上下文：阶段、元素快照、选项快照。
    List<AnnotationElement> elements = []
    elements.push(device)
    Map<String, String> options = [:]
    options.put("strict", "true")
    options.put("generatedPackage", "")
    AnnotationProcessorContext context = new AnnotationProcessorContext(
        AnnotationProcessorPhase.Validate,
        elements,
        options
    )
    print(context.phase() == AnnotationProcessorPhase.Validate)
    print(context.elements().length())
    print(context.hasOption("strict"))
    print(context.hasOption("generatedPackage"))
    print(context.hasOption("missing"))
    print(context.optionOr("strict", "false"))
    String emptyOption = context.optionOr("generatedPackage", "fallback")
    print(emptyOption == "")
    print(context.optionOr("missing", "false"))

    elements.push(device)
    print(context.elements().length())
    List<AnnotationElement> elementCopy = context.elements()
    elementCopy.push(device)
    print(context.elements().length())

    Map<String, String> optionCopy = context.options()
    optionCopy.put("added", "yes")
    print(context.hasOption("added"))
    print(optionCopy.length())

    // 处理结果：success 只由 Error 决定；诊断顺序与副本独立。
    AnnotationProcessingResult emptyResult = AnnotationProcessingResult.empty()
    print(emptyResult.success())
    print(emptyResult.diagnostics().length())
    print(emptyResult.generatedSources().length())

    List<AnnotationDiagnostic> warningOnly = []
    warningOnly.push(warning)
    Map<String, String> noSources = [:]
    AnnotationProcessingResult warningResult = new AnnotationProcessingResult(warningOnly, noSources)
    print(warningResult.success())

    List<AnnotationDiagnostic> noteOnly = []
    noteOnly.push(note)
    AnnotationProcessingResult noteResult = new AnnotationProcessingResult(noteOnly, noSources)
    print(noteResult.success())

    List<AnnotationDiagnostic> mixedDiagnostics = []
    mixedDiagnostics.push(error)
    mixedDiagnostics.push(warning)
    mixedDiagnostics.push(note)
    Map<String, String> generated = [:]
    generated.put("app/generated/Device.x", "class DeviceGenerated { }")
    generated.put("app/generated/Color.x", "class ColorGenerated { }")
    AnnotationProcessingResult mixed = new AnnotationProcessingResult(mixedDiagnostics, generated)
    print(mixed.success())
    print(mixed.diagnostics().length())
    print(mixed.diagnostics().get(0).code())
    print(mixed.diagnostics().get(1).code())
    print(mixed.diagnostics().get(2).code())
    print(mixed.generatedSources().length())
    String deviceSource = mixed.generatedSources().getOr("app/generated/Device.x", "")
    print(deviceSource)

    mixedDiagnostics.push(note)
    print(mixed.diagnostics().length())
    List<AnnotationDiagnostic> diagnosticCopy = mixed.diagnostics()
    diagnosticCopy.push(note)
    print(mixed.diagnostics().length())
    Map<String, String> sourceCopy = mixed.generatedSources()
    sourceCopy.put("app/generated/Extra.x", "class Extra { }")
    print(mixed.generatedSources().length())
    print(sourceCopy.length())

    // 非泛型处理器协议：名称、阶段声明、按阶段处理。
    AnnotationProcessor processor = new TestProcessor()
    print(processor.name())
    print(processor.phases().length())
    print(processor.phases().get(0) == AnnotationProcessorPhase.Validate)
    print(processor.phases().get(1) == AnnotationProcessorPhase.Generate)
    AnnotationProcessingResult validateResult = processor.process(context)
    print(validateResult.success())
    print(validateResult.diagnostics().length())

    List<AnnotationElement> generateElements = []
    generateElements.push(device)
    Map<String, String> generateOptions = [:]
    AnnotationProcessorContext generateContext = new AnnotationProcessorContext(
        AnnotationProcessorPhase.Generate,
        generateElements,
        generateOptions
    )
    AnnotationProcessingResult generateResult = processor.process(generateContext)
    print(generateResult.success())
    print(generateResult.diagnostics().length())
    print(generateResult.diagnostics().get(0).severity() == AnnotationDiagnosticSeverity.Note)
    print(generateResult.diagnostics().get(0).code())
    print(generateResult.generatedSources().length())
    print(generateResult.generatedSources().has("app/generated/DeviceMeta.x"))
    return 0
}
