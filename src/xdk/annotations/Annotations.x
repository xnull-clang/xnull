// xdk.annotations —— 注解元模型、只读注册表与处理器合同（B2.1/B2.2）。
// Tier: L0；依赖：语言核心标量与容器；稳定性：preview。
//
// 边界：
//   - 只定义元模型、处理器合同与编译器生成的只读注册表；
//   - 不做运行时反射、类路径扫描、动态代理、注解类加载；
//   - 值树、集合、元素、上下文、结果与注册表构造后不可变；
//   - 注册表只读查询，不提供动态注册入口。
package xdk.annotations
import xdk.collections

enum AnnotationTarget {
    Package,
    Type,
    Annotation,
    TypeParameter,
    Field,
    Method,
    Constructor,
    Deinit,
    Parameter,
    TypeUse,
    EnumItem,
}

enum AnnotationRetention {
    Source,
    Binary,
    Runtime,
}

enum AnnotationValueKind {
    Bool,
    Int,
    Long,
    Float,
    Double,
    Char,
    String,
    Enum,
    Type,
    Array,
    Annotation,
    Null,
}

enum AnnotationDiagnosticSeverity {
    Error,
    Warning,
    Note,
}

enum AnnotationProcessorPhase {
    Resolve,
    Validate,
    Generate,
    Finalize,
}

// 不可变注解常量值树节点：标签 + 对应负载。
// 工厂是唯一公开构造入口；不匹配的访问器返回 null，不抛异常。
// 说明：mini 暂不支持 Float 作为通用类型，Float 标签以 Double 负载承载；
// 该差异记录在 B2 批末 BLOCKED 证据中，访问器语义保持不变。
class AnnotationValue {
    final AnnotationValueKind _kind
    final Bool? _boolValue
    final Int? _intValue
    final Long? _longValue
    final Double? _floatValue
    final Double? _doubleValue
    final Char? _charValue
    final String? _stringValue
    final String? _enumTypeName
    final String? _enumItemName
    final String? _typeName
    final List<AnnotationValue> _arrayValue
    final AnnotationInfo? _annotationValue

    private AnnotationValue(AnnotationValueKind kind, Bool? boolValue, Int? intValue,
                            Long? longValue, Double? floatValue, Double? doubleValue,
                            Char? charValue, String? stringValue, String? enumTypeName,
                            String? enumItemName, String? typeName,
                            List<AnnotationValue>? arrayValue,
                            AnnotationInfo? annotationValue) {
        self._kind = kind
        self._boolValue = boolValue
        self._intValue = intValue
        self._longValue = longValue
        self._floatValue = floatValue
        self._doubleValue = doubleValue
        self._charValue = charValue
        self._stringValue = stringValue
        self._enumTypeName = enumTypeName
        self._enumItemName = enumItemName
        self._typeName = typeName
        List<AnnotationValue> array = []
        self._arrayValue = array
        if arrayValue != null {
            List<AnnotationValue> items = arrayValue as List<AnnotationValue>
            Int index = 0
            while index < items.length() {
                AnnotationValue item = items.get(index)
                if item == null {
                    throw "AnnotationValue: null array item"
                }
                self._arrayValue.push(item)
                index = index + 1
            }
        }
        self._annotationValue = annotationValue
    }

    static AnnotationValue ofBool(Bool value) {
        return new AnnotationValue(
            AnnotationValueKind.Bool,
            value, null, null, null, null, null, null, null, null, null, null, null
        )
    }

    static AnnotationValue ofInt(Int value) {
        return new AnnotationValue(
            AnnotationValueKind.Int,
            null, value, null, null, null, null, null, null, null, null, null, null
        )
    }

    static AnnotationValue ofLong(Long value) {
        return new AnnotationValue(
            AnnotationValueKind.Long,
            null, null, value, null, null, null, null, null, null, null, null, null
        )
    }

    // mini 无 Float 类型；以 Double 承载 Float 标签。
    static AnnotationValue ofFloat(Double value) {
        return new AnnotationValue(
            AnnotationValueKind.Float,
            null, null, null, value, null, null, null, null, null, null, null, null
        )
    }

