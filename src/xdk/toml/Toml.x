// xdk.toml —— TOML 1.0 子集解析/生成（M18.3）
//
// 解析结果映射到 xdk.codec.JsonValue：表→JsonObject，数组→JsonArray，标量→JsonValue。
// 不支持日期/时间、多行字符串、inf/nan、null；显式返回 Unsupported。
// 稳定性：preview。合同见 docs/design/utils/toml/。
package xdk.toml
import xdk.errors
import xdk.codec
import xdk.text

// ---------- TomlOptions ----------
class TomlOptions {
    Int _maxDepth
    Long _maxBytes

    TomlOptions() {
        self._maxDepth = 64
        self._maxBytes = 1048576 as Long
    }

    TomlOptions maxDepth(Int value) {
        if value <= 0 { throw "TomlOptions.maxDepth: must be positive" }
        self._maxDepth = value
        return self
    }

    TomlOptions maxBytes(Long value) {
        if value <= 0 { throw "TomlOptions.maxBytes: must be positive" }
        self._maxBytes = value
        return self
    }

    Int getMaxDepth() { return self._maxDepth }
    Long getMaxBytes() { return self._maxBytes }

    TomlOptions copy() {
        TomlOptions out = new TomlOptions()
        out._maxDepth = self._maxDepth
        out._maxBytes = self._maxBytes
        return out
    }
}

// ---------- helpers ----------
static Error tomlError(ErrorKind kind, String message) {
    return new BasicError(kind, message)
}

static Bool tomlBareKeyChar(Int code) {
    if code >= 48 && code <= 57 { return true }
    if code >= 65 && code <= 90 { return true }
    if code >= 97 && code <= 122 { return true }
    return code == 95 || code == 45
}

static String tomlHexDigits() {
    return "0123456789abcdef"
}

static Int tomlHexValue(String c) {
    if c.length() != 1 { return -1 }
    Int code = c.get(0)
    if code >= 48 && code <= 57 { return code - 48 }
    if code >= 97 && code <= 102 { return code - 97 + 10 }
    if code >= 65 && code <= 70 { return code - 65 + 10 }
    return -1
}

// 十进制数字串 -> Long；越界返回 null。
static Long? tomlDigitsToLong(String digits, Bool negative) {
    if digits.length() == 0 { return null }
    Long max = 9223372036854775807 as Long
    Long value = 0 as Long
    Int index = 0
    while index < digits.length() {
        Int code = digits.get(index)
        if code < 48 || code > 57 { return null }
        Long digit = (code - 48) as Long
        if value > (max - digit) / (10 as Long) { return null }
        value = value * (10 as Long) + digit
        index = index + 1
    }
    if negative { value = -value }
    return value
}

// 指定进制数字串 -> 十进制文本；越界/非法返回 null。
static String? tomlRadixToDecimal(String digits, Int radix) {
    if digits.length() == 0 { return null }
    Long max = 9223372036854775807 as Long
    Long value = 0 as Long
    Int index = 0
    while index < digits.length() {
        Int code = digits.get(index)
        Int digit = -1
        if code >= 48 && code <= 57 { digit = code - 48 }
        if code >= 97 && code <= 102 { digit = code - 97 + 10 }
        if code >= 65 && code <= 70 { digit = code - 65 + 10 }
        if digit < 0 || digit >= radix { return null }
        if value > (max - (digit as Long)) / (radix as Long) { return null }
        value = value * (radix as Long) + (digit as Long)
        index = index + 1
    }
    return str(value)
}

static String tomlJoinPath(List<String> path) {
    String out = ""
    Int index = 0
    while index < path.length() {
        if index > 0 { out = out + "." }
        out = out + path.get(index)
        index = index + 1
    }
    return out
}

static Bool tomlPathPrefix(String prefix, String path) {
    if prefix == path { return true }
    if prefix.length() >= path.length() { return false }
    return path.substring(0, prefix.length()) == prefix &&
        path.substring(prefix.length(), 1) == "."
}

static Bool tomlIsIntegerText(String raw) {
    if raw.length() == 0 { return false }
    Int index = 0
    if raw.substring(0, 1) == "-" { index = 1 }
    if index >= raw.length() { return false }
    while index < raw.length() {
        Int code = raw.get(index)
        if code < 48 || code > 57 { return false }
        index = index + 1
    }
    return true
}

