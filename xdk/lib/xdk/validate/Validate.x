// xdk.validate — JSON 规则/字段/Schema 校验（M4.1）。
package xdk.validate
import xdk.codec
import xdk.errors
import xdk.math
import xdk.text

protocol Validator {
    void validate(JsonValue value, ValidationContext context);
    String describe();
}

class ValidationError {
    final String _path
    final String _code
    final String _message

    ValidationError(String path, String code, String message) {
        if path == null { throw "ValidationError: null path" }
        if code == null || code == "" { throw "ValidationError: empty code" }
        if message == null || message == "" { throw "ValidationError: empty message" }
        if path.startsWith(".") { throw "ValidationError: leading dot path" }
        self._path = path
        self._code = code
        self._message = message
    }

    String path() { return self._path }
    String code() { return self._code }
    String message() { return self._message }

    String describe() {
        if self._path == "" { return self._message + " (" + self._code + ")" }
        return self._path + ": " + self._message + " (" + self._code + ")"
    }

    String toString() { return self.describe() }
}

class ValidationContext {
    String _path
    List<ValidationError> _errors
    Bool _failFast
    List<Bool> _stoppedFlag

    ValidationContext() {
        List<Bool> flag = []
        flag.push(false)
        self._path = ""
        self._errors = []
        self._failFast = false
        self._stoppedFlag = flag
    }

    static ValidationContext withFailFast(Bool failFast) {
        ValidationContext context = new ValidationContext()
        context._failFast = failFast
        return context
    }

    String path() { return self._path }
    Bool failFast() { return self._failFast }
    Bool isFailed() { return self._errors.length() > 0 }
    Bool isStopped() { return self._stoppedFlag.get(0) }

    List<ValidationError> errors() {
        List<ValidationError> copy = []
        Int index = 0
        while index < self._errors.length() {
            copy.push(self._errors.get(index))
            index = index + 1
        }
        return copy
    }

    void addError(String code, String message) {
        if code == null || code == "" { throw "ValidationContext.addError: empty code" }
        if message == null || message == "" { throw "ValidationContext.addError: empty message" }
        if self._stoppedFlag.get(0) { return }
        self._errors.push(new ValidationError(self._path, code, message))
        if self._failFast { self._stoppedFlag.set(0, true) }
    }

    ValidationContext child(String name) {
        if name == null { throw "ValidationContext.child: null name" }
        String childPath = name
        if self._path != "" {
            if name.startsWith("[") {
                childPath = self._path + name
            } else {
                childPath = self._path + "." + name
            }
        }
        ValidationContext child = new ValidationContext()
        child._path = childPath
        child._errors = self._errors
        child._failFast = self._failFast
        child._stoppedFlag = self._stoppedFlag
        return child
    }

    ValidationContext fork() {
        ValidationContext child = new ValidationContext()
        child._path = self._path
        child._errors = []
        child._failFast = self._failFast
        List<Bool> flag = []
        flag.push(false)
        child._stoppedFlag = flag
        return child
    }
}

class ValidationResult {
    List<ValidationError> _errors

    ValidationResult() {
        self._errors = []
    }

    static ValidationResult fromErrors(List<ValidationError> errors) {
        if errors == null { throw "ValidationResult: null errors" }
        ValidationResult result = new ValidationResult()
        Int index = 0
        while index < errors.length() {
            result._errors.push(errors.get(index))
            index = index + 1
        }
        return result
    }

    static ValidationResult fromContext(ValidationContext context) {
        if context == null { throw "ValidationResult.fromContext: null" }
        return ValidationResult.fromErrors(context.errors())
    }

    Bool isValid() { return self._errors.length() == 0 }

    List<ValidationError> errors() {
        List<ValidationError> copy = []
        Int index = 0
        while index < self._errors.length() {
            copy.push(self._errors.get(index))
            index = index + 1
        }
        return copy
    }

    ValidationError? firstError() {
        if self._errors.length() == 0 { return null }
        return self._errors.get(0)
    }

    Int errorCount() { return self._errors.length() }

    ValidationResult add(ValidationError error) {
        if error == null { throw "ValidationResult.add: null" }
        self._errors.push(error)
        return self
    }

    ValidationResult addAll(List<ValidationError> errors) {
        if errors == null { throw "ValidationResult.addAll: null" }
        Int index = 0
        while index < errors.length() {
            self.add(errors.get(index))
            index = index + 1
        }
        return self
    }

    ValidationResult merge(ValidationResult other) {
        if other == null { throw "ValidationResult.merge: null" }
        return self.addAll(other._errors)
    }

