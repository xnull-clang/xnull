// xdk.yaml —— YAML 子集解析/生成 + 属性源（M18.5）
//
// 值树复用 xdk.codec.JsonValue。支持块映射/序列、流式集合、引号/转义、
// 多文档、锚点/别名/合并键、profile 提取、属性扁平化。
// 不支持完整 YAML 1.1/1.2、复杂键、自定义标签、块标量、流式 Reader。
// 稳定性：preview。合同见 docs/design/utils/yaml/。
package xdk.yaml
import xdk.errors
import xdk.codec
import xdk.text

// ---------- YamlVersion ----------
enum YamlVersion {
    Yaml11,
    Yaml12,
}

String yamlVersionName(YamlVersion version) {
    if version == YamlVersion.Yaml11 { return "1.1" }
    return "1.2"
}

// ---------- YamlOptions ----------
class YamlOptions {
    YamlVersion _version
    Int _maxDepth
    Long _maxBytes
    Int _maxDocuments
    Int _maxAliases
    Bool _allowDuplicateKeys
    Bool _allowAnchors
    Bool _allowMergeKeys
    Bool _allowStandardTags
    String _profileKey

    YamlOptions() {
        self._version = YamlVersion.Yaml12
        self._maxDepth = 64
        self._maxBytes = 1048576 as Long
        self._maxDocuments = 16
        self._maxAliases = 64
        self._allowDuplicateKeys = true
        self._allowAnchors = true
        self._allowMergeKeys = true
        self._allowStandardTags = false
        self._profileKey = ""
    }

    YamlOptions version(YamlVersion value) {
        self._version = value
        return self
    }

    YamlOptions maxDepth(Int value) {
        if value <= 0 { throw "YamlOptions.maxDepth: must be positive" }
        self._maxDepth = value
        return self
    }

    YamlOptions maxBytes(Long value) {
        if value <= 0 { throw "YamlOptions.maxBytes: must be positive" }
        self._maxBytes = value
        return self
    }

    YamlOptions maxDocuments(Int value) {
        if value <= 0 { throw "YamlOptions.maxDocuments: must be positive" }
        self._maxDocuments = value
        return self
    }

    YamlOptions maxAliases(Int value) {
        if value < 0 { throw "YamlOptions.maxAliases: must be non-negative" }
        self._maxAliases = value
        return self
    }

    YamlOptions allowDuplicateKeys(Bool value) {
        self._allowDuplicateKeys = value
        return self
    }

    YamlOptions allowAnchors(Bool value) {
        self._allowAnchors = value
        return self
    }

    YamlOptions allowMergeKeys(Bool value) {
        self._allowMergeKeys = value
        return self
    }

    YamlOptions allowStandardTags(Bool value) {
        self._allowStandardTags = value
        return self
    }

    YamlOptions profileKey(String value) {
        if value == null { throw "YamlOptions.profileKey: null" }
        self._profileKey = value
        return self
    }

    YamlVersion getVersion() { return self._version }
    Int getMaxDepth() { return self._maxDepth }
    Long getMaxBytes() { return self._maxBytes }
    Int getMaxDocuments() { return self._maxDocuments }
    Int getMaxAliases() { return self._maxAliases }
    Bool isAllowDuplicateKeys() { return self._allowDuplicateKeys }
    Bool isAllowAnchors() { return self._allowAnchors }
    Bool isAllowMergeKeys() { return self._allowMergeKeys }
    Bool isAllowStandardTags() { return self._allowStandardTags }
    String getProfileKey() { return self._profileKey }

    YamlOptions copy() {
        YamlOptions out = new YamlOptions()
        out._version = self._version
        out._maxDepth = self._maxDepth
        out._maxBytes = self._maxBytes
        out._maxDocuments = self._maxDocuments
        out._maxAliases = self._maxAliases
        out._allowDuplicateKeys = self._allowDuplicateKeys
        out._allowAnchors = self._allowAnchors
        out._allowMergeKeys = self._allowMergeKeys
        out._allowStandardTags = self._allowStandardTags
        out._profileKey = self._profileKey
        return out
    }
}

// ---------- helpers ----------
static Error yamlError(ErrorKind kind, String message) {
    return new BasicError(kind, message)
}

static Bool yamlListHas(List<String> values, String value) {
    Int index = 0
    while index < values.length() {
        if values.get(index) == value { return true }
        index = index + 1
    }
    return false
}

static Bool yamlNameStart(Int code) {
    if code >= 65 && code <= 90 { return true }
    if code >= 97 && code <= 122 { return true }
    if code == 95 || code == 36 { return true }
    return code >= 128
}

static Bool yamlNameChar(Int code) {
    if yamlNameStart(code) { return true }
    if code >= 48 && code <= 57 { return true }
    return code == 45 || code == 46
}

static String yamlEscapeDouble(String text) {
    String out = ""
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
        else if code < 32 {
            String hex = "0123456789abcdef"
            out = out + "\\u00" + hex.substring(code / 16, 1) + hex.substring(code % 16, 1)
        } else {
            out = out + text.substring(index, 1)
        }
        index = index + 1
    }
    return out
}

static Bool yamlPlainSafe(String text) {
    if text.length() == 0 { return false }
    if text.trim() != text { return false }
    String lower = text.toLower()
    if lower == "null" || lower == "true" || lower == "false" || lower == "~" ||
       lower == "yes" || lower == "no" || lower == "on" || lower == "off" {
        return false
    }
    if text.substring(0, 1) == "-" || text.substring(0, 1) == "?" || text.substring(0, 1) == ":" {
        if text.length() == 1 || text.substring(1, 1) == " " { return false }
    }
    Int lead = text.get(0)
    if lead >= 48 && lead <= 57 { return false }
    if (lead == 43 || lead == 45) && text.length() > 1 {
        Int second = text.get(1)
        if second >= 48 && second <= 57 { return false }
    }
    Int index = 0
    while index < text.length() {
        String c = text.substring(index, 1)
        if c == "\n" || c == "\r" || c == "\t" { return false }
        if c == "#" && (index == 0 || text.substring(index - 1, 1) == " ") { return false }
        if c == ":" || c == "{" || c == "}" || c == "[" || c == "]" || c == "," || c == "&" ||
           c == "*" || c == "!" || c == "|" || c == ">" || c == "'" || c == "\"" ||
           c == "%" || c == "@" || c == "`" {
            return false
        }
        if c == ":" && index + 1 < text.length() && text.substring(index + 1, 1) == " " {
            return false
        }
        index = index + 1
    }
    return true
}

