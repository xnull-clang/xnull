package xdk2.validate
import xdk.codec
import xdk.errors
import xdk.text
import xdk.validate

static JsonValue j(String text) {
    return Json.parse(text).value()
}

static Bool passes(Validator rule, JsonValue value) {
    ValidationContext context = new ValidationContext()
    rule.validate(value, context)
    return !context.isFailed()
}

static String firstCode(Validator rule, JsonValue value) {
    ValidationContext context = new ValidationContext()
    rule.validate(value, context)
    if context.isFailed() { return context.errors().get(0).code() }
    return "ok"
}

static String firstPath(Validator rule, JsonValue value) {
    ValidationContext context = new ValidationContext()
    rule.validate(value, context)
    if context.isFailed() { return context.errors().get(0).path() }
    return "ok"
}

static Validator evenRule() {
    Bool(JsonValue) predicate = (JsonValue value) -> {
        if value == null || !value.isNumber() { return false }
        JsonNumber number = value.asNumber() as JsonNumber
        Result<Int, Error> parsed = number.asInt()
        if parsed.isErr() { return false }
        return parsed.value() % 2 == 0
    }
    return Rules.custom("even", "must be even", predicate)
}

static Int main() {
    // ---- type rules ----
    print("required-missing=" + str(passes(Rules.required(), null)))
    print("required-null=" + str(passes(Rules.required(), j("null"))))
    print("required-ok=" + str(passes(Rules.required(), j("\"x\""))))
    print("string-ok=" + str(passes(Rules.string(), j("\"x\""))))
    print("string-bad=" + firstCode(Rules.string(), j("1")))
    print("number-ok=" + str(passes(Rules.number(), j("1.5"))))
    print("number-bad=" + firstCode(Rules.number(), j("\"x\"")))
    print("integer-ok=" + str(passes(Rules.integer(), j("2"))))
    print("integer-float=" + firstCode(Rules.integer(), j("2.5")))
    print("integer-text=" + firstCode(Rules.integer(), j("\"2\"")))
    print("bool-ok=" + str(passes(Rules.bool(), j("true"))))
    print("bool-bad=" + firstCode(Rules.bool(), j("1")))
    print("array-ok=" + str(passes(Rules.array(), j("[]"))))
    print("array-bad=" + firstCode(Rules.array(), j("{}")))
    print("object-ok=" + str(passes(Rules.object(), j("{}"))))
    print("object-bad=" + firstCode(Rules.object(), j("[]")))

    // ---- length / range / enum / format ----
    print("minlength-ok=" + str(passes(Rules.minLength(3), j("\"abc\""))))
    print("minlength-bad=" + firstCode(Rules.minLength(3), j("\"ab\"")))
    print("minlength-array=" + firstCode(Rules.minLength(2), j("[1]")))
    print("minlength-type=" + firstCode(Rules.minLength(1), j("1")))
    print("maxlength-ok=" + str(passes(Rules.maxLength(2), j("\"ab\""))))
    print("maxlength-bad=" + firstCode(Rules.maxLength(2), j("\"abc\"")))
    print("range-ok=" + str(passes(Rules.range(1.0, 3.0), j("2"))))
    print("range-low=" + firstCode(Rules.range(1.0, 3.0), j("0")))
    print("range-high=" + firstCode(Rules.range(1.0, 3.0), j("4")))
    print("range-type=" + firstCode(Rules.range(1.0, 3.0), j("\"2\"")))
    List<String> allowed = ["a", "b"]
    print("oneof-ok=" + str(passes(Rules.oneOf(allowed), j("\"a\""))))
    print("oneof-bad=" + firstCode(Rules.oneOf(allowed), j("\"c\"")))
    Result<Regex, Error> re = Regex.compile("^a+$")
    print("pattern-ok=" + str(passes(Rules.pattern(re.value()), j("\"aaa\""))))
    print("pattern-bad=" + firstCode(Rules.pattern(re.value()), j("\"b\"")))
    print("email-ok=" + str(passes(Rules.email(), j("\"a@b.c\""))))
    print("email-bad=" + firstCode(Rules.email(), j("\"bad\"")))
    print("url-ok=" + str(passes(Rules.url(), j("\"https://x\""))))
    print("url-bad=" + firstCode(Rules.url(), j("\"ftp://x\"")))
    print("uuid-ok=" + str(passes(Rules.uuid(), j("\"12345678-1234-1234-1234-123456789abc\""))))
    print("uuid-bad=" + firstCode(Rules.uuid(), j("\"1234\"")))

    // ---- composition ----
    Validator stringRule = Rules.string()
    Validator minRule = Rules.minLength(3)
    List<Validator> allRules = []
    allRules.push(stringRule)
    allRules.push(minRule)
    Validator both = Rules.all(allRules)
    print("all-ok=" + str(passes(both, j("\"abc\""))))
    print("all-bad=" + firstCode(both, j("\"ab\"")))

    List<Validator> alternatives = []
    alternatives.push(Rules.integer())
    alternatives.push(Rules.string())
    Validator anyRule = Rules.any(alternatives)
    print("any-int=" + str(passes(anyRule, j("1"))))
    print("any-string=" + str(passes(anyRule, j("\"x\""))))
    print("any-bad=" + firstCode(anyRule, j("1.5")))

    Validator notString = Rules.not(Rules.string())
    print("not-int=" + str(passes(notString, j("1"))))
    print("not-string=" + firstCode(notString, j("\"x\"")))

    Validator even = evenRule()
    print("custom-ok=" + str(passes(even, j("4"))))
    print("custom-bad=" + firstCode(even, j("3")))

    Validator itemString = Rules.string()
    Validator items = Rules.arrayOf(itemString)
    print("arrayof-ok=" + str(passes(items, j("[\"a\",\"b\"]"))))
    print("arrayof-bad=" + firstCode(items, j("[\"a\",1]")))
    print("arrayof-path=" + firstPath(items, j("[\"a\",1]")))

    // ---- context ----
    ValidationContext root = new ValidationContext()
    root.addError("x", "m")
    print("ctx-failed=" + str(root.isFailed()))
    print("ctx-path=" + str(root.path() == ""))
    print("ctx-describe=" + root.errors().get(0).describe())
    ValidationContext userContext = root.child("user")
    ValidationContext nameContext = userContext.child("name")
    print("ctx-nested=" + nameContext.path())
    ValidationContext itemsContext = userContext.child("items")
    print("ctx-index=" + itemsContext.child("[2]").path())
    ValidationContext shared = root.child("shared")
    shared.addError("y", "n")
    print("ctx-shared=" + str(root.errors().length()))
    ValidationContext probe = shared.fork()
    probe.addError("z", "o")
    print("ctx-fork=" + str(probe.isFailed()) + "," + str(root.errors().length()))
    List<ValidationError> snapshot = root.errors()
    snapshot.push(new ValidationError("q", "q", "q"))
    print("ctx-snapshot=" + str(root.errors().length()))
    ValidationContext fast = ValidationContext.withFailFast(true)
    fast.addError("a", "one")
    fast.addError("b", "two")
    print("ctx-fast=" + str(fast.isStopped()) + "," + str(fast.errors().length()))

    // ---- result ----
    ValidationResult empty = new ValidationResult()
    print("result-valid=" + str(empty.isValid()) + "," + str(empty.toString()))
    print("result-toresult=" + str(empty.toResult().isOk()))
    ValidationResult built = new ValidationResult()
    built.add(new ValidationError("name", "required", "missing"))
    built.add(new ValidationError("name", "type", "wrong"))
    built.add(new ValidationError("age", "range", "bad"))
    print("result-count=" + str(built.errorCount()))
    ValidationError? first = built.firstError()
    ValidationError firstValue = first as ValidationError
    print("result-first=" + firstValue.describe())
    print("result-string=" + built.toString())
    Map<String, List<ValidationError>> byField = built.errorsByField()
    List<ValidationError> emptyBucket = []
    List<ValidationError> nameBucket = byField.getOr("name", emptyBucket)
    List<ValidationError> ageBucket = byField.getOr("age", emptyBucket)
    print("result-group=" + str(nameBucket.length()) + "," + str(ageBucket.length()))
    ValidationResult other = new ValidationResult()
    other.add(new ValidationError("x", "c", "m"))
    built.merge(other)
    print("result-merge=" + str(built.errorCount()))
    print("result-fail=" + str(built.toResult().isErr()))
    ValidationContext resultContext = new ValidationContext()
    resultContext.addError("k", "v")
    ValidationResult fromCtx = ValidationResult.fromContext(resultContext)
    print("result-fromctx=" + str(fromCtx.errorCount()))

    // ---- schema ----
    Schema schema = new Schema()
    Validator nameType = Rules.string()
    Validator ageType = Rules.integer()
    schema.field("name", nameType)
    schema.field("age", ageType)
    schema.required("name")
    print("schema-fields=" + str(schema.fields().length()) + "," + schema.describe())
    print("schema-failfast=" + str(schema.isFailFast()))
    ValidationResult missing = schema.validateValue(j("{\"age\":3}"))
    print("schema-required=" + str(missing.errorCount()) + "," + missing.errors().get(0).code() + "," + missing.errors().get(0).path())
    ValidationResult nullRequired = schema.validateValue(j("{\"name\":null,\"age\":3}"))
    print("schema-null=" + str(nullRequired.errorCount()) + "," + nullRequired.errors().get(0).code())
    ValidationResult valid = schema.validateValue(j("{\"name\":\"Ada\",\"age\":3}"))
    print("schema-valid=" + str(valid.isValid()))
    ValidationResult invalidAge = schema.validateValue(j("{\"name\":\"Ada\",\"age\":\"x\"}"))
    print("schema-type=" + str(invalidAge.errorCount()) + "," + invalidAge.errors().get(0).path() + "," + invalidAge.errors().get(0).code())
    ValidationResult unknown = schema.validateValue(j("{\"name\":\"Ada\",\"extra\":1}"))
    print("schema-unknown=" + str(unknown.isValid()))
    ValidationResult nonObject = schema.validateValue(j("[]"))
    print("schema-object=" + str(nonObject.errorCount()) + "," + nonObject.errors().get(0).path() + "," + nonObject.errors().get(0).code())
    ValidationResult fieldResult = schema.validateField("name", j("1"))
    print("schema-field=" + str(fieldResult.errorCount()) + "," + fieldResult.errors().get(0).path())
    Schema fastSchema = Schema.withFailFast(true)
    fastSchema.field("a", Rules.string())
    fastSchema.field("b", Rules.string())
    ValidationResult fastResult = fastSchema.validateValue(j("{\"a\":1,\"b\":2}"))
    print("schema-fast=" + str(fastResult.errorCount()) + "," + fastResult.errors().get(0).path())

    // nested schema
    Schema inner = new Schema()
    inner.field("email", Rules.email())
    Schema outer = new Schema()
    outer.field("user", inner)
    ValidationResult nestedBad = outer.validateValue(j("{\"user\":{\"email\":\"bad\"}}"))
    print("schema-nested=" + str(nestedBad.errorCount()) + "," + nestedBad.errors().get(0).path() + "," + nestedBad.errors().get(0).code())

    // field rule
    FieldRule fieldRule = new FieldRule("email", Rules.email(), false)
    print("fieldrule=" + fieldRule.describe())
    FieldRule requiredRule = fieldRule.withRequired(true)
    print("fieldrule-required=" + requiredRule.describe() + "," + str(fieldRule.isRequired()) + "," + str(requiredRule.isRequired()))
    return 0
}
