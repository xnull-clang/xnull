// xdk.xml —— XML 1.0 元素树解析/生成（M18.4）
//
// 元素中心模型：元素只有属性、子元素、可选纯文本；混合内容明确失败。
// 不做 DTD/实体声明展开、命名空间解析、XSD/XPath/流式。
// 稳定性：preview。合同见 docs/design/utils/xml/。
package xdk.xml
import xdk.errors
import xdk.bytes
import xdk.text

// ---------- 名称/字符校验 ----------
static Bool xmlNameStart(Int code) {
    if code >= 65 && code <= 90 { return true }
    if code >= 97 && code <= 122 { return true }
    if code == 95 || code == 58 { return true }
    return code >= 128
}

static Bool xmlNameChar(Int code) {
    if xmlNameStart(code) { return true }
    if code >= 48 && code <= 57 { return true }
    return code == 46 || code == 45
}

static Bool xmlNameValid(String name) {
    if name == null || name.length() == 0 { return false }
    Int index = 0
    while index < name.length() {
        Int code = name.get(index)
        if index == 0 {
            if !xmlNameStart(code) { return false }
        } else {
            if !xmlNameChar(code) { return false }
        }
        index = index + 1
    }
    return true
}

static Bool xmlCharValid(String text) {
    if text == null { return false }
    Int index = 0
    while index < text.length() {
        Int code = text.get(index)
        if code == 9 || code == 10 || code == 13 { index = index + 1; continue }
        if code < 32 { return false }
        if code == 0xFFFE || code == 0xFFFF { return false }
        index = index + 1
    }
    return true
}

static Error xmlError(ErrorKind kind, String message) {
    return new BasicError(kind, message)
}

// ---------- XmlElement ----------
class XmlElement {
    final String _name
    Map<String, String> _attributes
    List<XmlElement> _children
    String? _text

    XmlElement(String name) {
        if name == null || name.length() == 0 {
            throw "XmlElement: empty name"
        }
        if !xmlNameValid(name) {
            throw "XmlElement: invalid name"
        }
        self._name = name
        Map<String, String> attributes = [:]
        self._attributes = attributes
        self._children = []
    }

    String name() { return self._name }

    Map<String, String> attributes() {
        Map<String, String> result = [:]
        List<String> keys = self._attributes.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            result.put(key, self._attributes.getOr(key, ""))
            index = index + 1
        }
        return result
    }

    String? attributeOrNull(String name) {
        if name == null { throw "XmlElement.attributeOrNull: null name" }
        if !self._attributes.has(name) { return null }
        return self._attributes.getOr(name, "")
    }

    XmlElement setAttribute(String name, String value) {
        if name == null || name.length() == 0 {
            throw "XmlElement.setAttribute: empty name"
        }
        if !xmlNameValid(name) {
            throw "XmlElement.setAttribute: invalid name"
        }
        if value == null {
            throw "XmlElement.setAttribute: null value"
        }
        if !xmlCharValid(value) {
            throw "XmlElement.setAttribute: invalid value"
        }
        self._attributes.put(name, value)
        return self
    }

    Bool removeAttribute(String name) {
        if name == null { throw "XmlElement.removeAttribute: null name" }
        return self._attributes.remove(name)
    }

    List<XmlElement> children() {
        return self._children.copy()
    }

    XmlElement addChild(XmlElement child) {
        if child == null { throw "XmlElement.addChild: null child" }
        if child == self { throw "XmlElement.addChild: self reference" }
        if self._text != null {
            throw "XmlElement.addChild: element already has text"
        }
        self._children.push(child)
        return self
    }

    String? textOrNull() { return self._text }

    XmlElement setText(String? value) {
        if value == null || value == "" {
            self._text = null
            return self
        }
        if self._children.length() > 0 {
            throw "XmlElement.setText: element already has children"
        }
        if !xmlCharValid(value) {
            throw "XmlElement.setText: invalid text"
        }
        self._text = value
        return self
    }

    XmlElement copy() {
        XmlElement clone = new XmlElement(self._name)
        clone._text = self._text
        List<String> keys = self._attributes.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            clone._attributes.put(key, self._attributes.getOr(key, ""))
            index = index + 1
        }
        index = 0
        while index < self._children.length() {
            clone._children.push(self._children.get(index).copy())
            index = index + 1
        }
        return clone
    }

    String describe() {
        String textPart = "none"
        if self._text != null {
            String text = self._text as String
            textPart = str(text.length())
        }
        return self._name + "(attrs=" + str(self._attributes.length()) +
            ",children=" + str(self._children.length()) + ",text=" + textPart + ")"
    }
}