// ---------- parser ----------
class TomlParser {
    final String _text
    final Int _length
    final TomlOptions _options
    Int _pos
    Bool _failed
    ErrorKind _kind
    String _message
    JsonObject _root
    List<String> _definedTables
    List<String> _closedTables
    List<String> _currentPath
    JsonObject _current

    TomlParser(String text, TomlOptions options) {
        self._text = text
        self._length = text.length()
        self._options = options
        self._pos = 0
        self._failed = false
        self._kind = ErrorKind.DataCorrupted
        self._message = ""
        self._root = new JsonObject()
        self._definedTables = []
        self._closedTables = []
        self._currentPath = []
        self._current = self._root
    }

    Bool fail(ErrorKind kind, String message) {
        if !self._failed {
            self._failed = true
            self._kind = kind
            self._message = message
        }
        return false
    }

    Bool atEnd() {
        return self._pos >= self._length
    }

    String peek() {
        if self._pos >= self._length { return "" }
        return self._text.substring(self._pos, 1)
    }

    String peekAt(Int offset) {
        Int at = self._pos + offset
        if at < 0 || at >= self._length { return "" }
        return self._text.substring(at, 1)
    }

    Void advance() {
        self._pos = self._pos + 1
    }

    Void skipInline() {
        while !self.atEnd() {
            String c = self.peek()
            if c == " " || c == "\t" { self.advance() } else { return }
        }
    }

    Void skipBlank() {
        while !self.atEnd() {
            String c = self.peek()
            if c == " " || c == "\t" || c == "\r" || c == "\n" {
                self.advance()
            } else if c == "#" {
                while !self.atEnd() && self.peek() != "\n" { self.advance() }
            } else {
                return
            }
        }
    }

    Void skipComment() {
        self.skipInline()
        if self.peek() == "#" {
            while !self.atEnd() && self.peek() != "\n" { self.advance() }
        }
    }

    Bool finishStatement() {
        self.skipComment()
        if self.atEnd() { return true }
        if self.peek() == "\r" { self.advance() }
        if self.peek() == "\n" { self.advance(); return true }
        return self.fail(ErrorKind.DataCorrupted, "TOML: expected end of line")
    }

    Bool closedPath(List<String> path) {
        String joined = tomlJoinPath(path)
        Int index = 0
        while index < self._closedTables.length() {
            String closed = self._closedTables.get(index)
            if tomlPathPrefix(closed, joined) {
                return true
            }
            index = index + 1
        }
        return false
    }

    Bool depthOk(Int depth) {
        if depth > self._options.getMaxDepth() {
            return self.fail(ErrorKind.InvalidArgument, "TOML: maxDepth exceeded")
        }
        return true
    }

    Result<JsonValue, Error> parseDocument() {
        if self._length as Long > self._options.getMaxBytes() {
            return Err(tomlError(ErrorKind.InvalidArgument, "TOML: input exceeds maxBytes"))
        }
        while !self.atEnd() && !self._failed {
            self.skipBlank()
            if self.atEnd() { break }
            if self.peek() == "[" {
                if self.peekAt(1) == "[" {
                    self.parseArrayTable()
                } else {
                    self.parseTable()
                }
            } else {
                self.parseKeyValue()
            }
            if !self._failed {
                self.finishStatement()
            }
        }
        if self._failed {
            return Err(tomlError(self._kind, self._message))
        }
        return Ok(new JsonValue(JsonKind.Object, false, null, null, null, self._root))
    }

    List<String> parseKeyPath() {
        List<String> parts = []
        while true {
            self.skipInline()
            String? part = self.parseKey()
            if part == null {
                List<String> none = []
                return none
            }
            String text = part as String
            if self._failed {
                List<String> none = []
                return none
            }
            if text == "" {
                self.fail(ErrorKind.Unsupported, "TOML: empty key is not supported")
                List<String> none = []
                return none
            }
            parts.push(text)
            self.skipInline()
            if self.peek() != "." {
                return parts
            }
            self.advance()
        }
        return parts
    }