static String yamlQuote(String text) {
    return "\"" + yamlEscapeDouble(text) + "\""
}

static String yamlKey(String key) {
    if yamlPlainSafe(key) { return key }
    return yamlQuote(key)
}

// ---------- 文档/属性源 ----------
class YamlDocument {
    final Int _index
    final JsonValue _value
    final List<String> _profiles

    YamlDocument(Int documentIndex, JsonValue value, List<String> profiles) {
        if documentIndex < 0 { throw "YamlDocument: negative index" }
        if value == null { throw "YamlDocument: null value" }
        if profiles == null { throw "YamlDocument: null profiles" }
        self._index = documentIndex
        self._value = value
        self._profiles = profiles.copy()
        Int index = 0
        while index < self._profiles.length() {
            if self._profiles.get(index) == "" { throw "YamlDocument: empty profile" }
            index = index + 1
        }
    }

    Int index() { return self._index }
    JsonValue value() { return self._value }
    List<String> profiles() { return self._profiles.copy() }

    Bool isActive(List<String> activeProfiles) {
        if activeProfiles == null { throw "YamlDocument.isActive: null profiles" }
        if self._profiles.length() == 0 { return true }
        Int index = 0
        while index < self._profiles.length() {
            String expression = self._profiles.get(index)
            if expression.substring(0, 1) == "!" {
                String name = expression.substring(1, expression.length() - 1)
                if !yamlListHas(activeProfiles, name) { return true }
            } else if yamlListHas(activeProfiles, expression) {
                return true
            }
            index = index + 1
        }
        return false
    }

    String describe() {
        return "document[" + str(self._index) + "](profiles=" + str(self._profiles.length()) + ")"
    }
}

class YamlPropertySource {
    final String _name
    final Int _documentIndex
    final List<String> _profiles
    final Map<String, String> _properties

    YamlPropertySource(String name, Int documentIndex, List<String> profiles, Map<String, String> properties) {
        if name == null || name.length() == 0 { throw "YamlPropertySource: empty name" }
        if documentIndex < 0 { throw "YamlPropertySource: negative index" }
        if profiles == null || properties == null { throw "YamlPropertySource: null argument" }
        self._name = name
        self._documentIndex = documentIndex
        self._profiles = profiles.copy()
        Map<String, String> copied = [:]
        self._properties = copied
        List<String> keys = properties.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            String value = properties.getOr(key, "")
            self._properties.put(key, value)
            index = index + 1
        }
    }

    String name() { return self._name }
    Int documentIndex() { return self._documentIndex }
    List<String> profiles() { return self._profiles.copy() }

    Map<String, String> properties() {
        Map<String, String> result = [:]
        List<String> keys = self._properties.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            result.put(key, self._properties.getOr(key, ""))
            index = index + 1
        }
        return result
    }

    String? getOrNull(String key) {
        if key == null { throw "YamlPropertySource.getOrNull: null key" }
        if !self._properties.has(key) { return null }
        return self._properties.getOr(key, "")
    }

    String getOr(String key, String fallback) {
        if key == null { throw "YamlPropertySource.getOr: null key" }
        if fallback == null { throw "YamlPropertySource.getOr: null fallback" }
        String? value = self.getOrNull(key)
        if value == null { return fallback }
        return value as String
    }

    Bool contains(String key) {
        if key == null { throw "YamlPropertySource.contains: null key" }
        return self._properties.has(key)
    }

    List<String> keys() { return self._properties.keys() }

    Bool isActiveFor(List<String> activeProfiles) {
        if activeProfiles == null { throw "YamlPropertySource.isActiveFor: null profiles" }
        if self._profiles.length() == 0 { return true }
        Int index = 0
        while index < self._profiles.length() {
            String expression = self._profiles.get(index)
            if expression.substring(0, 1) == "!" {
                String name = expression.substring(1, expression.length() - 1)
                if !yamlListHas(activeProfiles, name) { return true }
            } else if yamlListHas(activeProfiles, expression) {
                return true
            }
            index = index + 1
        }
        return false
    }

    String describe() {
        return self._name + "#" + str(self._documentIndex) +
            "(profiles=" + str(self._profiles.length()) + ",keys=" + str(self._properties.length()) + ")"
    }
}

// ---------- 解析内部类型 ----------
class YamlLine {
    final Int indent
    final String content
    YamlLine(Int indentation, String text) {
        self.indent = indentation
        self.content = text
    }
}

class YamlParsed {
    final JsonValue value
    final Int next
    final Bool ok
    YamlParsed(JsonValue parsedValue, Int nextIndex, Bool success) {
        self.value = parsedValue
        self.next = nextIndex
        self.ok = success
    }
}

class YamlFlowResult {
    final JsonValue value
    final Int next
    final Bool ok
    YamlFlowResult(JsonValue parsedValue, Int nextIndex, Bool success) {
        self.value = parsedValue
        self.next = nextIndex
        self.ok = success
    }
}

// ---------- 解析器 ----------
class YamlParser {
    final YamlOptions _options
    List<YamlLine> _lines
    Bool _failed
    ErrorKind _kind
    String _message
    Map<String, JsonValue> _anchors
    Int _aliases
    Int _lastPairNext

    YamlParser(YamlOptions options) {
        self._options = options
        self._lines = []
        self._failed = false
        self._kind = ErrorKind.DataCorrupted
        self._message = ""
        Map<String, JsonValue> anchors = [:]
        self._anchors = anchors
        self._aliases = 0
        self._lastPairNext = 0
    }

    Bool fail(ErrorKind kind, String message) {
        if !self._failed {
            self._failed = true
            self._kind = kind
            self._message = message
        }
        return false
    }

    Bool depthOk(Int depth) {
        if depth > self._options.getMaxDepth() {
            return self.fail(ErrorKind.InvalidArgument, "Yaml: maxDepth exceeded")
        }
        return true
    }

    String stripComment(String text) {
        Bool single = false
        Bool doubleQuote = false
        Int index = 0
        while index < text.length() {
            String c = text.substring(index, 1)
            if c == "'" && !doubleQuote {
                single = !single
            } else if c == "\"" && !single {
                Bool escaped = index > 0 && text.substring(index - 1, 1) == "\\"
                if !escaped { doubleQuote = !doubleQuote }
            } else if c == "#" && !single && !doubleQuote {
                if index == 0 || text.substring(index - 1, 1) == " " || text.substring(index - 1, 1) == "\t" {
                    return text.substring(0, index)
                }
            }
            index = index + 1
        }
        return text
    }