// ---------- XmlOptions ----------
class XmlOptions {
    Int _maxDepth
    Long _maxBytes
    Bool _preserveWhitespace
    Bool _allowDoctype

    XmlOptions() {
        self._maxDepth = 128
        self._maxBytes = 16777216 as Long
        self._preserveWhitespace = true
        self._allowDoctype = false
    }

    XmlOptions maxDepth(Int value) {
        if value <= 0 { throw "XmlOptions.maxDepth: must be positive" }
        self._maxDepth = value
        return self
    }

    XmlOptions maxBytes(Long value) {
        if value <= 0 { throw "XmlOptions.maxBytes: must be positive" }
        self._maxBytes = value
        return self
    }

    XmlOptions preserveWhitespace(Bool value) {
        self._preserveWhitespace = value
        return self
    }

    XmlOptions allowDoctype(Bool value) {
        self._allowDoctype = value
        return self
    }

    Int getMaxDepth() { return self._maxDepth }
    Long getMaxBytes() { return self._maxBytes }
    Bool isPreserveWhitespace() { return self._preserveWhitespace }
    Bool isAllowDoctype() { return self._allowDoctype }

    XmlOptions copy() {
        XmlOptions out = new XmlOptions()
        out._maxDepth = self._maxDepth
        out._maxBytes = self._maxBytes
        out._preserveWhitespace = self._preserveWhitespace
        out._allowDoctype = self._allowDoctype
        return out
    }
}

// ---------- 解析器 ----------
class XmlParser {
    final String _text
    final Int _length
    final XmlOptions _options
    Int _pos
    Bool _failed
    ErrorKind _kind
    String _message