    String? parseKey() {
        String c = self.peek()
        if c == "\"" {
            return self.parseBasicString()
        }
        if c == "'" {
            return self.parseLiteralString()
        }
        Int start = self._pos
        while !self.atEnd() {
            String current = self.peek()
            if current.length() == 1 && tomlBareKeyChar(current.get(0)) {
                self.advance()
            } else {
                break
            }
        }
        if self._pos == start { return null }
        return self._text.substring(start, self._pos - start)
    }

    String? parseBasicString() {
        if self.peek() != "\"" { return null }
        if self.peekAt(1) == "\"" && self.peekAt(2) == "\"" {
            self.fail(ErrorKind.Unsupported, "TOML: multiline strings are not supported")
            return null
        }
        self.advance()
        String result = ""
        while !self.atEnd() {
            String c = self.peek()
            if c == "\"" {
                self.advance()
                return result
            }
            if c == "\n" || c == "\r" {
                self.fail(ErrorKind.DataCorrupted, "TOML: newline in basic string")
                return null
            }
            if c == "\\" {
                self.advance()
                String? escaped = self.parseEscape()
                if escaped == null { return null }
                result = result + (escaped as String)
            } else {
                result = result + c
                self.advance()
            }
        }
        self.fail(ErrorKind.DataCorrupted, "TOML: unterminated string")
        return null
    }

    String? parseEscape() {
        String c = self.peek()
        if c == "" { return null }
        self.advance()
        if c == "b" { return fromCodePoint(8) }
        if c == "t" { return fromCodePoint(9) }
        if c == "n" { return fromCodePoint(10) }
        if c == "f" { return fromCodePoint(12) }
        if c == "r" { return fromCodePoint(13) }
        if c == "\"" { return "\"" }
        if c == "\\" { return "\\" }
        if c == "u" {
            return self.parseUnicodeEscape(4)
        }
        if c == "U" {
            return self.parseUnicodeEscape(8)
        }
        self.fail(ErrorKind.DataCorrupted, "TOML: invalid escape")
        return null
    }

    String? parseUnicodeEscape(Int count) {
        Int value = 0
        Int index = 0
        while index < count {
            String c = self.peek()
            if c == "" { return null }
            Int digit = tomlHexValue(c)
            if digit < 0 {
                self.fail(ErrorKind.DataCorrupted, "TOML: invalid unicode escape")
                return null
            }
            value = value * 16 + digit
            self.advance()
            index = index + 1
        }
        return fromCodePoint(value)
    }

    String? parseLiteralString() {
        if self.peek() != "'" { return null }
        if self.peekAt(1) == "'" && self.peekAt(2) == "'" {
            self.fail(ErrorKind.Unsupported, "TOML: multiline strings are not supported")
            return null
        }
        self.advance()
        String result = ""
        while !self.atEnd() {
            String c = self.peek()
            if c == "'" {
                self.advance()
                return result
            }
            if c == "\n" || c == "\r" {
                self.fail(ErrorKind.DataCorrupted, "TOML: newline in literal string")
                return null
            }
            result = result + c
            self.advance()
        }
        self.fail(ErrorKind.DataCorrupted, "TOML: unterminated literal string")
        return null
    }

    JsonObject? ensureObject(JsonObject parent, String key, List<String> path, Bool allowArray) {
        JsonValue? existing = parent.getOrNull(key)
        if existing == null {
            JsonValue created = new JsonValue(JsonKind.Object, false, null, null, null, new JsonObject())
            parent.set(key, created)
            path.push(key)
            if !self.depthOk(path.length()) { return null }
            return created.asObject() as JsonObject
        }
        JsonValue value = existing as JsonValue
        if value.isObject() {
            path.push(key)
            if !self.depthOk(path.length()) { return null }
            return value.asObject() as JsonObject
        }
        if allowArray && value.isArray() {
            JsonArray array = value.asArray() as JsonArray
            if array.length() == 0 {
                self.fail(ErrorKind.DataCorrupted, "TOML: empty array table")
                return null
            }
            JsonValue last = array.get(array.length() - 1)
            if !last.isObject() {
                self.fail(ErrorKind.DataCorrupted, "TOML: array table element is not a table")
                return null
            }
            path.push(key)
            return last.asObject() as JsonObject
        }
        self.fail(ErrorKind.DataCorrupted, "TOML: key is not a table")
        return null
    }

