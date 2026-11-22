// xdk.codec — JSON/CSV/Base64/Hex（M3.1）。
package xdk.codec
import xdk.errors
import xdk.bytes
import xdk.text
import xdk.io

Error codecError(ErrorKind kind, String message) { return new BasicError(kind, message) }

String charText(Char value) {
    String out = $"{value}"
    return out
}

enum JsonKind {
    Null,
    Bool,
    Number,
    String,
    Array,
    Object,
}

String jsonKindName(JsonKind kind) {
    if kind == JsonKind.Null { return "Null" }
    if kind == JsonKind.Bool { return "Bool" }
    if kind == JsonKind.Number { return "Number" }
    if kind == JsonKind.String { return "String" }
    if kind == JsonKind.Array { return "Array" }
    if kind == JsonKind.Object { return "Object" }
    return "Unknown"
}

class JsonNumber {
    final String _raw
    JsonNumber(String raw) {
        if !JsonNumber.isValidText(raw) { throw "JsonNumber: invalid number" }
        self._raw = raw
    }
    static Bool isDigit(String c) { return c.length() == 1 && JsonNumber.digitIndex(c) >= 0 }
    static Int digitIndex(String c) {
        Int d = "0123456789".indexOf(c)
        return d
    }
    static Bool isValidText(String raw) {
        if raw == "" { return false }
        Int i = 0
        if raw.substring(0, 1) == "-" { i = 1 }
        if i >= raw.length() { return false }
        if raw.substring(i, 1) == "0" { i = i + 1 } else {
            if !isDigit(raw.substring(i, 1)) { return false }
            while i < raw.length() && isDigit(raw.substring(i, 1)) { i = i + 1 }
        }
        if i < raw.length() && raw.substring(i, 1) == "." {
            i = i + 1
            if i >= raw.length() || !isDigit(raw.substring(i, 1)) { return false }
            while i < raw.length() && isDigit(raw.substring(i, 1)) { i = i + 1 }
        }
        if i < raw.length() && (raw.substring(i, 1) == "e" || raw.substring(i, 1) == "E") {
            i = i + 1
            if i < raw.length() && (raw.substring(i, 1) == "+" || raw.substring(i, 1) == "-") { i = i + 1 }
            if i >= raw.length() || !isDigit(raw.substring(i, 1)) { return false }
            while i < raw.length() && isDigit(raw.substring(i, 1)) { i = i + 1 }
        }
        return i == raw.length()
    }
    String raw() { return self._raw }
    Bool isInteger() { return self._raw.indexOf(".") < 0 && self._raw.indexOf("e") < 0 && self._raw.indexOf("E") < 0 }
    Result<Long, Error> asLong() {
        if !self.isInteger() { return Err(codecError(ErrorKind.DataCorrupted, "JsonNumber: not integer")) }
        Int i = 0
        Bool neg = false
        if self._raw.substring(0, 1) == "-" { neg = true; i = 1 }
        Long value = 0
        Long cutoff = 922337203685477580
        while i < self._raw.length() {
            Int d = JsonNumber.digitIndex(self._raw.substring(i, 1))
            if d < 0 { return Err(codecError(ErrorKind.DataCorrupted, "JsonNumber: invalid digit")) }
            if value > cutoff { return Err(codecError(ErrorKind.DataCorrupted, "JsonNumber: long overflow")) }
            if value == cutoff {
                if !neg && d > 7 { return Err(codecError(ErrorKind.DataCorrupted, "JsonNumber: long overflow")) }
                if neg && d > 8 { return Err(codecError(ErrorKind.DataCorrupted, "JsonNumber: long overflow")) }
            }
            value = value * 10 + d
            i = i + 1
        }
        if neg { value = -value }
        return Ok(value)
    }
    Result<Int, Error> asInt() {
        Result<Long, Error> value = self.asLong()
        if value.isErr() { return Err(value.error()) }
        Long raw = value.value()
        if raw > 2147483647 || raw < -2147483648 { return Err(codecError(ErrorKind.DataCorrupted, "JsonNumber: int overflow")) }
        return Ok(raw as Int)
    }
    Result<Double, Error> asDouble() {
        Int i = 0
        Bool neg = false
        if self._raw.substring(0, 1) == "-" { neg = true; i = 1 }
        Double value = 0.0
        while i < self._raw.length() && self._raw.substring(i, 1) != "." &&
              self._raw.substring(i, 1) != "e" && self._raw.substring(i, 1) != "E" {
            Int d = JsonNumber.digitIndex(self._raw.substring(i, 1))
            if d < 0 { return Err(codecError(ErrorKind.DataCorrupted, "JsonNumber: invalid digit")) }
            value = value * 10.0 + d
            i = i + 1
        }
        if i < self._raw.length() && self._raw.substring(i, 1) == "." {
            i = i + 1
            Double scale = 0.1
            while i < self._raw.length() && JsonNumber.isDigit(self._raw.substring(i, 1)) {
                value = value + JsonNumber.digitIndex(self._raw.substring(i, 1)) * scale
                scale = scale * 0.1
                i = i + 1
            }
        }
        Int exp = 0
        Bool expNeg = false
        if i < self._raw.length() && (self._raw.substring(i, 1) == "e" || self._raw.substring(i, 1) == "E") {
            i = i + 1
            if self._raw.substring(i, 1) == "+" { i = i + 1 } else if self._raw.substring(i, 1) == "-" { expNeg = true; i = i + 1 }
            while i < self._raw.length() {
                exp = exp * 10 + JsonNumber.digitIndex(self._raw.substring(i, 1))
                i = i + 1
            }
        }
        while exp > 0 {
            if expNeg { value = value / 10.0 } else { value = value * 10.0 }
            exp = exp - 1
        }
        if neg { value = -value }
        return Ok(value)
    }
    String toString() { return self._raw }
}