    List<YamlLine> prepare(String text) {
        List<YamlLine> result = []
        List<String> raw = text.split("\n")
        Int lineNumber = 0
        while lineNumber < raw.length() {
            String current = raw.get(lineNumber)
            if current.length() > 0 && current.substring(current.length() - 1, 1) == "\r" {
                current = current.substring(0, current.length() - 1)
            }
            Int spaces = 0
            while spaces < current.length() && current.substring(spaces, 1) == " " {
                spaces = spaces + 1
            }
            if spaces < current.length() && current.substring(spaces, 1) == "\t" {
                self.fail(ErrorKind.DataCorrupted, "Yaml: tab indentation")
                return result
            }
            String content = self.stripComment(current.substring(spaces, current.length() - spaces)).trim()
            if content.length() > 0 {
                result.push(new YamlLine(spaces, content))
            }
            lineNumber = lineNumber + 1
        }
        return result
    }

    Int findColon(String text) {
        Bool single = false
        Bool doubleQuote = false
        Int depth = 0
        Int index = 0
        while index < text.length() {
            String c = text.substring(index, 1)
            if c == "'" && !doubleQuote { single = !single }
            else if c == "\"" && !single {
                Bool escaped = index > 0 && text.substring(index - 1, 1) == "\\"
                if !escaped { doubleQuote = !doubleQuote }
            }
            if !single && !doubleQuote {
                if c == "[" || c == "{" { depth = depth + 1 }
                if c == "]" || c == "}" { depth = depth - 1 }
                if c == ":" && depth == 0 {
                    if index + 1 >= text.length() || text.substring(index + 1, 1) == " " {
                        return index
                    }
                }
            }
            index = index + 1
        }
        return -1
    }

    Bool isSequenceStart(YamlLine line) {
        if line.content == "-" { return true }
        return line.content.length() > 1 && line.content.substring(0, 2) == "- "
    }

    JsonValue parseDocumentLines(List<YamlLine> lines) {
        self._lines = lines
        self._failed = false
        Map<String, JsonValue> anchors = [:]
        self._anchors = anchors
        self._aliases = 0
        if lines.length() == 0 { return Json.nullValue() }
        YamlParsed parsed = self.parseBlock(0, lines.get(0).indent, 1)
        if !parsed.ok { return Json.nullValue() }
        if parsed.next != lines.length() {
            self.fail(ErrorKind.DataCorrupted, "Yaml: unexpected indentation or trailing content")
            return Json.nullValue()
        }
        return parsed.value
    }

    YamlParsed parseBlock(Int index, Int indent, Int depth) {
        if !self.depthOk(depth) { return new YamlParsed(Json.nullValue(), index, false) }
        if index >= self._lines.length() { return new YamlParsed(Json.nullValue(), index, false) }
        YamlLine line = self._lines.get(index)
        if line.indent != indent {
            self.fail(ErrorKind.DataCorrupted, "Yaml: inconsistent indentation")
            return new YamlParsed(Json.nullValue(), index, false)
        }
        if self.isSequenceStart(line) { return self.parseSequence(index, indent, depth) }
        if self.findColon(line.content) >= 0 { return self.parseMapping(index, indent, depth) }
        return self.parseNodeText(line.content, index + 1, indent, depth)
    }

    YamlParsed parseMapping(Int index, Int indent, Int depth) {
        JsonObject object = new JsonObject()
        Int cursor = index
        while cursor < self._lines.length() {
            YamlLine line = self._lines.get(cursor)
            if line.indent != indent { break }
            if self.isSequenceStart(line) {
                self.fail(ErrorKind.DataCorrupted, "Yaml: sequence item in mapping")
                return new YamlParsed(Json.nullValue(), cursor, false)
            }
            Int colon = self.findColon(line.content)
            if colon < 0 {
                self.fail(ErrorKind.DataCorrupted, "Yaml: expected mapping key")
                return new YamlParsed(Json.nullValue(), cursor, false)
            }
            String keyText = line.content.substring(0, colon).trim()
            String key = self.parseKeyText(keyText)
            if self._failed { return new YamlParsed(Json.nullValue(), cursor, false) }
            if key.length() == 0 {
                self.fail(ErrorKind.Unsupported, "Yaml: complex or empty keys are not supported")
                return new YamlParsed(Json.nullValue(), cursor, false)
            }
            String rest = line.content.substring(colon + 1, line.content.length() - colon - 1).trim()
            YamlParsed value = self.parseNodeText(rest, cursor + 1, indent, depth + 1)
            if !value.ok { return value }
            if key == "<<" {
                if !self._options.isAllowMergeKeys() {
                    self.fail(ErrorKind.Unsupported, "Yaml: merge keys are not allowed")
                    return new YamlParsed(Json.nullValue(), cursor, false)
                }
                if !self.mergeInto(object, value.value) {
                    return new YamlParsed(Json.nullValue(), cursor, false)
                }
            } else {
                if object.has(key) && !self._options.isAllowDuplicateKeys() {
                    self.fail(ErrorKind.DataCorrupted, "Yaml: duplicate key")
                    return new YamlParsed(Json.nullValue(), cursor, false)
                }
                object.set(key, value.value)
            }
            cursor = value.next
        }
        return new YamlParsed(new JsonValue(JsonKind.Object, false, null, null, null, object), cursor, true)
    }

    YamlParsed parseSequence(Int index, Int indent, Int depth) {
        JsonArray array = new JsonArray()
        Int cursor = index
        while cursor < self._lines.length() {
            YamlLine line = self._lines.get(cursor)
            if line.indent != indent || !self.isSequenceStart(line) { break }
            String rest = ""
            if line.content.length() > 1 {
                rest = line.content.substring(2, line.content.length() - 2).trim()
            }
            if rest.length() == 0 {
                if cursor + 1 < self._lines.length() && self._lines.get(cursor + 1).indent > indent {
                    YamlParsed nested = self.parseBlock(cursor + 1, self._lines.get(cursor + 1).indent, depth + 1)
                    if !nested.ok { return nested }
                    array.add(nested.value)
                    cursor = nested.next
                } else {
                    array.add(Json.nullValue())
                    cursor = cursor + 1
                }
                continue
            }
            if self.findColon(rest) >= 0 {
                YamlParsed item = self.parseMappingItem(rest, cursor + 1, indent + 2, depth + 1)
                if !item.ok { return item }
                array.add(item.value)
                cursor = item.next
                continue
            }
            YamlParsed item = self.parseNodeText(rest, cursor + 1, indent, depth + 1)
            if !item.ok { return item }
            array.add(item.value)
            cursor = item.next
        }
        return new YamlParsed(new JsonValue(JsonKind.Array, false, null, null, array, null), cursor, true)
    }