    Void parseTable() {
        self.advance()
        List<String> parts = self.parseKeyPath()
        if parts.length() == 0 { return }
        self.skipInline()
        if self.peek() != "]" {
            self.fail(ErrorKind.DataCorrupted, "TOML: expected ]")
            return
        }
        self.advance()
        if parts.length() > self._options.getMaxDepth() {
            self.fail(ErrorKind.InvalidArgument, "TOML: maxDepth exceeded")
            return
        }
        JsonObject table = self._root
        List<String> path = []
        Int index = 0
        while index < parts.length() - 1 {
            String segment = parts.get(index)
            List<String> probe = path.copy()
            probe.push(segment)
            if self.closedPath(probe) {
                self.fail(ErrorKind.DataCorrupted, "TOML: inline table is closed")
                return
            }
            JsonObject? next = self.ensureObject(table, segment, path, true)
            if next == null { return }
            table = next as JsonObject
            index = index + 1
        }
        String last = parts.get(parts.length() - 1)
        path.push(last)
        if self.closedPath(path) {
            self.fail(ErrorKind.DataCorrupted, "TOML: inline table is closed")
            return
        }
        JsonValue? existing = table.getOrNull(last)
        String joined = tomlJoinPath(path)
        if existing == null {
            JsonValue created = new JsonValue(JsonKind.Object, false, null, null, null, new JsonObject())
            table.set(last, created)
            table = created.asObject() as JsonObject
        } else {
            JsonValue value = existing as JsonValue
            if !value.isObject() {
                self.fail(ErrorKind.DataCorrupted, "TOML: table conflicts with value")
                return
            }
            Int defined = 0
            while defined < self._definedTables.length() {
                if self._definedTables.get(defined) == joined {
                    self.fail(ErrorKind.DataCorrupted, "TOML: duplicate table")
                    return
                }
                defined = defined + 1
            }
            table = value.asObject() as JsonObject
        }
        self._definedTables.push(joined)
        self._currentPath = path
        self._current = table
    }

    Void parseArrayTable() {
        self.advance()
        self.advance()
        List<String> parts = self.parseKeyPath()
        if parts.length() == 0 { return }
        self.skipInline()
        if self.peek() != "]" || self.peekAt(1) != "]" {
            self.fail(ErrorKind.DataCorrupted, "TOML: expected ]]")
            return
        }
        self.advance()
        self.advance()
        if parts.length() > self._options.getMaxDepth() {
            self.fail(ErrorKind.InvalidArgument, "TOML: maxDepth exceeded")
            return
        }
        JsonObject table = self._root
        List<String> path = []
        Int index = 0
        while index < parts.length() - 1 {
            String segment = parts.get(index)
            List<String> probe = path.copy()
            probe.push(segment)
            if self.closedPath(probe) {
                self.fail(ErrorKind.DataCorrupted, "TOML: inline table is closed")
                return
            }
            JsonObject? next = self.ensureObject(table, segment, path, true)
            if next == null { return }
            table = next as JsonObject
            index = index + 1
        }
        String last = parts.get(parts.length() - 1)
        path.push(last)
        JsonValue? existing = table.getOrNull(last)
        JsonArray array = new JsonArray()
        if existing == null {
            array = new JsonArray()
            table.set(last, new JsonValue(JsonKind.Array, false, null, null, array, null))
        } else {
            JsonValue value = existing as JsonValue
            if !value.isArray() {
                self.fail(ErrorKind.DataCorrupted, "TOML: array table conflicts with value")
                return
            }
            array = value.asArray() as JsonArray
        }
        JsonObject element = new JsonObject()
        array.add(new JsonValue(JsonKind.Object, false, null, null, null, element))
        self._currentPath = path
        self._current = element
    }