class JsonArray {
    final List<JsonValue> _values
    JsonArray() { self._values = [] }
    JsonValue get(Int index) { return self._values.get(index) }
    Void add(JsonValue value) {
        if value == null { throw "JsonArray.add: null" }
        self._values.push(value)
    }
    JsonValue remove(Int index) {
        JsonValue value = self._values.get(index)
        self._values.remove(index)
        return value
    }
    Int length() { return self._values.length() }
    List<JsonValue> toList() { return self._values.copy() }
    JsonArray copy() {
        JsonArray result = new JsonArray()
        Int i = 0
        while i < self._values.length() { result.add(self._values.get(i)); i = i + 1 }
        return result
    }
}

class JsonObject {
    final List<String> _order
    final List<JsonValue> _values
    JsonObject() { self._order = []; self._values = [] }
    Int indexOf(String name) {
        Int i = 0
        while i < self._order.length() {
            if self._order.get(i) == name { return i }
            i = i + 1
        }
        return -1
    }
    JsonValue? getOrNull(String name) {
        Int i = self.indexOf(name)
        if i < 0 { return null }
        return self._values.get(i)
    }
    JsonValue getOr(String name, JsonValue fallback) {
        Int i = self.indexOf(name)
        if i < 0 { return fallback }
        return self._values.get(i)
    }
    Bool has(String name) { return self.indexOf(name) >= 0 }
    Void set(String name, JsonValue value) {
        if value == null { throw "JsonObject.set: null" }
        Int i = self.indexOf(name)
        if i < 0 { self._order.push(name); self._values.push(value); return }
        self._values.set(i, value)
    }
    Bool remove(String name) {
        Int i = self.indexOf(name)
        if i < 0 { return false }
        self._order.remove(i); self._values.remove(i)
        return true
    }
    List<String> keys() { return self._order.copy() }
    List<JsonValue> values() { return self._values.copy() }
    Int length() { return self._order.length() }
    Void clear() {
        self._order.clear()
        self._values.clear()
    }
    JsonObject copy() {
        JsonObject out = new JsonObject()
        Int i = 0
        while i < self._order.length() { out.set(self._order.get(i), self._values.get(i)); i = i + 1 }
        return out
    }
}

class JsonValue {
    final JsonKind _kind
    final Bool _bool
    final JsonNumber? _number
    final String? _string
    final JsonArray? _array
    final JsonObject? _object
    JsonValue(JsonKind kind, Bool boolValue, JsonNumber? numberValue, String? stringValue, JsonArray? arrayValue, JsonObject? objectValue) {
        self._kind = kind; self._bool = boolValue; self._number = numberValue
        self._string = stringValue; self._array = arrayValue; self._object = objectValue
    }
    JsonKind kind() { return self._kind }
    Bool isNull() { return self._kind == JsonKind.Null }
    Bool isBool() { return self._kind == JsonKind.Bool }
    Bool isNumber() { return self._kind == JsonKind.Number }
    Bool isString() { return self._kind == JsonKind.String }
    Bool isArray() { return self._kind == JsonKind.Array }
    Bool isObject() { return self._kind == JsonKind.Object }
    Bool? asBool() { return self._bool }
    JsonNumber? asNumber() { return self._number }
    String? asString() { return self._string }
    JsonArray? asArray() { return self._array }
    JsonObject? asObject() { return self._object }
}