    YamlParsed parseMappingItem(String firstPair, Int index, Int itemIndent, Int depth) {
        JsonObject object = new JsonObject()
        if !self.applyPair(object, firstPair, index, itemIndent, depth) {
            return new YamlParsed(Json.nullValue(), index, false)
        }
        Int cursor = self._lastPairNext
        Int childIndent = itemIndent
        if cursor < self._lines.length() && self._lines.get(cursor).indent > itemIndent - 1 {
            childIndent = self._lines.get(cursor).indent
        }
        while cursor < self._lines.length() {
            YamlLine line = self._lines.get(cursor)
            if line.indent != childIndent || self.isSequenceStart(line) { break }
            Int colon = self.findColon(line.content)
            if colon < 0 { break }
            if !self.applyPair(object, line.content, cursor + 1, childIndent, depth) {
                return new YamlParsed(Json.nullValue(), cursor, false)
            }
            cursor = self._lastPairNext
        }
        return new YamlParsed(new JsonValue(JsonKind.Object, false, null, null, null, object), cursor, true)
    }

    Bool applyPair(JsonObject object, String pairText, Int index, Int indent, Int depth) {
        Int colon = self.findColon(pairText)
        if colon < 0 { return self.fail(ErrorKind.DataCorrupted, "Yaml: expected mapping pair") }
        String keyText = pairText.substring(0, colon).trim()
        String key = self.parseKeyText(keyText)
        if self._failed { return false }
        if key.length() == 0 {
            return self.fail(ErrorKind.Unsupported, "Yaml: complex or empty keys are not supported")
        }
        String rest = pairText.substring(colon + 1, pairText.length() - colon - 1).trim()
        YamlParsed value = self.parseNodeText(rest, index, indent, depth + 1)
        if !value.ok { return false }
        if key == "<<" {
            if !self._options.isAllowMergeKeys() {
                return self.fail(ErrorKind.Unsupported, "Yaml: merge keys are not allowed")
            }
            if !self.mergeInto(object, value.value) { return false }
        } else {
            if object.has(key) && !self._options.isAllowDuplicateKeys() {
                return self.fail(ErrorKind.DataCorrupted, "Yaml: duplicate key")
            }
            object.set(key, value.value)
        }
        self._lastPairNext = value.next
        return true
    }

    YamlParsed parseNodeText(String text, Int index, Int parentIndent, Int depth) {
        if !self.depthOk(depth) { return new YamlParsed(Json.nullValue(), index, false) }
        String rest = text
        String anchor = ""
        List<String> tags = []
        while true {
            if rest.length() == 0 { break }
            if rest.substring(0, 1) == "!" {
                Int space = rest.indexOf(" ")
                String tag = rest
                if space >= 0 { tag = rest.substring(0, space) }
                Bool doubleTag = tag.length() >= 2 && tag.substring(0, 2) == "!!"
                if !doubleTag {
                    self.fail(ErrorKind.Unsupported, "Yaml: custom tags are not supported")
                    return new YamlParsed(Json.nullValue(), index, false)
                }
                if !self._options.isAllowStandardTags() {
                    self.fail(ErrorKind.Unsupported, "Yaml: standard tags are not allowed")
                    return new YamlParsed(Json.nullValue(), index, false)
                }
                tags.push(tag)
                if space < 0 { rest = "" } else { rest = rest.substring(space + 1, rest.length() - space - 1).trim() }
            } else if rest.substring(0, 1) == "&" {
                if !self._options.isAllowAnchors() {
                    self.fail(ErrorKind.Unsupported, "Yaml: anchors are not allowed")
                    return new YamlParsed(Json.nullValue(), index, false)
                }
                Int space = rest.indexOf(" ")
                if space < 0 {
                    anchor = rest.substring(1, rest.length() - 1)
                    rest = ""
                } else {
                    anchor = rest.substring(1, space - 1)
                    rest = rest.substring(space + 1, rest.length() - space - 1).trim()
                }
            } else {
                break
            }
        }
        if rest.length() > 0 && rest.substring(0, 1) == "*" {
            if !self._options.isAllowAnchors() {
                self.fail(ErrorKind.Unsupported, "Yaml: aliases are not allowed")
                return new YamlParsed(Json.nullValue(), index, false)
            }
            if self._options.getMaxAliases() == 0 {
                self.fail(ErrorKind.Unsupported, "Yaml: aliases are disabled")
                return new YamlParsed(Json.nullValue(), index, false)
            }
            String name = rest.substring(1, rest.length() - 1)
            if !self._anchors.has(name) {
                self.fail(ErrorKind.DataCorrupted, "Yaml: unknown alias")
                return new YamlParsed(Json.nullValue(), index, false)
            }
            self._aliases = self._aliases + 1
            if self._aliases > self._options.getMaxAliases() {
                self.fail(ErrorKind.InvalidArgument, "Yaml: maxAliases exceeded")
                return new YamlParsed(Json.nullValue(), index, false)
            }
            return new YamlParsed(self._anchors.getOr(name, Json.nullValue()), index, true)
        }
        JsonValue value = Json.nullValue()
        Int next = index
        if rest.length() == 0 {
            if index < self._lines.length() && self._lines.get(index).indent > parentIndent {
                YamlParsed nested = self.parseBlock(index, self._lines.get(index).indent, depth + 1)
                if !nested.ok { return nested }
                value = nested.value
                next = nested.next
            }
        } else {
            YamlFlowResult parsed = self.parseFlowOrScalar(rest, depth + 1)
            if !parsed.ok || self._failed { return new YamlParsed(Json.nullValue(), index, false) }
            value = parsed.value
            next = index
        }
        if anchor.length() > 0 {
            if !yamlNameValid(anchor) {
                self.fail(ErrorKind.DataCorrupted, "Yaml: invalid anchor name")
                return new YamlParsed(Json.nullValue(), index, false)
            }
            self._anchors.put(anchor, value)
        }
        return new YamlParsed(value, next, true)
    }