    static AnnotationValue ofDouble(Double value) {
        return new AnnotationValue(
            AnnotationValueKind.Double,
            null, null, null, null, value, null, null, null, null, null, null, null
        )
    }

    static AnnotationValue ofChar(Char value) {
        return new AnnotationValue(
            AnnotationValueKind.Char,
            null, null, null, null, null, value, null, null, null, null, null, null
        )
    }

    static AnnotationValue ofString(String value) {
        if value == null {
            throw "AnnotationValue.ofString: null value"
        }
        return new AnnotationValue(
            AnnotationValueKind.String,
            null, null, null, null, null, null, value, null, null, null, null, null
        )
    }

    static AnnotationValue ofEnum(String enumTypeName, String enumItemName) {
        if enumTypeName == null || enumTypeName == "" {
            throw "AnnotationValue.ofEnum: empty enum type name"
        }
        if enumItemName == null || enumItemName == "" {
            throw "AnnotationValue.ofEnum: empty enum item name"
        }
        return new AnnotationValue(
            AnnotationValueKind.Enum,
            null, null, null, null, null, null, null,
            enumTypeName, enumItemName, null, null, null
        )
    }

    static AnnotationValue ofType(String typeName) {
        if typeName == null || typeName == "" {
            throw "AnnotationValue.ofType: empty type name"
        }
        return new AnnotationValue(
            AnnotationValueKind.Type,
            null, null, null, null, null, null, null,
            null, null, typeName, null, null
        )
    }

    static AnnotationValue ofArray(List<AnnotationValue> values) {
        if values == null {
            throw "AnnotationValue.ofArray: null values"
        }
        return new AnnotationValue(
            AnnotationValueKind.Array,
            null, null, null, null, null, null, null,
            null, null, null, values, null
        )
    }

    static AnnotationValue ofAnnotation(AnnotationInfo annotation) {
        if annotation == null {
            throw "AnnotationValue.ofAnnotation: null annotation"
        }
        return new AnnotationValue(
            AnnotationValueKind.Annotation,
            null, null, null, null, null, null, null,
            null, null, null, null, annotation
        )
    }

    static AnnotationValue nullValue() {
        return new AnnotationValue(
            AnnotationValueKind.Null,
            null, null, null, null, null, null, null,
            null, null, null, null, null
        )
    }

    AnnotationValueKind kind() {
        return self._kind
    }

    Bool isNull() {
        return self._kind == AnnotationValueKind.Null
    }

    Bool? asBool() {
        return self._boolValue
    }

    Int? asInt() {
        return self._intValue
    }

    Long? asLong() {
        return self._longValue
    }

    // 与 ofFloat 一致：Float 标签的负载以 Double 返回。
    Double? asFloat() {
        return self._floatValue
    }

    Double? asDouble() {
        return self._doubleValue
    }

    Char? asChar() {
        return self._charValue
    }

    String? asString() {
        return self._stringValue
    }

    String? enumTypeName() {
        return self._enumTypeName
    }

    String? enumItemName() {
        return self._enumItemName
    }

    String? asTypeName() {
        return self._typeName
    }

    List<AnnotationValue>? asArray() {
        if self._kind != AnnotationValueKind.Array {
            return null
        }
        return self._arrayValue.copy()
    }

    AnnotationInfo? asAnnotation() {
        return self._annotationValue
    }

    String describe() {
        return annotationsValueDescribe(self)
    }
}

// 单个注解使用点的不可变快照。
class AnnotationInfo {
    final String _typeName
    final AnnotationTarget _target
    final String _targetName
    final Map<String, AnnotationValue> _values
    final Int _repeatIndex