class JsonOptions {
    Int _maxDepth
    Long _maxBytes
    Bool _allowComments
    Bool _allowTrailingComma
    Bool _pretty
    JsonOptions() {
        self._maxDepth = 128
        self._maxBytes = 16777216
        self._allowComments = false
        self._allowTrailingComma = false
        self._pretty = false
    }
    JsonOptions maxDepth(Int value) {
        if value <= 0 { throw "JsonOptions.maxDepth" }
        self._maxDepth = value
        return self
    }
    JsonOptions maxBytes(Long value) {
        if value <= 0 { throw "JsonOptions.maxBytes" }
        self._maxBytes = value
        return self
    }
    JsonOptions allowComments(Bool value) { self._allowComments = value; return self }
    JsonOptions allowTrailingComma(Bool value) { self._allowTrailingComma = value; return self }
    JsonOptions pretty(Bool value) { self._pretty = value; return self }
    Int getMaxDepth() { return self._maxDepth }
    Long getMaxBytes() { return self._maxBytes }
    Bool isAllowComments() { return self._allowComments }
    Bool isAllowTrailingComma() { return self._allowTrailingComma }
    Bool isPretty() { return self._pretty }
    JsonOptions copy() {
        JsonOptions out = new JsonOptions()
        out._maxDepth = self._maxDepth; out._maxBytes = self._maxBytes
        out._allowComments = self._allowComments; out._allowTrailingComma = self._allowTrailingComma
        out._pretty = self._pretty
        return out
    }
}

class Json {
    String _text
    Int _pos
    JsonOptions _options
    Json() { self._text = ""; self._pos = 0; self._options = new JsonOptions() }

    static Result<JsonValue, Error> parse(String text) { return Json.parseWithOptions(text, new JsonOptions()) }
    static Result<JsonValue, Error> parseWithOptions(String text, JsonOptions options) {
        if text == null || options == null { throw "Json.parse: null" }
        if text.length() as Long > options.getMaxBytes() { return Err(codecError(ErrorKind.DataCorrupted, "Json: input too large")) }
        Json p = new Json()
        p._text = text; p._pos = 0; p._options = options
        p.skipSpace()
        Result<JsonValue, Error> out = p.value(0)
        if out.isErr() { return out }
        p.skipSpace()
        if p._pos != p._text.length() { return Err(codecError(ErrorKind.DataCorrupted, "Json: trailing data")) }
        return out
    }
    static Result<JsonValue, Error> parseBytes(Bytes data) {
        if data == null { throw "Json.parseBytes: null" }
        return Json.parse(data.toString())
    }
    static Result<JsonObject, Error> parseObject(String text) {
        Result<JsonValue, Error> v = Json.parse(text)
        if v.isErr() { return Err(v.error()) }
        if !v.value().isObject() { return Err(codecError(ErrorKind.InvalidArgument, "Json.parseObject: not object")) }
        return Ok((v.value().asObject() as JsonObject))
    }
    static Result<JsonArray, Error> parseArray(String text) {
        Result<JsonValue, Error> v = Json.parse(text)
        if v.isErr() { return Err(v.error()) }
        if !v.value().isArray() { return Err(codecError(ErrorKind.InvalidArgument, "Json.parseArray: not array")) }
        return Ok((v.value().asArray() as JsonArray))
    }
    static Result<JsonValue, Error> parseReader(Context context, Reader reader) {
        if context == null || reader == null { throw "Json.parseReader: null" }
        String text = reader.readBytes(reader.remaining()).toString()
        return Json.parse(text)
    }

    static JsonValue object() { return new JsonValue(JsonKind.Object, false, null, null, null, new JsonObject()) }
    static JsonValue array() { return new JsonValue(JsonKind.Array, false, null, null, new JsonArray(), null) }
    static JsonValue string(String value) {
        if value == null { throw "Json.string: null" }
        return new JsonValue(JsonKind.String, false, null, value, null, null)
    }
    static JsonValue number(String raw) { return new JsonValue(JsonKind.Number, false, new JsonNumber(raw), null, null, null) }
    static JsonValue bool(Bool value) { return new JsonValue(JsonKind.Bool, value, null, null, null, null) }
    static JsonValue nullValue() { return new JsonValue(JsonKind.Null, false, null, null, null, null) }