    Map<String, List<ValidationError>> errorsByField() {
        Map<String, List<ValidationError>> result = [:]
        Int index = 0
        while index < self._errors.length() {
            ValidationError error = self._errors.get(index)
            List<ValidationError> bucket = []
            if result.has(error.path()) {
                bucket = result.getOr(error.path(), bucket)
            }
            bucket.push(error)
            result.put(error.path(), bucket)
            index = index + 1
        }
        return result
    }

    Result<Unit, Error> toResult() {
        if self._errors.length() == 0 { return Ok() }
        BasicError error = new BasicError(ErrorKind.InvalidArgument, "validation failed: " + self._errors.get(0).describe())
        return Err(error)
    }

    String toString() {
        if self._errors.length() == 0 { return "valid" }
        return "invalid(" + str(self._errors.length()) + "): " + self._errors.get(0).describe()
    }
}

class Rule implements Validator {
    final String _code
    final String _message
    final String _description
    final void(JsonValue, ValidationContext) _check

    Rule(String code, String message, String description, void(JsonValue, ValidationContext) check) {
        if code == null || code == "" { throw "Rule: empty code" }
        if message == null || message == "" { throw "Rule: empty message" }
        if description == null || description == "" { throw "Rule: empty description" }
        self._code = code
        self._message = message
        self._description = description
        self._check = check
    }

    void validate(JsonValue value, ValidationContext context) {
        if context == null { throw "Rule.validate: null context" }
        if context.isStopped() { return }
        self._check(value, context)
    }

    String describe() { return self._description }
    String code() { return self._code }
    String message() { return self._message }
}

class Rules {
    Rules() { }

    static Validator required() {
        return new Rule("required", "value is required", "required",
            (JsonValue value, ValidationContext context) -> {
                if value == null || value.isNull() {
                    context.addError("required", "value is required")
                }
            })
    }

    static Validator string() {
        return new Rule("type", "expected string", "string",
            (JsonValue value, ValidationContext context) -> {
                if value != null && !value.isNull() && !value.isString() {
                    context.addError("type", "expected string")
                }
            })
    }

    static Validator number() {
        return new Rule("type", "expected number", "number",
            (JsonValue value, ValidationContext context) -> {
                if value != null && !value.isNull() && !value.isNumber() {
                    context.addError("type", "expected number")
                }
            })
    }

    static Validator integer() {
        return new Rule("type", "expected integer", "integer",
            (JsonValue value, ValidationContext context) -> {
                if value == null || value.isNull() { return }
                if !value.isNumber() {
                    context.addError("type", "expected integer")
                    return
                }
                JsonNumber number = value.asNumber() as JsonNumber
                if !number.isInteger() {
                    context.addError("type", "expected integer")
                }
            })
    }

    static Validator bool() {
        return new Rule("type", "expected boolean", "bool",
            (JsonValue value, ValidationContext context) -> {
                if value != null && !value.isNull() && !value.isBool() {
                    context.addError("type", "expected boolean")
                }
            })
    }

    static Validator array() {
        return new Rule("type", "expected array", "array",
            (JsonValue value, ValidationContext context) -> {
                if value != null && !value.isNull() && !value.isArray() {
                    context.addError("type", "expected array")
                }
            })
    }

    static Validator object() {
        return new Rule("type", "expected object", "object",
            (JsonValue value, ValidationContext context) -> {
                if value != null && !value.isNull() && !value.isObject() {
                    context.addError("type", "expected object")
                }
            })
    }

    static Validator minLength(Int length) {
        if length < 0 { throw "Rules.minLength: negative length" }
        return new Rule("min_length", "value is too short", "minLength(" + str(length) + ")",
            (JsonValue value, ValidationContext context) -> {
                if value == null || value.isNull() { return }
                if value.isString() {
                    String text = value.asString() as String
                    if text.length() < length {
                        context.addError("min_length", "value is too short")
                    }
                } else if value.isArray() {
                    JsonArray array = value.asArray() as JsonArray
                    if array.length() < length {
                        context.addError("min_length", "array is too short")
                    }
                } else {
                    context.addError("type", "expected string or array")
                }
            })
    }

    static Validator maxLength(Int length) {
        if length < 0 { throw "Rules.maxLength: negative length" }
        return new Rule("max_length", "value is too long", "maxLength(" + str(length) + ")",
            (JsonValue value, ValidationContext context) -> {
                if value == null || value.isNull() { return }
                if value.isString() {
                    String text = value.asString() as String
                    if text.length() > length {
                        context.addError("max_length", "value is too long")
                    }
                } else if value.isArray() {
                    JsonArray array = value.asArray() as JsonArray
                    if array.length() > length {
                        context.addError("max_length", "array is too long")
                    }
                } else {
                    context.addError("type", "expected string or array")
                }
            })
    }