    String parseKeyText(String text) {
        String trimmed = text.trim()
        if trimmed.length() == 0 { return "" }
        String first = trimmed.substring(0, 1)
        if first == "\"" || first == "'" {
            YamlFlowResult quoted = self.parseQuoted(trimmed, 0)
            if !quoted.ok { return "" }
            if quoted.next != trimmed.length() {
                self.fail(ErrorKind.DataCorrupted, "Yaml: trailing data after quoted key")
                return ""
            }
            String value = quoted.value.asString() as String
            return value
        }
        if first == "?" {
            self.fail(ErrorKind.Unsupported, "Yaml: complex keys are not supported")
            return ""
        }
        return trimmed
    }

    YamlFlowResult parseFlowOrScalar(String text, Int depth) {
        String trimmed = text.trim()
        if trimmed.length() == 0 { return new YamlFlowResult(Json.nullValue(), 0, true) }
        String first = trimmed.substring(0, 1)
        if first == "\"" || first == "'" { return self.parseQuoted(trimmed, 0) }
        if first == "[" || first == "{" {
            return self.parseFlow(trimmed, 0, depth)
        }
        return new YamlFlowResult(self.parseScalarText(trimmed), trimmed.length() - trimmed.length() + text.length(), true)
    }

    YamlFlowResult parseQuoted(String text, Int start) {
        String quote = text.substring(start, 1)
        Int index = start + 1
        String result = ""
        while index < text.length() {
            String c = text.substring(index, 1)
            if c == quote {
                if quote == "'" && index + 1 < text.length() && text.substring(index + 1, 1) == "'" {
                    result = result + "'"
                    index = index + 2
                    continue
                }
                return new YamlFlowResult(new JsonValue(JsonKind.String, false, null, result, null, null), index + 1, true)
            }
            if quote == "\"" && c == "\\" {
                if index + 1 >= text.length() {
                    self.fail(ErrorKind.DataCorrupted, "Yaml: unterminated escape")
                    return new YamlFlowResult(Json.nullValue(), index, false)
                }
                String escaped = text.substring(index + 1, 1)
                if escaped == "n" { result = result + "\n"; index = index + 2 }
                else if escaped == "t" { result = result + "\t"; index = index + 2 }
                else if escaped == "r" { result = result + "\r"; index = index + 2 }
                else if escaped == "\"" { result = result + "\""; index = index + 2 }
                else if escaped == "\\" { result = result + "\\"; index = index + 2 }
                else if escaped == "u" {
                    if index + 6 > text.length() {
                        self.fail(ErrorKind.DataCorrupted, "Yaml: invalid unicode escape")
                        return new YamlFlowResult(Json.nullValue(), index, false)
                    }
                    Int code = 0
                    Int probe = 0
                    while probe < 4 {
                        Int digit = yamlHexValue(text.substring(index + 2 + probe, 1))
                        if digit < 0 {
                            self.fail(ErrorKind.DataCorrupted, "Yaml: invalid unicode escape")
                            return new YamlFlowResult(Json.nullValue(), index, false)
                        }
                        code = code * 16 + digit
                        probe = probe + 1
                    }
                    result = result + fromCodePoint(code)
                    index = index + 6
                } else {
                    self.fail(ErrorKind.DataCorrupted, "Yaml: invalid escape")
                    return new YamlFlowResult(Json.nullValue(), index, false)
                }
                continue
            }
            result = result + c
            index = index + 1
        }
        self.fail(ErrorKind.DataCorrupted, "Yaml: unterminated string")
        return new YamlFlowResult(Json.nullValue(), index, false)
    }

    YamlFlowResult parseFlow(String text, Int start, Int depth) {
        if !self.depthOk(depth) { return new YamlFlowResult(Json.nullValue(), start, false) }
        String first = text.substring(start, 1)
        if first == "[" {
            JsonArray array = new JsonArray()
            Int index = start + 1
            while true {
                index = self.skipSpaces(text, index)
                if index >= text.length() {
                    self.fail(ErrorKind.DataCorrupted, "Yaml: unterminated flow sequence")
                    return new YamlFlowResult(Json.nullValue(), index, false)
                }
                if text.substring(index, 1) == "]" {
                    return new YamlFlowResult(new JsonValue(JsonKind.Array, false, null, null, array, null), index + 1, true)
                }
                YamlFlowResult item = self.parseFlowValue(text, index, depth + 1)
                if !item.ok { return item }
                array.add(item.value)
                index = self.skipSpaces(text, item.next)
                if index < text.length() && text.substring(index, 1) == "," {
                    index = index + 1
                } else if index < text.length() && text.substring(index, 1) == "]" {
                    return new YamlFlowResult(new JsonValue(JsonKind.Array, false, null, null, array, null), index + 1, true)
                } else {
                    self.fail(ErrorKind.DataCorrupted, "Yaml: expected , or ]")
                    return new YamlFlowResult(Json.nullValue(), index, false)
                }
            }
        }
        JsonObject object = new JsonObject()
        Int index = start + 1
        while true {
            index = self.skipSpaces(text, index)
            if index >= text.length() {
                self.fail(ErrorKind.DataCorrupted, "Yaml: unterminated flow mapping")
                return new YamlFlowResult(Json.nullValue(), index, false)
            }
            if text.substring(index, 1) == "}" {
                return new YamlFlowResult(new JsonValue(JsonKind.Object, false, null, null, null, object), index + 1, true)
            }
            String key = ""
            if text.substring(index, 1) == "\"" || text.substring(index, 1) == "'" {
                YamlFlowResult keyResult = self.parseQuoted(text, index)
                if !keyResult.ok { return keyResult }
                key = keyResult.value.asString() as String
                index = keyResult.next
            } else {
                Int colon = self.findColon(text.substring(index, text.length() - index))
                if colon < 0 {
                    self.fail(ErrorKind.DataCorrupted, "Yaml: expected flow mapping key")
                    return new YamlFlowResult(Json.nullValue(), index, false)
                }
                key = text.substring(index, colon).trim()
                index = index + colon
            }
            index = self.skipSpaces(text, index)
            if index >= text.length() || text.substring(index, 1) != ":" {
                self.fail(ErrorKind.DataCorrupted, "Yaml: expected : in flow mapping")
                return new YamlFlowResult(Json.nullValue(), index, false)
            }
            index = self.skipSpaces(text, index + 1)
            YamlFlowResult item = self.parseFlowValue(text, index, depth + 1)
            if !item.ok { return item }
            if object.has(key) && !self._options.isAllowDuplicateKeys() {
                self.fail(ErrorKind.DataCorrupted, "Yaml: duplicate key")
                return new YamlFlowResult(Json.nullValue(), index, false)
            }
            object.set(key, item.value)
            index = self.skipSpaces(text, item.next)
            if index < text.length() && text.substring(index, 1) == "," {
                index = index + 1
            } else if index < text.length() && text.substring(index, 1) == "}" {
                return new YamlFlowResult(new JsonValue(JsonKind.Object, false, null, null, null, object), index + 1, true)
            } else {
                self.fail(ErrorKind.DataCorrupted, "Yaml: expected , or }")
                return new YamlFlowResult(Json.nullValue(), index, false)
            }
        }
    }