    AnnotationInfo(String typeName, AnnotationTarget target, String targetName,
                   Map<String, AnnotationValue> values, Int repeatIndex) {
        if typeName == null || typeName == "" {
            throw "AnnotationInfo: empty type name"
        }
        if targetName == null || targetName == "" {
            throw "AnnotationInfo: empty target name"
        }
        if values == null {
            throw "AnnotationInfo: null values"
        }
        if repeatIndex < 1 {
            throw "AnnotationInfo: invalid repeat index"
        }
        self._typeName = typeName
        self._target = target
        self._targetName = targetName
        self._repeatIndex = repeatIndex
        Map<String, AnnotationValue> copiedValues = [:]
        self._values = copiedValues
        List<String> names = values.keys()
        Int index = 0
        while index < names.length() {
            String name = names.get(index)
            if name == null || name == "" {
                throw "AnnotationInfo: empty value name"
            }
            AnnotationValue value = values.getOr(name, AnnotationValue.nullValue())
            if value == null {
                throw "AnnotationInfo: null value"
            }
            self._values.put(name, value)
            index = index + 1
        }
    }

    String typeName() {
        return self._typeName
    }

    AnnotationTarget target() {
        return self._target
    }

    String targetName() {
        return self._targetName
    }

    Map<String, AnnotationValue> values() {
        Map<String, AnnotationValue> result = [:]
        List<String> names = self._values.keys()
        Int index = 0
        while index < names.length() {
            String name = names.get(index)
            result.put(name, self._values.getOr(name, AnnotationValue.nullValue()))
            index = index + 1
        }
        return result
    }

    AnnotationValue? valueOrNull(String name) {
        if name == null || name == "" {
            throw "AnnotationInfo.valueOrNull: empty name"
        }
        if !self._values.has(name) {
            return null
        }
        return self._values.getOr(name, AnnotationValue.nullValue())
    }

    Bool hasValue(String name) {
        if name == null || name == "" {
            throw "AnnotationInfo.hasValue: empty name"
        }
        return self._values.has(name)
    }

    Int repeatIndex() {
        return self._repeatIndex
    }

    String describe() {
        return annotationsInfoDescribe(self)
    }
}

// 同一目标上的有序不可变注解集合。
class AnnotationSet {
    final List<AnnotationInfo> _annotations

    AnnotationSet(List<AnnotationInfo> annotations) {
        if annotations == null {
            throw "AnnotationSet: null annotations"
        }
        List<AnnotationInfo> copied = []
        self._annotations = copied
        Int index = 0
        while index < annotations.length() {
            AnnotationInfo annotation = annotations.get(index)
            if annotation == null {
                throw "AnnotationSet: null annotation"
            }
            if self._annotations.length() > 0 {
                AnnotationInfo reference = self._annotations.get(0)
                if annotation.target() != reference.target() {
                    throw "AnnotationSet: mixed targets"
                }
                if annotation.targetName() != reference.targetName() {
                    throw "AnnotationSet: mixed target names"
                }
            }
            Int scan = 0
            while scan < self._annotations.length() {
                AnnotationInfo existing = self._annotations.get(scan)
                if existing.typeName() == annotation.typeName() &&
                   existing.repeatIndex() == annotation.repeatIndex() {
                    throw "AnnotationSet: duplicate annotation use"
                }
                scan = scan + 1
            }
            self._annotations.push(annotation)
            index = index + 1
        }
    }

    static AnnotationSet empty() {
        List<AnnotationInfo> empty = []
        return new AnnotationSet(empty)
    }

    AnnotationInfo? first(String typeName) {
        if typeName == null || typeName == "" {
            throw "AnnotationSet.first: empty type name"
        }
        Int index = 0
        while index < self._annotations.length() {
            if self._annotations.get(index).typeName() == typeName {
                return self._annotations.get(index)
            }
            index = index + 1
        }
        return null
    }

    List<AnnotationInfo> all(String typeName) {
        if typeName == null || typeName == "" {
            throw "AnnotationSet.all: empty type name"
        }
        List<AnnotationInfo> result = []
        Int index = 0
        while index < self._annotations.length() {
            if self._annotations.get(index).typeName() == typeName {
                result.push(self._annotations.get(index))
            }
            index = index + 1
        }
        return result
    }