    static Validator pattern(Regex regex) {
        if regex == null { throw "Rules.pattern: null regex" }
        return new Rule("pattern", "value does not match pattern", "pattern",
            (JsonValue value, ValidationContext context) -> {
                if value == null || value.isNull() { return }
                if !value.isString() {
                    context.addError("type", "expected string")
                    return
                }
                String text = value.asString() as String
                if !regex.isMatch(text) {
                    context.addError("pattern", "value does not match pattern")
                }
            })
    }

    static Validator range(Double min, Double max) {
        if isNaN(min) || isNaN(max) { throw "Rules.range: NaN bound" }
        if min > max { throw "Rules.range: min > max" }
        return new Rule("range", "value out of range", "range(" + str(min) + "," + str(max) + ")",
            (JsonValue value, ValidationContext context) -> {
                if value == null || value.isNull() { return }
                if !value.isNumber() {
                    context.addError("type", "expected number")
                    return
                }
                JsonNumber number = value.asNumber() as JsonNumber
                Result<Double, Error> parsed = number.asDouble()
                if parsed.isErr() {
                    context.addError("number", "invalid number")
                    return
                }
                Double actual = parsed.value()
                if actual < min || actual > max {
                    context.addError("range", "value out of range")
                }
            })
    }

    static Validator oneOf(List<String> allowed) {
        if allowed == null || allowed.length() == 0 {
            throw "Rules.oneOf: empty allowed list"
        }
        return new Rule("one_of", "value is not allowed", "oneOf",
            (JsonValue value, ValidationContext context) -> {
                if value == null || value.isNull() { return }
                if !value.isString() {
                    context.addError("type", "expected string")
                    return
                }
                String text = value.asString() as String
                Int index = 0
                while index < allowed.length() {
                    if text == allowed.get(index) { return }
                    index = index + 1
                }
                context.addError("one_of", "value is not allowed")
            })
    }

    static Validator email() {
        Result<Regex, Error> compiled = Regex.compile("^[^@ ]+@[^@ ]+[.][^@ ]+$")
        if compiled.isErr() { throw "Rules.email: invalid pattern" }
        return Rules.pattern(compiled.value())
    }

    static Validator url() {
        Result<Regex, Error> compiled = Regex.compile("^https?://[^ ]+$")
        if compiled.isErr() { throw "Rules.url: invalid pattern" }
        return Rules.pattern(compiled.value())
    }

    static Validator uuid() {
        Result<Regex, Error> compiled = Regex.compile("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
        if compiled.isErr() { throw "Rules.uuid: invalid pattern" }
        return Rules.pattern(compiled.value())
    }

    static Validator arrayOf(Validator element) {
        if element == null { throw "Rules.arrayOf: null element" }
        return new Rule("array", "invalid array element", "arrayOf",
            (JsonValue value, ValidationContext context) -> {
                if value == null || value.isNull() { return }
                if !value.isArray() {
                    context.addError("type", "expected array")
                    return
                }
                JsonArray array = value.asArray() as JsonArray
                Int index = 0
                while index < array.length() {
                    if context.isStopped() { return }
                    element.validate(array.get(index), context.child("[" + str(index) + "]"))
                    index = index + 1
                }
            })
    }

    static Validator all(List<Validator> validators) {
        if validators == null || validators.length() == 0 {
            throw "Rules.all: empty validators"
        }
        return new Rule("all", "one or more rules failed", "all",
            (JsonValue value, ValidationContext context) -> {
                Int index = 0
                while index < validators.length() {
                    if context.isStopped() { return }
                    validators.get(index).validate(value, context)
                    index = index + 1
                }
            })
    }

    static Validator any(List<Validator> validators) {
        if validators == null || validators.length() == 0 {
            throw "Rules.any: empty validators"
        }
        return new Rule("any", "no alternative matched", "any",
            (JsonValue value, ValidationContext context) -> {
                Int index = 0
                while index < validators.length() {
                    ValidationContext probe = context.fork()
                    validators.get(index).validate(value, probe)
                    if !probe.isFailed() { return }
                    index = index + 1
                }
                context.addError("any", "no alternative matched")
            })
    }

    static Validator not(Validator validator) {
        if validator == null { throw "Rules.not: null validator" }
        return new Rule("not", "value matches forbidden rule", "not",
            (JsonValue value, ValidationContext context) -> {
                ValidationContext probe = context.fork()
                validator.validate(value, probe)
                if !probe.isFailed() {
                    context.addError("not", "value matches forbidden rule")
                }
            })
    }

    static Validator custom(String code, String message, Bool(JsonValue) predicate) {
        if code == null || code == "" { throw "Rules.custom: empty code" }
        if message == null || message == "" { throw "Rules.custom: empty message" }
        return new Rule(code, message, "custom",
            (JsonValue value, ValidationContext context) -> {
                if !predicate(value) {
                    context.addError(code, message)
                }
            })
    }
}

class FieldRule {
    final String _name
    final Validator _validator
    final Bool _required