    XmlParser(String text, XmlOptions options) {
        self._text = text
        self._length = text.length()
        self._options = options
        self._pos = 0
        self._failed = false
        self._kind = ErrorKind.DataCorrupted
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

    Bool atEnd() { return self._pos >= self._length }

    String peek() {
        if self.atEnd() { return "" }
        return self._text.substring(self._pos, 1)
    }

    String peekAt(Int offset) {
        Int at = self._pos + offset
        if at < 0 || at >= self._length { return "" }
        return self._text.substring(at, 1)
    }

    Void advance() { self._pos = self._pos + 1 }

    Bool startsWith(String text) {
        if self._pos + text.length() > self._length { return false }
        return self._text.substring(self._pos, text.length()) == text
    }

    Void advanceBy(Int count) { self._pos = self._pos + count }

    Void skipWhitespace() {
        while !self.atEnd() {
            String c = self.peek()
            if c == " " || c == "\t" || c == "\r" || c == "\n" { self.advance() } else { return }
        }
    }

    Void skipComment() {
        if !self.startsWith("<!--") { return }
        self.advanceBy(4)
        while !self.atEnd() {
            if self.startsWith("-->") {
                self.advanceBy(3)
                return
            }
            self.advance()
        }
        self.fail(ErrorKind.DataCorrupted, "Xml: unterminated comment")
    }

    Void skipProcessingInstruction() {
        if !self.startsWith("<?") { return }
        self.advanceBy(2)
        while !self.atEnd() {
            if self.startsWith("?>") {
                self.advanceBy(2)
                return
            }
            self.advance()
        }
        self.fail(ErrorKind.DataCorrupted, "Xml: unterminated processing instruction")
    }

    Bool skipDoctype() {
        if !self.startsWith("<!DOCTYPE") { return true }
        if !self._options.isAllowDoctype() {
            return self.fail(ErrorKind.PermissionDenied, "Xml: DOCTYPE is not allowed")
        }
        Int start = self._pos
        self.advanceBy(9)
        Bool inSubset = false
        Int subsetDepth = 0
        while !self.atEnd() {
            String c = self.peek()
            if c == "[" {
                inSubset = true
                subsetDepth = subsetDepth + 1
            } else if c == "]" {
                subsetDepth = subsetDepth - 1
            } else if c == ">" && subsetDepth <= 0 {
                self.advance()
                if inSubset {
                    return self.fail(ErrorKind.Unsupported, "Xml: internal DTD subset is not supported")
                }
                return true
            }
            self.advance()
        }
        return self.fail(ErrorKind.DataCorrupted, "Xml: unterminated DOCTYPE")
    }

    Void skipMisc() {
        while !self.atEnd() {
            self.skipWhitespace()
            if self.startsWith("<!--") { self.skipComment() }
            else if self.startsWith("<?") { self.skipProcessingInstruction() }
            else { return }
        }
    }

    XmlElement? parseDocument() {
        if self._length as Long > self._options.getMaxBytes() {
            self.fail(ErrorKind.InvalidArgument, "Xml: input exceeds maxBytes")
            return null
        }
        if self.peek() == "\uFEFF" { self.advance() }
        if self.startsWith("<?xml") {
            if !self.parseDeclaration() { return null }
        }
        self.skipMisc()
        if self.startsWith("<!DOCTYPE") {
            if !self.skipDoctype() { return null }
            self.skipMisc()
        }
        if self.atEnd() || self.peek() != "<" {
            self.fail(ErrorKind.DataCorrupted, "Xml: expected root element")
            return null
        }
        XmlElement? root = self.parseElement(1)
        if root == null { return null }
        self.skipMisc()
        if !self.atEnd() {
            self.fail(ErrorKind.DataCorrupted, "Xml: trailing content after root")
            return null
        }
        return root
    }

    Bool parseDeclaration() {
        self.advanceBy(5)
        while !self.atEnd() && !self.startsWith("?>") {
            self.skipWhitespace()
            if self.startsWith("?>") { break }
            String key = self.parseName()
            if key == "" { return self.fail(ErrorKind.DataCorrupted, "Xml: invalid declaration") }
            self.skipWhitespace()
            if self.peek() != "=" {
                return self.fail(ErrorKind.DataCorrupted, "Xml: invalid declaration attribute")
            }
            self.advance()
            self.skipWhitespace()
            String? value = self.parseAttributeValue()
            if value == null { return false }
            if key == "encoding" {
                String encoded = value as String
                String lower = encoded.toLower()
                if lower != "utf-8" && lower != "utf8" {
                    return self.fail(ErrorKind.Unsupported, "Xml: unsupported encoding")
                }
            }
        }
        if !self.startsWith("?>") {
            return self.fail(ErrorKind.DataCorrupted, "Xml: unterminated declaration")
        }
        self.advanceBy(2)
        return true
    }

    String parseName() {
        Int start = self._pos
        while !self.atEnd() {
            Int code = self.peek().get(0)
            if (self._pos == start && xmlNameStart(code)) ||
               (self._pos > start && xmlNameChar(code)) {
                self.advance()
            } else {
                break
            }
        }
        if self._pos == start { return "" }
        return self._text.substring(start, self._pos - start)
    }

    String? parseAttributeValue() {
        String quote = self.peek()
        if quote != "\"" && quote != "'" { return null }
        self.advance()
        String result = ""
        while !self.atEnd() {
            String c = self.peek()
            if c == quote {
                self.advance()
                return result
            }
            if c == "<" {
                self.fail(ErrorKind.DataCorrupted, "Xml: < in attribute value")
                return null
            }
            if c == "&" {
                String? decoded = self.parseEntity()
                if decoded == null { return null }
                result = result + (decoded as String)
            } else {
                result = result + c
                self.advance()
            }
        }
        self.fail(ErrorKind.DataCorrupted, "Xml: unterminated attribute value")
        return null
    }

    String? parseEntity() {
        self.advance()
        String name = ""
        while !self.atEnd() && self.peek() != ";" {
            name = name + self.peek()
            self.advance()
        }
        if self.peek() != ";" {
            self.fail(ErrorKind.DataCorrupted, "Xml: unterminated entity")
            return null
        }
        self.advance()
        if name == "amp" { return "&" }
        if name == "lt" { return "<" }
        if name == "gt" { return ">" }
        if name == "quot" { return "\"" }
        if name == "apos" { return "'" }
        if name.startsWith("#x") || name.startsWith("#X") {
            Int code = 0
            Int index = 2
            if index >= name.length() { self.fail(ErrorKind.DataCorrupted, "Xml: invalid character reference"); return null }
            while index < name.length() {
                Int digit = xmlHexValue(name.substring(index, 1))
                if digit < 0 { self.fail(ErrorKind.DataCorrupted, "Xml: invalid character reference"); return null }
                code = code * 16 + digit
                index = index + 1
            }
            return fromCodePoint(code)
        }
        if name.startsWith("#") {
            Int code = 0
            Int index = 1
            if index >= name.length() { self.fail(ErrorKind.DataCorrupted, "Xml: invalid character reference"); return null }
            while index < name.length() {
                Int d = name.get(index) - 48
                if d < 0 || d > 9 { self.fail(ErrorKind.DataCorrupted, "Xml: invalid character reference"); return null }
                code = code * 10 + d
                index = index + 1
            }
            return fromCodePoint(code)
        }
        self.fail(ErrorKind.DataCorrupted, "Xml: unknown entity"); return null
    }

    XmlElement? parseElement(Int depth) {
        if depth > self._options.getMaxDepth() {
            self.fail(ErrorKind.InvalidArgument, "Xml: maxDepth exceeded")
            return null
        }
        if self.peek() != "<" { self.fail(ErrorKind.DataCorrupted, "Xml: expected element"); return null }
        self.advance()
        if self.peek() == "/" { self.fail(ErrorKind.DataCorrupted, "Xml: unexpected closing tag"); return null }
        String name = self.parseName()
        if name == "" { self.fail(ErrorKind.DataCorrupted, "Xml: invalid element name"); return null }
        XmlElement element = new XmlElement(name)
        List<String> attributeNames = []
        while true {
            self.skipWhitespace()
            if self.startsWith("/>") {
                self.advanceBy(2)
                return element
            }
            if self.peek() == ">" {
                self.advance()
                break
            }
            String attribute = self.parseName()
            if attribute == "" { self.fail(ErrorKind.DataCorrupted, "Xml: invalid attribute name"); return null }
            Int duplicate = 0
            while duplicate < attributeNames.length() {
                if attributeNames.get(duplicate) == attribute {
                    self.fail(ErrorKind.DataCorrupted, "Xml: duplicate attribute"); return null
                }
                duplicate = duplicate + 1
            }
            attributeNames.push(attribute)
            self.skipWhitespace()
            if self.peek() != "=" { self.fail(ErrorKind.DataCorrupted, "Xml: expected ="); return null }
            self.advance()
            self.skipWhitespace()
            String? value = self.parseAttributeValue()
            if value == null { return null }
            element.setAttribute(attribute, value as String)
        }
        String text = ""
        while true {
            if self.atEnd() {
                self.fail(ErrorKind.DataCorrupted, "Xml: unterminated element"); return null
            }
            if self.startsWith("</") {
                self.advanceBy(2)
                String closing = self.parseName()
                self.skipWhitespace()
                if self.peek() != ">" { self.fail(ErrorKind.DataCorrupted, "Xml: expected >"); return null }
                self.advance()
                if closing != name { self.fail(ErrorKind.DataCorrupted, "Xml: mismatched closing tag"); return null }
                if element.children().length() > 0 && text.trim().length() > 0 {
                    self.fail(ErrorKind.DataCorrupted, "Xml: mixed content")
                    return null
                }
                if text.length() > 0 && element.children().length() == 0 {
                    String normalized = text
                    if !self._options.isPreserveWhitespace() { normalized = normalized.trim() }
                    if normalized.length() > 0 { element.setText(normalized) }
                }
                return element
            }
            if self.startsWith("<!--") {
                self.skipComment()
                if self._failed { return null }
                continue
            }
            if self.startsWith("<![CDATA[") {
                if element.children().length() > 0 || text.length() > 0 && text.trim().length() > 0 {
                    self.fail(ErrorKind.DataCorrupted, "Xml: mixed content"); return null
                }
                self.advanceBy(9)
                String cdata = ""
                while !self.atEnd() && !self.startsWith("]]>") {
                    cdata = cdata + self.peek()
                    self.advance()
                }
                if !self.startsWith("]]>") { self.fail(ErrorKind.DataCorrupted, "Xml: unterminated CDATA"); return null }
                self.advanceBy(3)
                if element.children().length() > 0 {
                    self.fail(ErrorKind.DataCorrupted, "Xml: mixed content"); return null
                }
                text = text + cdata
                continue
            }
            if self.startsWith("<?") {
                self.skipProcessingInstruction()
                if self._failed { return null }
                continue
            }
            if self.peek() == "<" {
                if text.trim().length() > 0 {
                    self.fail(ErrorKind.DataCorrupted, "Xml: mixed content"); return null
                }
                String childText = text
                text = ""
                if childText.length() > 0 && self._options.isPreserveWhitespace() {
                    /* 元素间的纯空白不保留；无法建模混合内容。 */
                }
                XmlElement? child = self.parseElement(depth + 1)
                if child == null { return null }
                element.addChild(child as XmlElement)
                continue
            }
            if self.startsWith("]]>") {
                self.fail(ErrorKind.DataCorrupted, "Xml: ]]> in text"); return null
            }
            String c = self.peek()
            if c == "&" {
                String? decoded = self.parseEntity()
                if decoded == null { return null }
                text = text + (decoded as String)
            } else {
                if !xmlCharValid(c) { self.fail(ErrorKind.DataCorrupted, "Xml: invalid character"); return null }
                text = text + c
                self.advance()
            }
        }
        return null
    }
}

// ---------- 生成器 ----------
class XmlWriter {
    final XmlOptions _options
    List<String> _parts
    Long _bytes
    Bool _failed
    ErrorKind _kind
    String _message