    AnnotationSet byTypeName(String typeName) {
        if typeName == null || typeName == "" {
            throw "AnnotationSet.byTypeName: empty type name"
        }
        return new AnnotationSet(self.all(typeName))
    }

    Bool has(String typeName) {
        if typeName == null || typeName == "" {
            throw "AnnotationSet.has: empty type name"
        }
        return self.first(typeName) != null
    }

    Int length() {
        return self._annotations.length()
    }

    Bool isEmpty() {
        return self._annotations.length() == 0
    }

    AnnotationSet merge(AnnotationSet other) {
        if other == null {
            throw "AnnotationSet.merge: null other"
        }
        if !self.isEmpty() && !other.isEmpty() {
            AnnotationInfo selfFirst = self._annotations.get(0)
            AnnotationInfo otherFirst = other.toList().get(0)
            if selfFirst.target() != otherFirst.target() {
                throw "AnnotationSet.merge: mixed targets"
            }
            if selfFirst.targetName() != otherFirst.targetName() {
                throw "AnnotationSet.merge: mixed target names"
            }
        }
        List<AnnotationInfo> next = self.toList()
        List<AnnotationInfo> incoming = other.toList()
        Int index = 0
        while index < incoming.length() {
            AnnotationInfo candidate = incoming.get(index)
            Bool exists = false
            Int scan = 0
            while scan < next.length() {
                AnnotationInfo existing = next.get(scan)
                if existing.typeName() == candidate.typeName() &&
                   existing.repeatIndex() == candidate.repeatIndex() {
                    exists = true
                    break
                }
                scan = scan + 1
            }
            if !exists {
                next.push(candidate)
            }
            index = index + 1
        }
        return new AnnotationSet(next)
    }

    List<AnnotationInfo> toList() {
        return self._annotations.copy()
    }

    String describe() {
        String result = ""
        Int index = 0
        while index < self._annotations.length() {
            if index > 0 {
                result = result + ", "
            }
            result = result + self._annotations.get(index).describe()
            index = index + 1
        }
        return result
    }
}

// 编译器生成的只读注解元数据注册表。
// 构造参数是扁平 AnnotationInfo 列表；构造时按 target + targetName 分组。
class AnnotationRegistry {
    final Map<String, AnnotationSet> _targets

    AnnotationRegistry(List<AnnotationInfo> annotations) {
        if annotations == null {
            throw "AnnotationRegistry: null annotations"
        }
        Map<String, List<AnnotationInfo>> grouped = [:]
        List<String> order = []
        List<AnnotationInfo> emptyBucket = []
        Int index = 0
        while index < annotations.length() {
            AnnotationInfo annotation = annotations.get(index)
            if annotation == null {
                throw "AnnotationRegistry: null annotation"
            }
            String key = annotationsTargetKey(annotation.target(), annotation.targetName())
            if !grouped.has(key) {
                List<AnnotationInfo> bucket = []
                grouped.put(key, bucket)
                order.push(key)
            }
            List<AnnotationInfo> bucket = grouped.getOr(key, emptyBucket)
            bucket.push(annotation)
            index = index + 1
        }
        Map<String, AnnotationSet> targets = [:]
        self._targets = targets
        Int orderIndex = 0
        while orderIndex < order.length() {
            String key = order.get(orderIndex)
            self._targets.put(key, new AnnotationSet(grouped.getOr(key, emptyBucket)))
            orderIndex = orderIndex + 1
        }
    }

    AnnotationSet ofTarget(AnnotationTarget target, String targetName) {
        String key = annotationsTargetKey(target, targetName)
        if self._targets.has(key) {
            return self._targets.getOr(key, AnnotationSet.empty())
        }
        return AnnotationSet.empty()
    }

    AnnotationSet ofType(String typeName) {
        return self.ofTarget(AnnotationTarget.Type, typeName)
    }

    AnnotationSet ofField(String ownerName, String fieldName) {
        if ownerName == null || ownerName == "" {
            throw "AnnotationRegistry.ofField: empty owner name"
        }
        if fieldName == null || fieldName == "" {
            throw "AnnotationRegistry.ofField: empty field name"
        }
        return self.ofTarget(AnnotationTarget.Field, ownerName + "#" + fieldName)
    }