    YamlFlowResult parseFlowValue(String text, Int start, Int depth) {
        Int index = self.skipSpaces(text, start)
        if index >= text.length() { return new YamlFlowResult(Json.nullValue(), index, true) }
        String first = text.substring(index, 1)
        if first == "*" || first == "&" || first == "!" {
            self.fail(ErrorKind.Unsupported, "Yaml: aliases/tags in flow collections are not supported")
            return new YamlFlowResult(Json.nullValue(), index, false)
        }
        if first == "[" || first == "{" { return self.parseFlow(text, index, depth) }
        if first == "\"" || first == "'" { return self.parseQuoted(text, index) }
        Int end = index
        while end < text.length() {
            String c = text.substring(end, 1)
            if c == "," || c == "]" || c == "}" { break }
            end = end + 1
        }
        String token = text.substring(index, end - index).trim()
        JsonValue scalar = self.parseScalarText(token)
        if self._failed { return new YamlFlowResult(Json.nullValue(), end, false) }
        return new YamlFlowResult(scalar, end, true)
    }

    Int skipSpaces(String text, Int index) {
        Int cursor = index
        while cursor < text.length() {
            String c = text.substring(cursor, 1)
            if c == " " || c == "\t" { cursor = cursor + 1 } else { return cursor }
        }
        return cursor
    }

    JsonValue parseScalarText(String token) {
        if token.length() == 0 { return Json.nullValue() }
        if token == "null" || token == "~" || token == "Null" || token == "NULL" { return Json.nullValue() }
        String lower = token.toLower()
        if lower == "true" { return Json.bool(true) }
        if lower == "false" { return Json.bool(false) }
        if self._options.getVersion() == YamlVersion.Yaml11 {
            if lower == "yes" || lower == "on" { return Json.bool(true) }
            if lower == "no" || lower == "off" { return Json.bool(false) }
        }
        if lower == "inf" || lower == "+inf" || lower == "-inf" || lower == "nan" || lower == ".nan" {
            self.fail(ErrorKind.Unsupported, "Yaml: inf/nan are not supported")
            return Json.nullValue()
        }
        String? integer = self.parseInteger(token)
        if integer != null {
            return new JsonValue(JsonKind.Number, false, new JsonNumber(integer as String), null, null, null)
        }
        if self.isFloat(token) {
            return new JsonValue(JsonKind.Number, false, new JsonNumber(token), null, null, null)
        }
        return new JsonValue(JsonKind.String, false, null, token, null, null)
    }

    String? parseInteger(String token) {
        String text = token
        Bool negative = false
        if text.substring(0, 1) == "+" { text = text.substring(1, text.length() - 1) }
        else if text.substring(0, 1) == "-" { negative = true; text = text.substring(1, text.length() - 1) }
        if text.length() == 0 { return null }
        if text.length() > 2 && text.substring(0, 2).toLower() == "0x" {
            if negative { return null }
            return yamlRadixToDecimal(text.substring(2, text.length() - 2), 16)
        }
        if text.length() > 2 && text.substring(0, 2).toLower() == "0o" {
            if negative { return null }
            return yamlRadixToDecimal(text.substring(2, text.length() - 2), 8)
        }
        Int index = 0
        while index < text.length() {
            Int code = text.get(index)
            if code < 48 || code > 57 { return null }
            index = index + 1
        }
        if text.length() > 1 && text.substring(0, 1) == "0" { return null }
        Long value = 0 as Long
        Long max = 9223372036854775807 as Long
        index = 0
        while index < text.length() {
            Long digit = (text.get(index) - 48) as Long
            if value > (max - digit) / (10 as Long) { return null }
            value = value * (10 as Long) + digit
            index = index + 1
        }
        if negative { value = -value }
        return str(value)
    }

    Bool isFloat(String token) {
        if token.indexOf(".") < 0 && token.indexOf("e") < 0 && token.indexOf("E") < 0 { return false }
        Bool hasDigit = false
        Int index = 0
        if token.substring(0, 1) == "-" || token.substring(0, 1) == "+" { index = 1 }
        if index >= token.length() { return false }
        while index < token.length() {
            Int code = token.get(index)
            if code >= 48 && code <= 57 { hasDigit = true; index = index + 1 }
            else if token.substring(index, 1) == "." || token.substring(index, 1) == "e" ||
                    token.substring(index, 1) == "E" || token.substring(index, 1) == "+" ||
                    token.substring(index, 1) == "-" {
                index = index + 1
            } else {
                return false
            }
        }
        return hasDigit
    }

    Bool mergeInto(JsonObject target, JsonValue source) {
        if source.isObject() {
            JsonObject object = source.asObject() as JsonObject
            List<String> keys = object.keys()
            Int index = 0
            while index < keys.length() {
                String key = keys.get(index)
                if !target.has(key) {
                    target.set(key, object.getOr(key, Json.nullValue()))
                }
                index = index + 1
            }
            return true
        }
        if source.isArray() {
            JsonArray array = source.asArray() as JsonArray
            Int index = 0
            while index < array.length() {
                if !self.mergeInto(target, array.get(index)) { return false }
                index = index + 1
            }
            return true
        }
        return self.fail(ErrorKind.DataCorrupted, "Yaml: merge value must be a mapping")
    }
}

static Bool yamlNameValid(String name) {
    if name.length() == 0 { return false }
    Int index = 0
    while index < name.length() {
        Int code = name.get(index)
        if index == 0 {
            if !yamlNameStart(code) { return false }
        } else if !yamlNameChar(code) {
            return false
        }
        index = index + 1
    }
    return true
}