    Void parseKeyValue() {
        List<String> parts = self.parseKeyPath()
        if parts.length() == 0 { return }
        self.skipInline()
        if self.peek() != "=" {
            self.fail(ErrorKind.DataCorrupted, "TOML: expected =")
            return
        }
        self.advance()
        self.skipInline()
        Int depth = self._currentPath.length() + parts.length()
        if !self.depthOk(depth) { return }
        JsonValue? value = self.parseValue(depth)
        if value == null { return }
        JsonValue actual = value as JsonValue
        JsonObject table = self._current
        List<String> path = self._currentPath.copy()
        Int index = 0
        while index < parts.length() - 1 {
            String segment = parts.get(index)
            List<String> probe = path.copy()
            probe.push(segment)
            if self.closedPath(probe) {
                self.fail(ErrorKind.DataCorrupted, "TOML: inline table is closed")
                return
            }
            JsonObject? next = self.ensureObject(table, segment, path, false)
            if next == null { return }
            table = next as JsonObject
            index = index + 1
        }
        String last = parts.get(parts.length() - 1)
        path.push(last)
        if table.has(last) {
            self.fail(ErrorKind.DataCorrupted, "TOML: duplicate key")
            return
        }
        table.set(last, actual)
        if actual.isObject() {
            self._closedTables.push(tomlJoinPath(path))
        }
    }

    JsonValue? parseValue(Int depth) {
        if !self.depthOk(depth) { return null }
        String c = self.peek()
        if c == "\"" {
            String? text = self.parseBasicString()
            if text == null { return null }
            return new JsonValue(JsonKind.String, false, null, text, null, null)
        }
        if c == "'" {
            String? text = self.parseLiteralString()
            if text == null { return null }
            return new JsonValue(JsonKind.String, false, null, text, null, null)
        }
        if c == "[" { return self.parseArray(depth) }
        if c == "{" { return self.parseInlineTable(depth) }
        if self.startsWith("true") {
            self.advanceBy(4)
            return new JsonValue(JsonKind.Bool, true, null, null, null, null)
        }
        if self.startsWith("false") {
            self.advanceBy(5)
            return new JsonValue(JsonKind.Bool, false, null, null, null, null)
        }
        return self.parseScalar()
    }

    Bool startsWith(String text) {
        if self._pos + text.length() > self._length { return false }
        return self._text.substring(self._pos, text.length()) == text
    }

    Void advanceBy(Int count) {
        self._pos = self._pos + count
    }

    JsonValue? parseArray(Int depth) {
        self.advance()
        JsonArray array = new JsonArray()
        while true {
            self.skipBlank()
            if self.atEnd() {
                self.fail(ErrorKind.DataCorrupted, "TOML: unterminated array")
                return null
            }
            if self.peek() == "]" {
                self.advance()
                return new JsonValue(JsonKind.Array, false, null, null, array, null)
            }
            JsonValue? item = self.parseValue(depth + 1)
            if item == null { return null }
            array.add(item as JsonValue)
            self.skipBlank()
            if self.peek() == "," {
                self.advance()
            } else if self.peek() == "]" {
                self.advance()
                return new JsonValue(JsonKind.Array, false, null, null, array, null)
            } else {
                self.fail(ErrorKind.DataCorrupted, "TOML: expected , or ]")
                return null
            }
        }
        return null
    }

    JsonValue? parseInlineTable(Int depth) {
        self.advance()
        JsonObject object = new JsonObject()
        while true {
            self.skipBlank()
            if self.atEnd() {
                self.fail(ErrorKind.DataCorrupted, "TOML: unterminated inline table")
                return null
            }
            if self.peek() == "}" {
                self.advance()
                return new JsonValue(JsonKind.Object, false, null, null, null, object)
            }
            List<String> parts = self.parseKeyPath()
            if parts.length() == 0 { return null }
            self.skipInline()
            if self.peek() != "=" {
                self.fail(ErrorKind.DataCorrupted, "TOML: expected = in inline table")
                return null
            }
            self.advance()
            self.skipInline()
            JsonValue? value = self.parseValue(depth + 1)
            if value == null { return null }
            JsonValue actualValue = value as JsonValue
            JsonObject table = object
            Int index = 0
            while index < parts.length() - 1 {
                String segment = parts.get(index)
                JsonValue? existing = table.getOrNull(segment)
                if existing == null {
                    JsonObject created = new JsonObject()
                    table.set(segment, new JsonValue(JsonKind.Object, false, null, null, null, created))
                    table = created
                } else {
                    JsonValue current = existing as JsonValue
                    if !current.isObject() {
                        self.fail(ErrorKind.DataCorrupted, "TOML: inline table key conflict")
                        return null
                    }
                    table = current.asObject() as JsonObject
                }
                index = index + 1
            }
            String last = parts.get(parts.length() - 1)
            if table.has(last) {
                self.fail(ErrorKind.DataCorrupted, "TOML: duplicate inline table key")
                return null
            }
            table.set(last, value as JsonValue)
            self.skipBlank()
            if self.peek() == "," {
                self.advance()
            } else if self.peek() == "}" {
                self.advance()
                return new JsonValue(JsonKind.Object, false, null, null, null, object)
            } else {
                self.fail(ErrorKind.DataCorrupted, "TOML: expected , or }")
                return null
            }
        }
        return null
    }