    AnnotationSet ofMethod(String ownerName, String methodName,
                           List<String> parameterTypeNames) {
        if ownerName == null || ownerName == "" {
            throw "AnnotationRegistry.ofMethod: empty owner name"
        }
        if methodName == null || methodName == "" {
            throw "AnnotationRegistry.ofMethod: empty method name"
        }
        String targetName = ownerName + "#" + methodName +
            "(" + annotationsParameterKey(parameterTypeNames) + ")"
        return self.ofTarget(AnnotationTarget.Method, targetName)
    }

    AnnotationSet ofConstructor(String ownerName, List<String> parameterTypeNames) {
        if ownerName == null || ownerName == "" {
            throw "AnnotationRegistry.ofConstructor: empty owner name"
        }
        String targetName = ownerName + "#<init>(" +
            annotationsParameterKey(parameterTypeNames) + ")"
        return self.ofTarget(AnnotationTarget.Constructor, targetName)
    }

    AnnotationSet ofParameter(String memberTargetName, Int parameterIndex) {
        if memberTargetName == null || memberTargetName == "" {
            throw "AnnotationRegistry.ofParameter: empty member target name"
        }
        if parameterIndex < 0 {
            throw "AnnotationRegistry.ofParameter: negative parameter index"
        }
        String targetName = memberTargetName + "#" + str(parameterIndex)
        return self.ofTarget(AnnotationTarget.Parameter, targetName)
    }

    AnnotationSet ofPackage(String packageName) {
        return self.ofTarget(AnnotationTarget.Package, packageName)
    }

    AnnotationSet ofEnumItem(String enumTypeName, String enumItemName) {
        if enumTypeName == null || enumTypeName == "" {
            throw "AnnotationRegistry.ofEnumItem: empty enum type name"
        }
        if enumItemName == null || enumItemName == "" {
            throw "AnnotationRegistry.ofEnumItem: empty enum item name"
        }
        return self.ofTarget(AnnotationTarget.EnumItem, enumTypeName + "#" + enumItemName)
    }

    List<String> types() {
        List<String> result = []
        List<String> keys = self._targets.keys()
        Int index = 0
        while index < keys.length() {
            AnnotationSet set = self._targets.getOr(keys.get(index), AnnotationSet.empty())
            if !set.isEmpty() {
                AnnotationInfo head = set.toList().get(0)
                if head.target() == AnnotationTarget.Type {
                    result.push(head.targetName())
                }
            }
            index = index + 1
        }
        annotationsSortNames(result)
        return result
    }

}

// 处理器眼中的目标元素不可变视图。
class AnnotationElement {
    final AnnotationTarget _target
    final String _ownerName
    final String _name
    final String _typeName
    final AnnotationSet _annotations
    final String _sourceName

    AnnotationElement(AnnotationTarget target, String ownerName, String name,
                      String typeName, AnnotationSet annotations, String sourceName) {
        if ownerName == null {
            throw "AnnotationElement: null owner name"
        }
        if name == null || name == "" {
            throw "AnnotationElement: empty name"
        }
        if typeName == null || typeName == "" {
            throw "AnnotationElement: empty type name"
        }
        if annotations == null {
            throw "AnnotationElement: null annotations"
        }
        if sourceName == null || sourceName == "" {
            throw "AnnotationElement: empty source name"
        }
        if target != AnnotationTarget.Package && ownerName == "" {
            throw "AnnotationElement: empty owner name"
        }
        if !annotations.isEmpty() {
            AnnotationInfo head = annotations.toList().get(0)
            if head.target() != target {
                throw "AnnotationElement: annotation target mismatch"
            }
        }
        self._target = target
        self._ownerName = ownerName
        self._name = name
        self._typeName = typeName
        self._annotations = annotations
        self._sourceName = sourceName
    }

    AnnotationTarget target() {
        return self._target
    }

    String ownerName() {
        return self._ownerName
    }