static Int yamlHexValue(String c) {
    if c.length() != 1 { return -1 }
    Int code = c.get(0)
    if code >= 48 && code <= 57 { return code - 48 }
    if code >= 97 && code <= 102 { return code - 97 + 10 }
    if code >= 65 && code <= 70 { return code - 65 + 10 }
    return -1
}

static String? yamlRadixToDecimal(String digits, Int radix) {
    if digits.length() == 0 { return null }
    Long value = 0 as Long
    Long max = 9223372036854775807 as Long
    Int index = 0
    while index < digits.length() {
        Int digit = yamlHexValue(digits.substring(index, 1))
        if digit < 0 || digit >= radix { return null }
        if value > (max - (digit as Long)) / (radix as Long) { return null }
        value = value * (radix as Long) + (digit as Long)
        index = index + 1
    }
    return str(value)
}

// ---------- 生成器 ----------
class YamlWriter {
    final YamlOptions _options
    List<String> _lines
    Long _bytes
    Bool _failed
    ErrorKind _kind
    String _message

    YamlWriter(YamlOptions options) {
        self._options = options
        self._lines = []
        self._bytes = 0 as Long
        self._failed = false
        self._kind = ErrorKind.InvalidArgument
        self._message = ""
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
            self.fail(ErrorKind.InvalidArgument, "Yaml: output exceeds maxBytes")
            return
        }
        self._bytes = self._bytes + size
        self._lines.push(text)
    }

    String scalarText(JsonValue value) {
        if value.isNull() { return "null" }
        if value.isBool() {
            if value.asBool() as Bool { return "true" }
            return "false"
        }
        if value.isNumber() {
            JsonNumber number = value.asNumber() as JsonNumber
            return number.raw()
        }
        String text = value.asString() as String
        if yamlPlainSafe(text) { return text }
        return yamlQuote(text)
    }

    Void writeValue(JsonValue value, Int indent, Int depth) {
        if self._failed { return }
        if depth > self._options.getMaxDepth() {
            self.fail(ErrorKind.InvalidArgument, "Yaml: maxDepth exceeded")
            return
        }
        if value.isObject() {
            JsonObject object = value.asObject() as JsonObject
            List<String> keys = object.keys()
            if keys.length() == 0 {
                self.line("{}")
                return
            }
            Int index = 0
            while index < keys.length() {
                String key = keys.get(index)
                JsonValue child = object.getOr(key, Json.nullValue())
                String prefix = self.spaces(indent) + yamlKey(key) + ":"
                if child.isObject() {
                    JsonObject nested = child.asObject() as JsonObject
                    if nested.length() == 0 {
                        self.line(prefix + " {}")
                    } else {
                        self.line(prefix)
                        self.writeValue(child, indent + 2, depth + 1)
                    }
                } else if child.isArray() {
                    JsonArray nested = child.asArray() as JsonArray
                    if nested.length() == 0 {
                        self.line(prefix + " []")
                    } else {
                        self.line(prefix)
                        self.writeValue(child, indent + 2, depth + 1)
                    }
                } else {
                    self.line(prefix + " " + self.scalarText(child))
                }
                index = index + 1
            }
            return
        }
        if value.isArray() {
            JsonArray array = value.asArray() as JsonArray
            if array.length() == 0 {
                self.line("[]")
                return
            }
            Int index = 0
            while index < array.length() {
                JsonValue child = array.get(index)
                String prefix = self.spaces(indent) + "-"
                if child.isObject() {
                    JsonObject nested = child.asObject() as JsonObject
                    if nested.length() == 0 {
                        self.line(prefix + " {}")
                    } else {
                        self.line(prefix)
                        self.writeValue(child, indent + 2, depth + 1)
                    }
                } else if child.isArray() {
                    JsonArray nested = child.asArray() as JsonArray
                    if nested.length() == 0 {
                        self.line(prefix + " []")
                    } else {
                        self.line(prefix)
                        self.writeValue(child, indent + 2, depth + 1)
                    }
                } else {
                    self.line(prefix + " " + self.scalarText(child))
                }
                index = index + 1
            }
            return
        }
        self.line(self.spaces(indent) + self.scalarText(value))
    }

    String spaces(Int count) {
        String out = ""
        Int index = 0
        while index < count { out = out + " "; index = index + 1 }
        return out
    }
}

// ---------- 公共入口 ----------
class Yaml {
    private Yaml() { }

    static Result<JsonValue, Error> parse(String text) {
        return Yaml.parseWithOptions(text, new YamlOptions())
    }

    static Result<JsonValue, Error> parseWithOptions(String text, YamlOptions options) {
        if text == null || options == null { throw "Yaml.parse: null argument" }
        Result<List<YamlDocument>, Error> documents = Yaml.parseAllWithOptions(text, options)
        if documents.isErr() { return Err(documents.error()) }
        if documents.value().length() != 1 {
            return Err(yamlError(ErrorKind.InvalidArgument, "Yaml: expected exactly one document"))
        }
        return Ok(documents.value().get(0).value())
    }

    static Result<List<YamlDocument>, Error> parseAll(String text) {
        return Yaml.parseAllWithOptions(text, new YamlOptions())
    }

    static Result<List<YamlDocument>, Error> parseAllWithOptions(String text, YamlOptions options) {
        if text == null || options == null { throw "Yaml.parseAll: null argument" }
        if text.length() as Long > options.getMaxBytes() {
            return Err(yamlError(ErrorKind.InvalidArgument, "Yaml: input exceeds maxBytes"))
        }
        YamlParser preparer = new YamlParser(options.copy())
        List<YamlLine> lines = preparer.prepare(text)
        if preparer._failed {
            return Err(yamlError(preparer._kind, preparer._message))
        }
        List<List<YamlLine>> segments = []
        List<YamlLine> current = []
        Bool started = false
        Bool ended = false
        Int index = 0
        while index < lines.length() {
            YamlLine line = lines.get(index)
            if line.indent == 0 && line.content == "---" {
                if current.length() > 0 || started || segments.length() > 0 {
                    segments.push(current)
                    current = []
                }
                started = true
                ended = false
            } else if line.indent == 0 && line.content == "..." {
                segments.push(current)
                current = []
                started = false
                ended = true
            } else {
                current.push(line)
            }
            index = index + 1
        }
        if current.length() > 0 {
            segments.push(current)
        } else if segments.length() == 0 {
            segments.push(current)
        } else if started && !ended {
            segments.push(current)
        }
        if segments.length() > options.getMaxDocuments() {
            return Err(yamlError(ErrorKind.InvalidArgument, "Yaml: maxDocuments exceeded"))
        }
        List<YamlDocument> documents = []
        index = 0
        while index < segments.length() {
            YamlParser parser = new YamlParser(options.copy())
            JsonValue value = parser.parseDocumentLines(segments.get(index))
            if parser._failed {
                return Err(yamlError(parser._kind, parser._message))
            }
            List<String> profiles = Yaml.extractProfiles(value, options.getProfileKey())
            documents.push(new YamlDocument(index, value, profiles))
            index = index + 1
        }
        return Ok(documents)
    }