    XmlWriter(XmlOptions options) {
        self._options = options
        self._parts = []
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

    Void append(String text) {
        if self._failed { return }
        Long size = text.length() as Long
        if self._bytes + size > self._options.getMaxBytes() {
            self.fail(ErrorKind.InvalidArgument, "Xml: output exceeds maxBytes")
            return
        }
        self._bytes = self._bytes + size
        self._parts.push(text)
    }

    String escapeText(String text) {
        String out = ""
        Int index = 0
        while index < text.length() {
            String c = text.substring(index, 1)
            if c == "&" { out = out + "&amp;" }
            else if c == "<" { out = out + "&lt;" }
            else if c == ">" { out = out + "&gt;" }
            else { out = out + c }
            index = index + 1
        }
        return out
    }

    String escapeAttribute(String text) {
        String out = ""
        Int index = 0
        while index < text.length() {
            String c = text.substring(index, 1)
            if c == "&" { out = out + "&amp;" }
            else if c == "<" { out = out + "&lt;" }
            else if c == ">" { out = out + "&gt;" }
            else if c == "\"" { out = out + "&quot;" }
            else { out = out + c }
            index = index + 1
        }
        return out
    }

    Void writeElement(XmlElement element, Int depth) {
        if self._failed { return }
        if depth > self._options.getMaxDepth() {
            self.fail(ErrorKind.InvalidArgument, "Xml: maxDepth exceeded")
            return
        }
        self.append("<" + element.name())
        Map<String, String> attributes = element.attributes()
        List<String> keys = attributes.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            self.append(" " + key + "=\"" + self.escapeAttribute(attributes.getOr(key, "")) + "\"")
            index = index + 1
        }
        List<XmlElement> children = element.children()
        String? text = element.textOrNull()
        if children.length() == 0 && text == null {
            self.append("/>")
            return
        }
        self.append(">")
        if text != null {
            self.append(self.escapeText(text as String))
        }
        index = 0
        while index < children.length() {
            self.writeElement(children.get(index), depth + 1)
            index = index + 1
        }
        self.append("</" + element.name() + ">")
    }
}

// ---------- 公共入口 ----------
class Xml {
    private Xml() { }