    JsonValue? parseScalar() {
        Int start = self._pos
        while !self.atEnd() {
            String c = self.peek()
            if c == " " || c == "\t" || c == "\r" || c == "\n" || c == "," || c == "]" || c == "}" || c == "#" {
                break
            }
            self.advance()
        }
        if self._pos == start {
            self.fail(ErrorKind.DataCorrupted, "TOML: expected value")
            return null
        }
        String token = self._text.substring(start, self._pos - start)
        String lower = token.toLower()
        if lower == "inf" || lower == "nan" || lower == "+inf" || lower == "-inf" ||
           lower == "+nan" || lower == "-nan" {
            self.fail(ErrorKind.Unsupported, "TOML: inf/nan are not supported")
            return null
        }
        // 日期/时间：形如 1979-05-27 / 07:32:00 / 1979-05-27T07:32:00Z
        Bool hasColon = token.indexOf(":") >= 0
        Bool dateLike = token.length() >= 8 && token.substring(4, 1) == "-"
        if hasColon || dateLike || token.indexOf("T") >= 0 && token.length() > 10 {
            self.fail(ErrorKind.Unsupported, "TOML: date/time values are not supported")
            return null
        }
        if token.length() > 2 && token.substring(0, 2).toLower() == "0x" {
            String? decimal = tomlRadixToDecimal(token.substring(2, token.length() - 2).replace("_", ""), 16)
            if decimal == null {
                self.fail(ErrorKind.DataCorrupted, "TOML: invalid hex integer")
                return null
            }
            return new JsonValue(JsonKind.Number, false, new JsonNumber(decimal as String), null, null, null)
        }
        if token.length() > 2 && token.substring(0, 2).toLower() == "0o" {
            String? decimal = tomlRadixToDecimal(token.substring(2, token.length() - 2).replace("_", ""), 8)
            if decimal == null {
                self.fail(ErrorKind.DataCorrupted, "TOML: invalid octal integer")
                return null
            }
            return new JsonValue(JsonKind.Number, false, new JsonNumber(decimal as String), null, null, null)
        }
        if token.length() > 2 && token.substring(0, 2).toLower() == "0b" {
            String? decimal = tomlRadixToDecimal(token.substring(2, token.length() - 2).replace("_", ""), 2)
            if decimal == null {
                self.fail(ErrorKind.DataCorrupted, "TOML: invalid binary integer")
                return null
            }
            return new JsonValue(JsonKind.Number, false, new JsonNumber(decimal as String), null, null, null)
        }
        String cleaned = token.replace("_", "")
        Bool isFloat = cleaned.indexOf(".") >= 0 || cleaned.indexOf("e") >= 0 || cleaned.indexOf("E") >= 0
        if isFloat {
            String normalized = cleaned
            if normalized.substring(0, 1) == "+" {
                normalized = normalized.substring(1, normalized.length() - 1)
            }
            if !self.validFloat(normalized) {
                self.fail(ErrorKind.DataCorrupted, "TOML: invalid float")
                return null
            }
            return new JsonValue(JsonKind.Number, false, new JsonNumber(normalized), null, null, null)
        }
        Bool negative = false
        String digits = cleaned
        if digits.substring(0, 1) == "+" {
            digits = digits.substring(1, digits.length() - 1)
        } else if digits.substring(0, 1) == "-" {
            negative = true
            digits = digits.substring(1, digits.length() - 1)
        }
        if digits.length() == 0 {
            self.fail(ErrorKind.DataCorrupted, "TOML: invalid integer")
            return null
        }
        if digits.length() > 1 && digits.substring(0, 1) == "0" {
            self.fail(ErrorKind.DataCorrupted, "TOML: leading zero in integer")
            return null
        }
        Long? value = tomlDigitsToLong(digits, negative)
        if value == null {
            self.fail(ErrorKind.DataCorrupted, "TOML: integer out of range")
            return null
        }
        return new JsonValue(JsonKind.Number, false, new JsonNumber(str(value as Long)), null, null, null)
    }