    String name() {
        return self._name
    }

    String typeName() {
        return self._typeName
    }

    AnnotationSet annotations() {
        return self._annotations
    }

    String sourceName() {
        return self._sourceName
    }

    Bool hasAnnotation(String typeName) {
        return self._annotations.has(typeName)
    }

    AnnotationInfo? firstAnnotation(String typeName) {
        return self._annotations.first(typeName)
    }

    String describe() {
        if self._target == AnnotationTarget.Package {
            return "package " + self._name
        }
        return self._ownerName + "#" + self._name + ":" + self._typeName
    }
}

// 单条不可变诊断。
class AnnotationDiagnostic {
    final AnnotationDiagnosticSeverity _severity
    final String _code
    final String _message
    final String _elementName

    AnnotationDiagnostic(AnnotationDiagnosticSeverity severity, String code,
                         String message, String elementName) {
        if code == null || code.trim() == "" {
            throw "AnnotationDiagnostic: empty code"
        }
        if message == null || message.trim() == "" {
            throw "AnnotationDiagnostic: empty message"
        }
        if elementName == null {
            throw "AnnotationDiagnostic: null element name"
        }
        self._severity = severity
        self._code = code.trim()
        self._message = message.trim()
        self._elementName = elementName.trim()
    }

    AnnotationDiagnosticSeverity severity() {
        return self._severity
    }

    String code() {
        return self._code
    }

    String message() {
        return self._message
    }

    String elementName() {
        return self._elementName
    }

    String describe() {
        String result = annotationsSeverityName(self._severity) +
            " " + self._code + ": " + self._message
        if self._elementName != "" {
            result = result + " [" + self._elementName + "]"
        }
        return result
    }


}

// 单次处理器调用的不可变上下文。
class AnnotationProcessorContext {
    final AnnotationProcessorPhase _phase
    final List<AnnotationElement> _elements
    final Map<String, String> _options

    AnnotationProcessorContext(AnnotationProcessorPhase phase,
                               List<AnnotationElement> elements,
                               Map<String, String> options) {
        if elements == null {
            throw "AnnotationProcessorContext: null elements"
        }
        if options == null {
            throw "AnnotationProcessorContext: null options"
        }
        self._phase = phase
        List<AnnotationElement> copiedElements = []
        self._elements = copiedElements
        Int elementIndex = 0
        while elementIndex < elements.length() {
            AnnotationElement element = elements.get(elementIndex)
            if element == null {
                throw "AnnotationProcessorContext: null element"
            }
            self._elements.push(element)
            elementIndex = elementIndex + 1
        }
        Map<String, String> copiedOptions = [:]
        self._options = copiedOptions
        List<String> names = options.keys()
        Int optionIndex = 0
        while optionIndex < names.length() {
            String name = names.get(optionIndex)
            if name == null || name.trim() == "" {
                throw "AnnotationProcessorContext: empty option name"
            }
            String value = options.getOr(name, "")
            if value == null {
                throw "AnnotationProcessorContext: null option value"
            }
            self._options.put(name, value)
            optionIndex = optionIndex + 1
        }
    }

    AnnotationProcessorPhase phase() {
        return self._phase
    }

    List<AnnotationElement> elements() {
        return self._elements.copy()
    }

    Map<String, String> options() {
        Map<String, String> result = [:]
        List<String> names = self._options.keys()
        Int index = 0
        while index < names.length() {
            String name = names.get(index)
            result.put(name, self._options.getOr(name, ""))
            index = index + 1
        }
        return result
    }

    Bool hasOption(String name) {
        if name == null || name == "" {
            throw "AnnotationProcessorContext.hasOption: empty name"
        }
        return self._options.has(name)
    }

    String optionOr(String name, String fallback) {
        if name == null || name == "" {
            throw "AnnotationProcessorContext.optionOr: empty name"
        }
        if fallback == null {
            throw "AnnotationProcessorContext.optionOr: null fallback"
        }
        if self._options.has(name) {
            return self._options.getOr(name, "")
        }
        return fallback
    }
}