    static String stringify(JsonValue value) {
        if value == null { throw "Json.stringify: null" }
        return Json.write(value, false, 0)
    }
    static String stringifyPretty(JsonValue value) {
        if value == null { throw "Json.stringify: null" }
        return Json.write(value, true, 0)
    }
    static Bytes toBytes(JsonValue value) { return Bytes.fromString(Json.stringify(value)) }
    static String write(JsonValue v, Bool pretty, Int depth) {
        if v.isNull() { return "null" }
        if v.isBool() {
            if (v.asBool() as Bool) { return "true" }
            return "false"
        }
        if v.isNumber() {
            JsonNumber numberValue = v.asNumber() as JsonNumber
            return numberValue.raw()
        }
        if v.isString() {
            String stringValue = v.asString() as String
            return Json.quote(stringValue)
        }
        if v.isArray() {
            JsonArray a = v.asArray() as JsonArray
            if a.length() == 0 { return "[]" }
            String out = "["
            Int i = 0
            while i < a.length() {
                if i > 0 { out = out + "," }
                if pretty { out = out + "\n" + Json.indent(depth + 1) }
                out = out + Json.write(a.get(i), pretty, depth + 1)
                i = i + 1
            }
            if pretty { out = out + "\n" + Json.indent(depth) }
            return out + "]"
        }
        JsonObject o = v.asObject() as JsonObject
        if o.length() == 0 { return "{}" }
        String out = "{"
        List<String> keys = o.keys()
        Int i = 0
        while i < keys.length() {
            if i > 0 { out = out + "," }
            if pretty { out = out + "\n" + Json.indent(depth + 1) }
            out = out + Json.quote(keys.get(i)) + (pretty ? ": " : ":") + Json.write(o.getOr(keys.get(i), Json.nullValue()), pretty, depth + 1)
            i = i + 1
        }
        if pretty { out = out + "\n" + Json.indent(depth) }
        return out + "}"
    }
    static Int controlCode(String c) {
        Int i = 0
        while i < 32 {
            if c == fromCodePoint(i) { return i }
            i = i + 1
        }
        return -1
    }
    static String hex2(Int value) {
        String table = "0123456789abcdef"
        return table.substring(value / 16, 1) + table.substring(value % 16, 1)
    }
    static String indent(Int depth) {
        String out = ""
        Int i = 0
        while i < depth { out = out + "  "; i = i + 1 }
        return out
    }
    static String quote(String text) {
        String out = "\""
        Int i = 0
        while i < text.length() {
            String c = text.substring(i, 1)
            if c == "\\" { out = out + "\\\\" }
            else if c == "\"" { out = out + "\\\"" }
            else if c == "\n" { out = out + "\\n" }
            else if c == "\r" { out = out + "\\r" }
            else if c == "\t" { out = out + "\\t" }
            else if c == fromCodePoint(8) { out = out + "\\b" }
            else if c == fromCodePoint(12) { out = out + "\\f" }
            else {
                Int control = Json.controlCode(c)
                if control >= 0 { out = out + "\\u00" + Json.hex2(control) } else { out = out + c }
            }
            i = i + 1
        }
        return out + "\""
    }
    static JsonValue? get(JsonValue value, String path) {
        if value == null || path == null { return null }
        JsonValue current = value
        List<String> parts = path.split(".")
        Int i = 0
        while i < parts.length() {
            String part = parts.get(i)
            if part == "" { i = i + 1; continue }
            if current.isObject() {
                JsonObject o = current.asObject() as JsonObject
                if !o.has(part) { return null }
                current = o.getOr(part, Json.nullValue())
            } else if current.isArray() {
                Int index = 0
                if !Json.parseInt(part, index) { return null }
                JsonArray a = current.asArray() as JsonArray
                index = Json.parseIntValue(part)
                if index < 0 || index >= a.length() { return null }
                current = a.get(index)
            } else { return null }
            i = i + 1
        }
        return current
    }
    static Bool parseInt(String text, Int unused) { return Json.parseIntValue(text) >= 0 }
    static Int parseIntValue(String text) {
        if text == "" { return -1 }
        Int value = 0
        Int i = 0
        while i < text.length() {
            Int d = JsonNumber.digitIndex(text.substring(i, 1))
            if d < 0 { return -1 }
            value = value * 10 + d
            i = i + 1
        }
        return value
    }
    static Result<String, Error> getString(JsonValue value, String path) {
        JsonValue? found = Json.get(value, path)
        if found == null { return Err(codecError(ErrorKind.NotFound, "Json.getString: missing")) }
        JsonValue actual = found as JsonValue
        if !actual.isString() { return Err(codecError(ErrorKind.InvalidArgument, "Json.getString: not string")) }
        return Ok(actual.asString() as String)
    }
    static Result<Int, Error> getInt(JsonValue value, String path) {
        JsonValue? found = Json.get(value, path)
        if found == null { return Err(codecError(ErrorKind.NotFound, "Json.getInt: missing")) }
        JsonValue actual = found as JsonValue
        if !actual.isNumber() { return Err(codecError(ErrorKind.InvalidArgument, "Json.getInt: not number")) }
        JsonNumber numberValue = actual.asNumber() as JsonNumber
        Result<Long, Error> v = numberValue.asLong()
        if v.isErr() { return Err(v.error()) }
        return Ok(v.value() as Int)
    }
    static Result<Bool, Error> getBool(JsonValue value, String path) {
        JsonValue? found = Json.get(value, path)
        if found == null { return Err(codecError(ErrorKind.NotFound, "Json.getBool: missing")) }
        JsonValue actual = found as JsonValue
        if !actual.isBool() { return Err(codecError(ErrorKind.InvalidArgument, "Json.getBool: not bool")) }
        return Ok(actual.asBool() as Bool)
    }