    static List<String> extractProfiles(JsonValue value, String profileKey) {
        List<String> profiles = []
        if profileKey == "" { return profiles }
        JsonValue? found = Yaml.lookupPath(value, profileKey)
        if found == null { return profiles }
        JsonValue actual = found as JsonValue
        if actual.isString() {
            String text = actual.asString() as String
            if text == "" {
                return profiles
            }
            profiles.push(text)
            return profiles
        }
        if actual.isArray() {
            JsonArray array = actual.asArray() as JsonArray
            Int index = 0
            while index < array.length() {
                JsonValue item = array.get(index)
                if !item.isString() {
                    return profiles
                }
                String text = item.asString() as String
                if text == "" { return profiles }
                profiles.push(text)
                index = index + 1
            }
            return profiles
        }
        return profiles
    }

    static JsonValue? lookupPath(JsonValue value, String path) {
        List<String> parts = path.split(".")
        JsonValue current = value
        Int index = 0
        while index < parts.length() {
            if !current.isObject() { return null }
            JsonObject object = current.asObject() as JsonObject
            if !object.has(parts.get(index)) { return null }
            JsonValue next = object.getOr(parts.get(index), Json.nullValue())
            if index == parts.length() - 1 { return next }
            current = next
            index = index + 1
        }
        return null
    }

    static Result<List<YamlPropertySource>, Error> parsePropertySources(String sourceName, String text) {
        return Yaml.parsePropertySourcesWithOptions(sourceName, text, new YamlOptions())
    }

    static Result<List<YamlPropertySource>, Error> parsePropertySourcesWithOptions(
        String sourceName, String text, YamlOptions options) {
        if sourceName == null || text == null || options == null {
            throw "Yaml.parsePropertySources: null argument"
        }
        if sourceName.length() == 0 {
            return Err(yamlError(ErrorKind.InvalidArgument, "Yaml: empty source name"))
        }
        Result<List<YamlDocument>, Error> documents = Yaml.parseAllWithOptions(text, options)
        if documents.isErr() { return Err(documents.error()) }
        List<YamlPropertySource> sources = []
        Int index = 0
        while index < documents.value().length() {
            YamlDocument document = documents.value().get(index)
            JsonValue value = document.value()
            if !value.isObject() {
                return Err(yamlError(ErrorKind.InvalidArgument, "Yaml: property source root must be a mapping"))
            }
            Map<String, String> properties = [:]
            Yaml.flatten(value, "", properties)
            sources.push(new YamlPropertySource(sourceName + "#" + str(index), index,
                document.profiles(), properties))
            index = index + 1
        }
        return Ok(sources)
    }

    static Void flatten(JsonValue value, String prefix, Map<String, String> out) {
        if value == null { return }
        if value.isObject() {
            JsonObject object = value.asObject() as JsonObject
            List<String> keys = object.keys()
            Int index = 0
            while index < keys.length() {
                String key = keys.get(index)
                String path = key
                if prefix != "" { path = prefix + "." + key }
                Yaml.flatten(object.getOr(key, Json.nullValue()), path, out)
                index = index + 1
            }
            return
        }
        if value.isArray() {
            JsonArray array = value.asArray() as JsonArray
            Int index = 0
            while index < array.length() {
                Yaml.flatten(array.get(index), prefix + "[" + str(index) + "]", out)
                index = index + 1
            }
            return
        }
        if prefix == "" { return }
        out.put(prefix, Yaml.propertyText(value))
    }

    static String propertyText(JsonValue value) {
        if value.isNull() { return "" }
        if value.isBool() {
            if value.asBool() as Bool { return "true" }
            return "false"
        }
        if value.isNumber() {
            JsonNumber number = value.asNumber() as JsonNumber
            return number.raw()
        }
        return value.asString() as String
    }

    static Result<String, Error> stringify(JsonValue value) {
        return Yaml.stringifyWithOptions(value, new YamlOptions())
    }

    static Result<String, Error> stringifyWithOptions(JsonValue value, YamlOptions options) {
        if value == null || options == null { throw "Yaml.stringify: null argument" }
        YamlWriter writer = new YamlWriter(options.copy())
        writer.writeValue(value, 0, 1)
        if writer._failed {
            return Err(yamlError(writer._kind, writer._message))
        }
        if writer._lines.length() == 0 { return Ok("") }
        return Ok(writer._lines.join("\n") + "\n")
    }

    static Result<String, Error> stringifyAll(List<YamlDocument> documents) {
        return Yaml.stringifyAllWithOptions(documents, new YamlOptions())
    }

    static Result<String, Error> stringifyAllWithOptions(List<YamlDocument> documents, YamlOptions options) {
        if documents == null || options == null { throw "Yaml.stringifyAll: null argument" }
        if documents.length() == 0 {
            return Err(yamlError(ErrorKind.InvalidArgument, "Yaml: no documents"))
        }
        if documents.length() > options.getMaxDocuments() {
            return Err(yamlError(ErrorKind.InvalidArgument, "Yaml: maxDocuments exceeded"))
        }
        List<String> parts = []
        Long bytes = 0 as Long
        Int index = 0
        while index < documents.length() {
            Result<String, Error> rendered = Yaml.stringifyWithOptions(documents.get(index).value(), options)
            if rendered.isErr() { return Err(rendered.error()) }
            String text = rendered.value()
            if index > 0 { text = "---\n" + text }
            bytes = bytes + (text.length() as Long)
            if bytes > options.getMaxBytes() {
                return Err(yamlError(ErrorKind.InvalidArgument, "Yaml: output exceeds maxBytes"))
            }
            parts.push(text)
            index = index + 1
        }
        return Ok(parts.join(""))
    }
}