    FieldRule(String name, Validator validator, Bool required) {
        if name == null || name == "" { throw "FieldRule: empty name" }
        if validator == null { throw "FieldRule: null validator" }
        self._name = name
        self._validator = validator
        self._required = required
    }

    String name() { return self._name }
    Validator validator() { return self._validator }
    Bool isRequired() { return self._required }

    FieldRule withRequired(Bool required) {
        return new FieldRule(self._name, self._validator, required)
    }

    String describe() {
        if self._required { return self._name + " (required)" }
        return self._name
    }
}

class Schema implements Validator {
    Map<String, FieldRule> _fields
    List<String> _order
    List<FieldRule> _rules
    Bool _failFast

    Schema() {
        Map<String, FieldRule> fields = [:]
        self._fields = fields
        self._order = []
        self._rules = []
        self._failFast = false
    }

    static Schema withFailFast(Bool failFast) {
        Schema schema = new Schema()
        schema._failFast = failFast
        return schema
    }

    Schema field(String name, Validator validator) {
        if name == null || name == "" { throw "Schema.field: empty name" }
        if validator == null { throw "Schema.field: null validator" }
        if self._fields.has(name) { throw "Schema.field: duplicate name" }
        FieldRule rule = new FieldRule(name, validator, false)
        self._fields.put(name, rule)
        self._rules.push(rule)
        self._order.push(name)
        return self
    }

    Schema required(String name) {
        if name == null || name == "" { throw "Schema.required: empty name" }
        if !self._fields.has(name) { throw "Schema.required: unknown field" }
        Int index = 0
        while index < self._order.length() {
            if self._order.get(index) == name {
                FieldRule existing = self._rules.get(index)
                self._rules.set(index, existing.withRequired(true))
                self._fields.put(name, self._rules.get(index))
                break
            }
            index = index + 1
        }
        return self
    }

    void validate(JsonValue value, ValidationContext context) {
        if context == null { throw "Schema.validate: null context" }
        if value == null || !value.isObject() {
            context.addError("object", "expected object")
            return
        }
        JsonObject object = value.asObject() as JsonObject
        Int index = 0
        while index < self._order.length() {
            if context.isStopped() { return }
            String name = self._order.get(index)
            FieldRule rule = self._rules.get(index)
            JsonValue? fieldValue = object.getOrNull(name)
            if fieldValue == null {
                if rule.isRequired() {
                    context.child(name).addError("required", "field is required")
                }
            } else {
                JsonValue actual = fieldValue as JsonValue
                if actual.isNull() {
                    if rule.isRequired() {
                        context.child(name).addError("required", "field is required")
                    }
                } else {
                    rule.validator().validate(actual, context.child(name))
                }
            }
            index = index + 1
        }
    }

    ValidationResult validateValue(JsonValue value) {
        ValidationContext context = ValidationContext.withFailFast(self._failFast)
        self.validate(value, context)
        return ValidationResult.fromContext(context)
    }

    ValidationResult validateField(String name, JsonValue value) {
        if name == null || name == "" { throw "Schema.validateField: empty name" }
        if !self._fields.has(name) { throw "Schema.validateField: unknown field" }
        ValidationContext context = ValidationContext.withFailFast(self._failFast)
        Int fieldIndex = -1
        Int scan = 0
        while scan < self._order.length() {
            if self._order.get(scan) == name {
                fieldIndex = scan
                break
            }
            scan = scan + 1
        }
        FieldRule rule = self._rules.get(fieldIndex)
        if value == null || value.isNull() {
            if rule.isRequired() {
                context.child(name).addError("required", "field is required")
            }
        } else {
            rule.validator().validate(value, context.child(name))
        }
        return ValidationResult.fromContext(context)
    }

    List<FieldRule> fields() {
        List<FieldRule> result = []
        Int index = 0
        while index < self._rules.length() {
            result.push(self._rules.get(index))
            index = index + 1
        }
        return result
    }

    Bool isFailFast() { return self._failFast }

    String describe() {
        return "schema(" + str(self._fields.length()) + " fields)"
    }
}