    Void skipSpace() {
        while self._pos < self._text.length() {
            String c = self._text.substring(self._pos, 1)
            if c == " " || c == "\t" || c == "\n" || c == "\r" { self._pos = self._pos + 1; continue }
            if self._options.isAllowComments() && c == "/" && self._pos + 1 < self._text.length() {
                String d = self._text.substring(self._pos + 1, 1)
                if d == "/" {
                    self._pos = self._pos + 2
                    while self._pos < self._text.length() && self._text.substring(self._pos, 1) != "\n" { self._pos = self._pos + 1 }
                    continue
                }
                if d == "*" {
                    self._pos = self._pos + 2
                    while self._pos + 1 < self._text.length() {
                        if self._text.substring(self._pos, 2) == "*/" { self._pos = self._pos + 2; break }
                        self._pos = self._pos + 1
                    }
                    continue
                }
            }
            break
        }
    }
    Result<JsonValue, Error> value(Int depth) {
        if depth > self._options.getMaxDepth() { return Err(codecError(ErrorKind.DataCorrupted, "Json: max depth exceeded")) }
        if self._pos >= self._text.length() { return Err(codecError(ErrorKind.DataCorrupted, "Json: unexpected end")) }
        String c = self._text.substring(self._pos, 1)
        if c == "n" { if self.match("null") { return Ok(Json.nullValue()) } }
        if c == "t" { if self.match("true") { return Ok(Json.bool(true)) } }
        if c == "f" { if self.match("false") { return Ok(Json.bool(false)) } }
        if c == "\"" { return self.readString() }
        if c == "[" { return self.readArray(depth) }
        if c == "{" { return self.readObject(depth) }
        if c == "-" || JsonNumber.isDigit(c) { return self.readNumber() }
        return Err(codecError(ErrorKind.DataCorrupted, "Json: unexpected character"))
    }
    Bool match(String word) {
        if self._pos + word.length() > self._text.length() { return false }
        if self._text.substring(self._pos, word.length()) != word { return false }
        self._pos = self._pos + word.length()
        return true
    }
    Result<JsonValue, Error> readString() {
        self._pos = self._pos + 1
        String out = ""
        while self._pos < self._text.length() {
            String c = self._text.substring(self._pos, 1)
            if c == "\"" { self._pos = self._pos + 1; return Ok(Json.string(out)) }
            if c == "\\" {
                self._pos = self._pos + 1
                if self._pos >= self._text.length() { return Err(codecError(ErrorKind.DataCorrupted, "Json: bad escape")) }
                String e = self._text.substring(self._pos, 1)
                self._pos = self._pos + 1
                if e == "\"" { out = out + "\"" }
                else if e == "\\" { out = out + "\\" }
                else if e == "/" { out = out + "/" }
                else if e == "b" { out = out + fromCodePoint(8) }
                else if e == "f" { out = out + fromCodePoint(12) }
                else if e == "n" { out = out + "\n" }
                else if e == "r" { out = out + "\r" }
                else if e == "t" { out = out + "\t" }
                else if e == "u" {
                    if self._pos + 4 > self._text.length() { return Err(codecError(ErrorKind.DataCorrupted, "Json: bad unicode escape")) }
                    Int code = Json.hex4(self._text.substring(self._pos, 4))
                    if code < 0 { return Err(codecError(ErrorKind.DataCorrupted, "Json: bad unicode escape")) }
                    self._pos = self._pos + 4
                    if code >= 0xD800 && code <= 0xDBFF && self._pos + 6 <= self._text.length() {
                        if self._text.substring(self._pos, 2) == "\\u" {
                            Int low = Json.hex4(self._text.substring(self._pos + 2, 4))
                            if low >= 0xDC00 && low <= 0xDFFF {
                                code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                                self._pos = self._pos + 6
                            }
                        }
                    }
                    out = out + fromCodePoint(code)
                } else { return Err(codecError(ErrorKind.DataCorrupted, "Json: bad escape")) }
            } else {
                out = out + c
                self._pos = self._pos + 1
            }
        }
        return Err(codecError(ErrorKind.DataCorrupted, "Json: unterminated string"))
    }
    static Int hex4(String text) {
        Int out = 0
        Int i = 0
        while i < 4 {
            Int d = Json.hexDigit(text.substring(i, 1))
            if d < 0 { return -1 }
            out = out * 16 + d
            i = i + 1
        }
        return out
    }
    static Int hexDigit(String c) {
        Int d = "0123456789abcdef".indexOf(c)
        if d >= 0 { return d }
        Int u = "0123456789ABCDEF".indexOf(c)
        if u >= 0 { return u }
        return -1
    }
    Result<JsonValue, Error> readNumber() {
        Int start = self._pos
        if self._text.substring(self._pos, 1) == "-" { self._pos = self._pos + 1 }
        while self._pos < self._text.length() {
            String c = self._text.substring(self._pos, 1)
            if JsonNumber.isDigit(c) || c == "." || c == "e" || c == "E" || c == "+" || c == "-" { self._pos = self._pos + 1 } else { break }
        }
        String raw = self._text.substring(start, self._pos - start)
        if !JsonNumber.isValidText(raw) { return Err(codecError(ErrorKind.DataCorrupted, "Json: invalid number")) }
        return Ok(Json.number(raw))
    }
    Result<JsonValue, Error> readArray(Int depth) {
        self._pos = self._pos + 1
        JsonArray arr = new JsonArray()
        self.skipSpace()
        if self._pos < self._text.length() && self._text.substring(self._pos, 1) == "]" { self._pos = self._pos + 1; return Ok(new JsonValue(JsonKind.Array, false, null, null, arr, null)) }
        while true {
            self.skipSpace()
            if self._pos < self._text.length() && self._text.substring(self._pos, 1) == "]" && self._options.isAllowTrailingComma() { self._pos = self._pos + 1; break }
            Result<JsonValue, Error> v = self.value(depth + 1)
            if v.isErr() { return v }
            arr.add(v.value())
            self.skipSpace()
            if self._pos >= self._text.length() { return Err(codecError(ErrorKind.DataCorrupted, "Json: unterminated array")) }
            String c = self._text.substring(self._pos, 1)
            if c == "]" { self._pos = self._pos + 1; break }
            if c != "," { return Err(codecError(ErrorKind.DataCorrupted, "Json: expected , or ]")) }
            self._pos = self._pos + 1
        }
        return Ok(new JsonValue(JsonKind.Array, false, null, null, arr, null))
    }
    Result<JsonValue, Error> readObject(Int depth) {
        self._pos = self._pos + 1
        JsonObject obj = new JsonObject()
        self.skipSpace()
        if self._pos < self._text.length() && self._text.substring(self._pos, 1) == "}" { self._pos = self._pos + 1; return Ok(new JsonValue(JsonKind.Object, false, null, null, null, obj)) }
        while true {
            self.skipSpace()
            if self._pos >= self._text.length() || self._text.substring(self._pos, 1) != "\"" { return Err(codecError(ErrorKind.DataCorrupted, "Json: expected key")) }
            Result<JsonValue, Error> k = self.readString()
            if k.isErr() { return k }
            self.skipSpace()
            if self._pos >= self._text.length() || self._text.substring(self._pos, 1) != ":" { return Err(codecError(ErrorKind.DataCorrupted, "Json: expected :")) }
            self._pos = self._pos + 1
            Result<JsonValue, Error> v = self.value(depth + 1)
            if v.isErr() { return v }
            obj.set(k.value().asString() as String, v.value())
            self.skipSpace()
            if self._pos >= self._text.length() { return Err(codecError(ErrorKind.DataCorrupted, "Json: unterminated object")) }
            String c = self._text.substring(self._pos, 1)
            if c == "}" { self._pos = self._pos + 1; break }
            if c != "," { return Err(codecError(ErrorKind.DataCorrupted, "Json: expected , or }")) }
            self._pos = self._pos + 1
            self.skipSpace()
            if self._pos < self._text.length() && self._text.substring(self._pos, 1) == "}" && self._options.isAllowTrailingComma() { self._pos = self._pos + 1; break }
        }
        return Ok(new JsonValue(JsonKind.Object, false, null, null, null, obj))
    }
}