    static Result<XmlElement, Error> parse(String text) {
        return Xml.parseWithOptions(text, new XmlOptions())
    }

    static Result<XmlElement, Error> parseWithOptions(String text, XmlOptions options) {
        if text == null || options == null { throw "Xml.parse: null argument" }
        XmlParser parser = new XmlParser(text, options.copy())
        XmlElement? root = parser.parseDocument()
        if root == null {
            return Err(xmlError(parser._kind, parser._message))
        }
        return Ok(root as XmlElement)
    }

    static Result<XmlElement, Error> parseBytes(Bytes data) {
        return Xml.parseBytesWithOptions(data, new XmlOptions())
    }

    static Result<XmlElement, Error> parseBytesWithOptions(Bytes data, XmlOptions options) {
        if data == null || options == null { throw "Xml.parseBytes: null argument" }
        if data.length() >= 2 {
            Int first = data.get(0)
            Int second = data.get(1)
            if (first == 0xFF && second == 0xFE) || (first == 0xFE && second == 0xFF) {
                return Err(xmlError(ErrorKind.Unsupported, "Xml: UTF-16 is not supported"))
            }
        }
        if data.length() as Long > options.getMaxBytes() {
            return Err(xmlError(ErrorKind.InvalidArgument, "Xml: input exceeds maxBytes"))
        }
        return Xml.parseWithOptions(data.toString(), options)
    }