// 单次处理器调用的不可变结果：诊断 + 生成源码。
class AnnotationProcessingResult {
    final List<AnnotationDiagnostic> _diagnostics
    final Map<String, String> _generatedSources

    AnnotationProcessingResult(List<AnnotationDiagnostic> diagnostics,
                               Map<String, String> generatedSources) {
        if diagnostics == null {
            throw "AnnotationProcessingResult: null diagnostics"
        }
        if generatedSources == null {
            throw "AnnotationProcessingResult: null generated sources"
        }
        List<AnnotationDiagnostic> copiedDiagnostics = []
        self._diagnostics = copiedDiagnostics
        Int diagnosticIndex = 0
        while diagnosticIndex < diagnostics.length() {
            AnnotationDiagnostic diagnostic = diagnostics.get(diagnosticIndex)
            if diagnostic == null {
                throw "AnnotationProcessingResult: null diagnostic"
            }
            self._diagnostics.push(diagnostic)
            diagnosticIndex = diagnosticIndex + 1
        }
        Map<String, String> copiedSources = [:]
        self._generatedSources = copiedSources
        List<String> names = generatedSources.keys()
        Int sourceIndex = 0
        while sourceIndex < names.length() {
            String name = names.get(sourceIndex)
            if name == null || name.trim() == "" {
                throw "AnnotationProcessingResult: empty source name"
            }
            String source = generatedSources.getOr(name, "")
            if source == null || source.trim() == "" {
                throw "AnnotationProcessingResult: empty source"
            }
            self._generatedSources.put(name, source)
            sourceIndex = sourceIndex + 1
        }
    }

    static AnnotationProcessingResult empty() {
        List<AnnotationDiagnostic> diagnostics = []
        Map<String, String> generatedSources = [:]
        return new AnnotationProcessingResult(diagnostics, generatedSources)
    }

    List<AnnotationDiagnostic> diagnostics() {
        return self._diagnostics.copy()
    }

    Map<String, String> generatedSources() {
        Map<String, String> result = [:]
        List<String> names = self._generatedSources.keys()
        Int index = 0
        while index < names.length() {
            String name = names.get(index)
            result.put(name, self._generatedSources.getOr(name, ""))
            index = index + 1
        }
        return result
    }

    Bool success() {
        Int index = 0
        while index < self._diagnostics.length() {
            if self._diagnostics.get(index).severity() == AnnotationDiagnosticSeverity.Error {
                return false
            }
            index = index + 1
        }
        return true
    }
}

// 构建期注解处理器合同；非泛型协议。
protocol AnnotationProcessor {
    String name();
    List<AnnotationProcessorPhase> phases();
    AnnotationProcessingResult process(AnnotationProcessorContext context);
}

// ---------- 包内渲染/键辅助（非公开 API） ----------

static Bool annotationsTextLess(String left, String right) {
    Int leftIndex = 0
    Int rightIndex = 0
    while leftIndex < left.length() && rightIndex < right.length() {
        Int leftCode = left.get(leftIndex)
        Int rightCode = right.get(rightIndex)
        if leftCode < rightCode {
            return true
        }
        if leftCode > rightCode {
            return false
        }
        leftIndex = leftIndex + 1
        rightIndex = rightIndex + 1
    }
    return leftIndex == left.length() && rightIndex < right.length()
}

static Void annotationsSortNames(List<String> names) {
    Int outer = 0
    while outer < names.length() {
        Int inner = 0
        while inner + 1 < names.length() {
            String left = names.get(inner)
            String right = names.get(inner + 1)
            if annotationsTextLess(right, left) {
                names.set(inner, right)
                names.set(inner + 1, left)
            }
            inner = inner + 1
        }
        outer = outer + 1
    }
}