class CsvOptions {
    Char _delimiter
    Char _quote
    Char _escape
    Bool _hasHeader
    Bool _skipEmptyLines
    Bool _trim
    CsvOptions() { self._delimiter = ','; self._quote = '"'; self._escape = '\\'; self._hasHeader = false; self._skipEmptyLines = true; self._trim = false }
    CsvOptions delimiter(Char value) { self._delimiter = value; return self }
    CsvOptions quote(Char value) { self._quote = value; return self }
    CsvOptions escape(Char value) { self._escape = value; return self }
    CsvOptions hasHeader(Bool value) { self._hasHeader = value; return self }
    CsvOptions skipEmptyLines(Bool value) { self._skipEmptyLines = value; return self }
    CsvOptions trim(Bool value) { self._trim = value; return self }
    Char getDelimiter() { return self._delimiter }
    Char getQuote() { return self._quote }
    Char getEscape() { return self._escape }
    Bool isHasHeader() { return self._hasHeader }
    Bool isSkipEmptyLines() { return self._skipEmptyLines }
    Bool isTrim() { return self._trim }
    CsvOptions copy() {
        CsvOptions out = new CsvOptions()
        out._delimiter = self._delimiter; out._quote = self._quote; out._escape = self._escape
        out._hasHeader = self._hasHeader; out._skipEmptyLines = self._skipEmptyLines; out._trim = self._trim
        return out
    }
}