    Bool validFloat(String text) {
        if text.length() == 0 { return false }
        Int index = 0
        if text.substring(0, 1) == "-" { index = 1 }
        if index >= text.length() { return false }
        Int digitsBefore = 0
        while index < text.length() {
            Int code = text.get(index)
            if code >= 48 && code <= 57 {
                digitsBefore = digitsBefore + 1
                index = index + 1
            } else {
                break
            }
        }
        if digitsBefore == 0 { return false }
        if index < text.length() && text.substring(index, 1) == "." {
            index = index + 1
            Int digitsAfter = 0
            while index < text.length() {
                Int code = text.get(index)
                if code >= 48 && code <= 57 {
                    digitsAfter = digitsAfter + 1
                    index = index + 1
                } else {
                    break
                }
            }
            if digitsAfter == 0 { return false }
        }
        if index < text.length() && (text.substring(index, 1) == "e" || text.substring(index, 1) == "E") {
            index = index + 1
            if index < text.length() && (text.substring(index, 1) == "+" || text.substring(index, 1) == "-") {
                index = index + 1
            }
            Int expDigits = 0
            while index < text.length() {
                Int code = text.get(index)
                if code >= 48 && code <= 57 {
                    expDigits = expDigits + 1
                    index = index + 1
                } else {
                    break
                }
            }
            if expDigits == 0 { return false }
        }
        return index == text.length()
    }
}

// ---------- writer ----------
class TomlWriter {
    final TomlOptions _options
    List<String> _lines
    Long _bytes
    Bool _failed
    ErrorKind _kind
    String _message
    List<String> _active

    TomlWriter(TomlOptions options) {
        self._options = options
        self._lines = []
        self._bytes = 0 as Long
        self._failed = false
        self._kind = ErrorKind.InvalidArgument
        self._message = ""
        self._active = []
    }

    Bool fail(ErrorKind kind, String message) {
        if !self._failed {
            self._failed = true
            self._kind = kind
            self._message = message
        }
        return false
    }

    Void line(String text) {
        if self._failed { return }
        Long size = (text.length() as Long) + (1 as Long)
        if self._bytes + size > self._options.getMaxBytes() {
            self.fail(ErrorKind.InvalidArgument, "TOML: output exceeds maxBytes")
            return
        }
        self._bytes = self._bytes + size
        self._lines.push(text)
    }

    String keyText(String key) {
        if key.length() == 0 { return "" }
        Bool bare = true
        Int index = 0
        while index < key.length() {
            if !tomlBareKeyChar(key.get(index)) { bare = false }
            index = index + 1
        }
        if bare { return key }
        return self.quotedString(key)
    }

    String pathText(List<String> path) {
        String out = ""
        Int index = 0
        while index < path.length() {
            if index > 0 { out = out + "." }
            out = out + self.keyText(path.get(index))
            index = index + 1
        }
        return out
    }

    String quotedString(String text) {
        String digits = tomlHexDigits()
        String out = "\""
        Int index = 0
        while index < text.length() {
            Int code = text.get(index)
            if code == 34 { out = out + "\\\"" }
            else if code == 92 { out = out + "\\\\" }
            else if code == 8 { out = out + "\\b" }
            else if code == 9 { out = out + "\\t" }
            else if code == 10 { out = out + "\\n" }
            else if code == 12 { out = out + "\\f" }
            else if code == 13 { out = out + "\\r" }
            else if code < 32 || code == 127 {
                out = out + "\\u00" + digits.substring(code / 16, 1) + digits.substring(code % 16, 1)
            } else {
                out = out + text.substring(index, 1)
            }
            index = index + 1
        }
        return out + "\""
    }