    static Result<String, Error> stringify(XmlElement element) {
        return Xml.stringifyWithOptions(element, new XmlOptions())
    }

    static Result<String, Error> stringifyWithOptions(XmlElement element, XmlOptions options) {
        if element == null || options == null { throw "Xml.stringify: null argument" }
        XmlWriter writer = new XmlWriter(options.copy())
        writer.writeElement(element, 1)
        if writer._failed {
            return Err(xmlError(writer._kind, writer._message))
        }
        return Ok(writer._parts.join(""))
    }

    static Bool isXml(Bytes data) {
        if data == null { throw "Xml.isXml: null data" }
        Int index = 0
        if data.length() >= 3 && data.get(0) == 0xEF && data.get(1) == 0xBB && data.get(2) == 0xBF {
            index = 3
        }
        while index < data.length() {
            Int c = data.get(index)
            if c == 32 || c == 9 || c == 10 || c == 13 {
                index = index + 1
            } else {
                break
            }
        }
        if index >= data.length() { return false }
        if data.get(index) != 60 { return false }
        index = index + 1
        if index >= data.length() { return false }
        Int next = data.get(index)
        if next == 63 { return true }
        if next == 33 || next == 47 { return false }
        return next == 95 || next == 58 || (next >= 65 && next <= 90) || (next >= 97 && next <= 122) || next >= 128
    }
}

// ---------- 内部 hex（数字实体） ----------
static Int xmlHexValue(String c) {
    if c.length() != 1 { return -1 }
    Int code = c.get(0)
    if code >= 48 && code <= 57 { return code - 48 }
    if code >= 97 && code <= 102 { return code - 97 + 10 }
    if code >= 65 && code <= 70 { return code - 65 + 10 }
    return -1
}