class Csv {
    Csv() { }
    static Result<List<List<String>>, Error> parse(String text, CsvOptions options) {
        if text == null || options == null { throw "Csv.parse: null" }
        List<List<String>> rows = []
        List<String> row = []
        String field = ""
        Bool quoted = false
        Int i = 0
        while i < text.length() {
            String c = text.substring(i, 1)
            String quoteText = charText(options.getQuote())
            String delimiterText = charText(options.getDelimiter())
            String escapeText = charText(options.getEscape())
            if quoted {
                if c == quoteText && i + 1 < text.length() && text.substring(i + 1, 1) == quoteText {
                    field = field + quoteText; i = i + 2; continue
                }
                if c == escapeText && i + 1 < text.length() && text.substring(i + 1, 1) == quoteText {
                    field = field + quoteText; i = i + 2; continue
                }
                if c == quoteText { quoted = false; i = i + 1; continue }
                field = field + c; i = i + 1; continue
            }
            if c == quoteText { quoted = true; i = i + 1; continue }
            if c == delimiterText { row.push(options.isTrim() ? field.trim() : field); field = ""; i = i + 1; continue }
            if c == "\n" {
                row.push(options.isTrim() ? field.trim() : field)
                Bool blank = row.length() == 1 && row.get(0) == ""
                if !(blank && options.isSkipEmptyLines()) { rows.push(row) }
                row = []; field = ""; i = i + 1; continue
            }
            if c == "\r" { i = i + 1; continue }
            field = field + c; i = i + 1
        }
        if quoted { return Err(codecError(ErrorKind.DataCorrupted, "Csv: unterminated quote")) }
        if field != "" || row.length() > 0 {
            row.push(options.isTrim() ? field.trim() : field)
            Bool blank = row.length() == 1 && row.get(0) == ""
            if !(blank && options.isSkipEmptyLines()) { rows.push(row) }
        }
        return Ok(rows)
    }
    static Result<List<List<String>>, Error> parseReader(Context context, Reader reader, CsvOptions options) {
        if context == null || reader == null { throw "Csv.parseReader: null" }
        return Csv.parse(reader.readBytes(reader.remaining()).toString(), options)
    }
    static String write(List<List<String>> rows, CsvOptions options) {
        if rows == null || options == null { throw "Csv.write: null" }
        String out = ""
        Int r = 0
        while r < rows.length() {
            List<String> row = rows.get(r)
            Int c = 0
            while c < row.length() {
                String delimiterText = charText(options.getDelimiter())
                String quoteText = charText(options.getQuote())
                if c > 0 { out = out + delimiterText }
                String f = row.get(c)
                Bool need = f.indexOf(delimiterText) >= 0 || f.indexOf(quoteText) >= 0 || f.indexOf("\n") >= 0 || f.indexOf("\r") >= 0
                if need {
                    out = out + quoteText + f.replace(quoteText, quoteText + quoteText) + quoteText
                } else { out = out + f }
                c = c + 1
            }
            out = out + "\n"
            r = r + 1
        }
        return out
    }
    static Result<Unit, Error> writeTo(Context context, Writer writer, List<List<String>> rows, CsvOptions options) {
        if context == null || writer == null { throw "Csv.writeTo: null" }
        writer.writeBytes(Bytes.fromString(Csv.write(rows, options)))
        return Ok()
    }
}

class CsvReader {
    final Reader _reader
    final CsvOptions _options
    List<List<String>> _rows
    Int _index
    Bool _closed
    CsvReader(Reader reader, CsvOptions options) {
        if reader == null || options == null { throw "CsvReader: null" }
        self._reader = reader; self._options = options
        self._rows = []; self._index = 0; self._closed = false
    }
    Result<List<String>?, Error> readRecord() {
        if self._closed { return Err(codecError(ErrorKind.Unavailable, "CsvReader: closed")) }
        if self._index == 0 {
            Result<List<List<String>>, Error> parsed = Csv.parse(self._reader.readBytes(self._reader.remaining()).toString(), self._options)
            if parsed.isErr() { return Err(parsed.error()) }
            self._rows = parsed.value()
        }
        if self._index >= self._rows.length() { return Ok(null) }
        List<String> row = self._rows.get(self._index)
        self._index = self._index + 1
        return Ok(row)
    }
    Result<List<List<String>>, Error> readAll() {
        Result<List<List<String>>, Error> parsed = Csv.parse(self._reader.readBytes(self._reader.remaining()).toString(), self._options)
        return parsed
    }
    List<String> headers() {
        if self._options.isHasHeader() && self._rows.length() > 0 { return self._rows.get(0) }
        List<String> empty = []
        return empty
    }
    Result<Unit, Error> close() { self._closed = true; return Ok() }
}

class CsvWriter {
    final Writer _writer
    final CsvOptions _options
    Bool _closed
    CsvWriter(Writer writer, CsvOptions options) {
        if writer == null || options == null { throw "CsvWriter: null" }
        self._writer = writer; self._options = options; self._closed = false
    }
    Result<Unit, Error> writeRecord(List<String> row) {
        if self._closed { return Err(codecError(ErrorKind.Unavailable, "CsvWriter: closed")) }
        List<List<String>> rows = []; rows.push(row)
        self._writer.writeBytes(Bytes.fromString(Csv.write(rows, self._options)))
        return Ok()
    }
    Result<Unit, Error> writeAll(List<List<String>> rows) {
        if self._closed { return Err(codecError(ErrorKind.Unavailable, "CsvWriter: closed")) }
        self._writer.writeBytes(Bytes.fromString(Csv.write(rows, self._options)))
        return Ok()
    }
    Result<Unit, Error> flush() { return Ok() }
    Result<Unit, Error> close() { self._closed = true; return Ok() }
}