    String valueInline(JsonValue value, Int depth) {
        if self._failed { return "" }
        if depth > self._options.getMaxDepth() {
            self.fail(ErrorKind.InvalidArgument, "TOML: maxDepth exceeded")
            return ""
        }
        if value == null || value.isNull() {
            self.fail(ErrorKind.Unsupported, "TOML: null is not supported")
            return ""
        }
        if value.isBool() {
            if value.asBool() as Bool { return "true" }
            return "false"
        }
        if value.isString() {
            return self.quotedString(value.asString() as String)
        }
        if value.isNumber() {
            JsonNumber number = value.asNumber() as JsonNumber
            String raw = number.raw()
            if tomlIsIntegerText(raw) {
                Bool negative = raw.substring(0, 1) == "-"
                String digits = raw
                if negative { digits = raw.substring(1, raw.length() - 1) }
                if tomlDigitsToLong(digits, negative) == null {
                    self.fail(ErrorKind.InvalidArgument, "TOML: integer out of range")
                    return ""
                }
            }
            return raw
        }
        if value.isArray() {
            JsonArray array = value.asArray() as JsonArray
            String out = "["
            Int index = 0
            while index < array.length() {
                if index > 0 { out = out + ", " }
                out = out + self.valueInline(array.get(index), depth + 1)
                index = index + 1
            }
            return out + "]"
        }
        JsonObject object = value.asObject() as JsonObject
        String out = "{ "
        List<String> keys = object.keys()
        Int index = 0
        while index < keys.length() {
            if index > 0 { out = out + ", " }
            out = out + self.keyText(keys.get(index)) + " = " +
                self.valueInline(object.getOr(keys.get(index), Json.nullValue()), depth + 1)
            index = index + 1
        }
        if keys.length() == 0 { return "{}" }
        return out + " }"
    }

    Bool isObjectArray(JsonValue value) {
        if !value.isArray() { return false }
        JsonArray array = value.asArray() as JsonArray
        if array.length() == 0 { return false }
        Int index = 0
        while index < array.length() {
            if !array.get(index).isObject() { return false }
            index = index + 1
        }
        return true
    }

    Void writeTable(JsonObject object, List<String> path) {
        if self._failed { return }
        if path.length() + 1 > self._options.getMaxDepth() {
            self.fail(ErrorKind.InvalidArgument, "TOML: maxDepth exceeded")
            return
        }
        List<String> keys = object.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            JsonValue value = object.getOr(key, Json.nullValue())
            if value.isObject() || self.isObjectArray(value) {
                index = index + 1
                continue
            }
            self.line(self.keyText(key) + " = " + self.valueInline(value, path.length() + 1))
            index = index + 1
        }
        index = 0
        while index < keys.length() {
            String key = keys.get(index)
            JsonValue value = object.getOr(key, Json.nullValue())
            List<String> child = path.copy()
            child.push(key)
            if value.isObject() {
                self.line("[" + self.pathText(child) + "]")
                self.writeTable(value.asObject() as JsonObject, child)
            } else if self.isObjectArray(value) {
                JsonArray array = value.asArray() as JsonArray
                Int element = 0
                while element < array.length() {
                    self.line("[[" + self.pathText(child) + "]]")
                    self.writeTable(array.get(element).asObject() as JsonObject, child)
                    element = element + 1
                }
            }
            index = index + 1
        }
    }
}

// ---------- public entry ----------
class Toml {
    private Toml() { }

    static Result<JsonValue, Error> parse(String text) {
        return Toml.parseWithOptions(text, new TomlOptions())
    }

    static Result<JsonValue, Error> parseWithOptions(String text, TomlOptions options) {
        if text == null || options == null { throw "Toml.parse: null argument" }
        TomlParser parser = new TomlParser(text, options.copy())
        return parser.parseDocument()
    }

    static Result<String, Error> stringify(JsonValue value) {
        return Toml.stringifyWithOptions(value, new TomlOptions())
    }

    static Result<String, Error> stringifyWithOptions(JsonValue value, TomlOptions options) {
        if value == null || options == null { throw "Toml.stringify: null argument" }
        if !value.isObject() {
            return Err(tomlError(ErrorKind.InvalidArgument, "TOML root must be an object"))
        }
        TomlWriter writer = new TomlWriter(options.copy())
        List<String> rootPath = []
        writer.writeTable(value.asObject() as JsonObject, rootPath)
        if writer._failed {
            return Err(tomlError(writer._kind, writer._message))
        }
        if writer._lines.length() == 0 { return Ok("") }
        return Ok(writer._lines.join("\n") + "\n")
    }
}