static String annotationsValueDescribe(AnnotationValue value) {
    AnnotationValueKind kind = value.kind()
    if kind == AnnotationValueKind.Bool {
        return "Bool(" + str(value.asBool() as Bool) + ")"
    }
    if kind == AnnotationValueKind.Int {
        return "Int(" + str(value.asInt() as Int) + ")"
    }
    if kind == AnnotationValueKind.Long {
        return "Long(" + str(value.asLong() as Long) + ")"
    }
    if kind == AnnotationValueKind.Float {
        return "Float(" + str(value.asFloat() as Double) + ")"
    }
    if kind == AnnotationValueKind.Double {
        return "Double(" + str(value.asDouble() as Double) + ")"
    }
    if kind == AnnotationValueKind.Char {
        return "Char(" + str(value.asChar() as Char) + ")"
    }
    if kind == AnnotationValueKind.String {
        return "String(\"" + (value.asString() as String) + "\")"
    }
    if kind == AnnotationValueKind.Enum {
        return "Enum(" + (value.enumTypeName() as String) + "." +
            (value.enumItemName() as String) + ")"
    }
    if kind == AnnotationValueKind.Type {
        return "Type(" + (value.asTypeName() as String) + ")"
    }
    if kind == AnnotationValueKind.Array {
        List<AnnotationValue> items = value.asArray() as List<AnnotationValue>
        String result = "Array["
        Int index = 0
        while index < items.length() {
            if index > 0 {
                result = result + ","
            }
            result = result + annotationsValueDescribe(items.get(index))
            index = index + 1
        }
        return result + "]"
    }
    if kind == AnnotationValueKind.Annotation {
        AnnotationInfo nested = value.asAnnotation() as AnnotationInfo
        return "Annotation(" + annotationsInfoDescribe(nested) + ")"
    }
    return "Null"
}

static String annotationsInfoDescribe(AnnotationInfo info) {
    Map<String, AnnotationValue> values = info.values()
    List<String> names = values.keys()
    annotationsSortNames(names)
    String result = "@" + info.typeName()
    if names.length() == 0 {
        return result
    }
    result = result + "("
    Int index = 0
    while index < names.length() {
        if index > 0 {
            result = result + ","
        }
        String name = names.get(index)
        AnnotationValue value = values.getOr(name, AnnotationValue.nullValue())
        result = result + name + "=" + annotationsValueDescribe(value)
        index = index + 1
    }
    return result + ")"
}

static String annotationsTargetKey(AnnotationTarget target, String targetName) {
    if targetName == null || targetName == "" {
        throw "AnnotationRegistry.targetKey: empty target name"
    }
    if target == AnnotationTarget.Package {
        return "package:" + targetName
    }
    if target == AnnotationTarget.Type {
        return "type:" + targetName
    }
    if target == AnnotationTarget.Annotation {
        return "annotation:" + targetName
    }
    if target == AnnotationTarget.TypeParameter {
        return "type_parameter:" + targetName
    }
    if target == AnnotationTarget.Field {
        return "field:" + targetName
    }
    if target == AnnotationTarget.Method {
        return "method:" + targetName
    }
    if target == AnnotationTarget.Constructor {
        return "constructor:" + targetName
    }
    if target == AnnotationTarget.Deinit {
        return "deinit:" + targetName
    }
    if target == AnnotationTarget.Parameter {
        return "parameter:" + targetName
    }
    if target == AnnotationTarget.TypeUse {
        return "type_use:" + targetName
    }
    return "enum_item:" + targetName
}

static String annotationsParameterKey(List<String> parameterTypeNames) {
    if parameterTypeNames == null {
        throw "AnnotationRegistry.parameterKey: null parameter types"
    }
    String result = ""
    Int index = 0
    while index < parameterTypeNames.length() {
        String typeName = parameterTypeNames.get(index)
        if typeName == null || typeName == "" {
            throw "AnnotationRegistry.parameterKey: empty parameter type"
        }
        if index > 0 {
            result = result + ","
        }
        result = result + typeName
        index = index + 1
    }
    return result
}

static String annotationsSeverityName(AnnotationDiagnosticSeverity severity) {
    if severity == AnnotationDiagnosticSeverity.Error {
        return "error"
    }
    if severity == AnnotationDiagnosticSeverity.Warning {
        return "warning"
    }
    return "note"
}