class Base64 {
    Base64() { }
    static String alphabet(Bool url) {
        if url { return "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_" }
        return "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    }
    static String encodeBytes(Bytes data, Bool url, Bool pad) {
        if data == null { throw "Base64.encode: null" }
        String table = Base64.alphabet(url)
        String out = ""
        Int i = 0
        while i < data.length() {
            Int a = data.get(i)
            Int b = 0
            Int c = 0
            if i + 1 < data.length() { b = data.get(i + 1) }
            if i + 2 < data.length() { c = data.get(i + 2) }
            Int n = (a << 16) + (b << 8) + c
            out = out + table.substring((n >> 18) & 63, 1) + table.substring((n >> 12) & 63, 1)
            if i + 1 < data.length() { out = out + table.substring((n >> 6) & 63, 1) } else if pad { out = out + "=" }
            if i + 2 < data.length() { out = out + table.substring(n & 63, 1) } else if pad { out = out + "=" }
            i = i + 3
        }
        return out
    }
    static String encode(Bytes data) { return Base64.encodeBytes(data, false, true) }
    static String encodeUrl(Bytes data) { return Base64.encodeBytes(data, true, true) }
    static String encodeNoPadding(Bytes data) { return Base64.encodeBytes(data, false, false) }
    static Result<Bytes, Error> decodeText(String text, Bool url, Bool pad) {
        if text == null { throw "Base64.decode: null" }
        Int end = text.length()
        if pad {
            if text.length() % 4 != 0 { return Err(codecError(ErrorKind.DataCorrupted, "Base64: invalid length")) }
        } else {
            while end > 0 && text.substring(end - 1, 1) == "=" { end = end - 1 }
            if end % 4 == 1 { return Err(codecError(ErrorKind.DataCorrupted, "Base64: invalid length")) }
        }
        String table = Base64.alphabet(url)
        Bytes out = Bytes.fromString("")
        Int buffer = 0
        Int bits = 0
        Int i = 0
        while i < end {
            String ch = text.substring(i, 1)
            if ch == "=" { i = i + 1; continue }
            Int v = table.indexOf(ch)
            if v < 0 { return Err(codecError(ErrorKind.DataCorrupted, "Base64: invalid character")) }
            buffer = (buffer << 6) | v
            bits = bits + 6
            if bits >= 8 { bits = bits - 8; out.push((buffer >> bits) & 255) }
            i = i + 1
        }
        return Ok(out)
    }
    static Result<Bytes, Error> decode(String text) { return Base64.decodeText(text, false, true) }
    static Result<Bytes, Error> decodeUrl(String text) { return Base64.decodeText(text, true, true) }
    static Result<Bytes, Error> decodeNoPadding(String text) { return Base64.decodeText(text, false, false) }
    static Int encodedLength(Int length) {
        if length < 0 { throw "Base64.encodedLength: negative" }
        if length == 0 { return 0 }
        return ((length + 2) / 3) * 4
    }
    static Int decodedLength(Int length) {
        if length < 0 { throw "Base64.decodedLength: negative" }
        if length == 0 { return 0 }
        return (length / 4) * 3
    }
}

class Hex {
    Hex() { }
    static String encode(Bytes data) { return Hex.encodeCase(data, false) }
    static String encodeUpper(Bytes data) { return Hex.encodeCase(data, true) }
    static String encodeCase(Bytes data, Bool upper) {
        if data == null { throw "Hex.encode: null" }
        String low = "0123456789abcdef"
        String high = "0123456789ABCDEF"
        String digits = upper ? high : low
        String out = ""
        Int i = 0
        while i < data.length() {
            Int v = data.get(i)
            out = out + digits.substring(v / 16, 1) + digits.substring(v % 16, 1)
            i = i + 1
        }
        return out
    }
    static Bool isValid(String text) {
        if text == null || text.length() % 2 != 0 { return false }
        Int i = 0
        while i < text.length() {
            if Json.hexDigit(text.substring(i, 1)) < 0 { return false }
            i = i + 1
        }
        return true
    }
    static Result<Bytes, Error> decode(String text) {
        if !Hex.isValid(text) { return Err(codecError(ErrorKind.DataCorrupted, "Hex: invalid")) }
        Bytes out = Bytes.fromString("")
        Int i = 0
        while i < text.length() {
            out.push(Json.hexDigit(text.substring(i, 1)) * 16 + Json.hexDigit(text.substring(i + 1, 1)))
            i = i + 2
        }
        return Ok(out)
    }
}
