// xdk.net.mime — media types and common extension mappings.
// Tier: L5；依赖：xdk.errors、xdk.text；稳定性：preview。
package xdk.net.mime
import xdk.errors
import xdk.text

Error mimeError(ErrorKind kind, String message) { return new BasicError(kind, message) }

Bool isToken(String text) {
    if text == null || text == "" { return false }
    Int index = 0
    while index < text.length() {
        String c = text.substring(index, 1)
        Bool letter = (compareText(c, "a") >= 0 && compareText(c, "z") <= 0) ||
            (compareText(c, "A") >= 0 && compareText(c, "Z") <= 0)
        Bool digit = compareText(c, "0") >= 0 && compareText(c, "9") <= 0
        Bool allowed = c == "!" || c == "#" || c == "$" || c == "%" || c == "&" ||
            c == "'" || c == "*" || c == "+" || c == "-" || c == "." || c == "^" ||
            c == "_" || c == "`" || c == "|" || c == "~"
        if !letter && !digit && !allowed { return false }
        index = index + 1
    }
    return true
}

class MediaType {
    final String _type
    final String _subtype
    final List<String> _names
    final List<String> _values

    MediaType(String mediaType, String mediaSubtype, List<String> names, List<String> values) {
        if mediaType == null || mediaType == "" || mediaSubtype == null || mediaSubtype == "" {
            throw "MediaType: empty type/subtype"
        }
        if names == null || values == null || names.length() != values.length() {
            throw "MediaType: invalid parameters"
        }
        self._type = mediaType.toLower()
        self._subtype = mediaSubtype.toLower()
        self._names = names.copy()
        self._values = values.copy()
    }

    static Result<MediaType, Error> parse(String text) {
        if text == null { throw "MediaType.parse: null text" }
        String trimmed = text.trim()
        if trimmed == "" { return Err(mimeError(ErrorKind.InvalidArgument, "empty media type")) }
        List<String> parts = trimmed.split(";")
        String fullType = parts.get(0).trim()
        Int slash = fullType.indexOf("/")
        if slash <= 0 || slash >= fullType.length() - 1 {
            return Err(mimeError(ErrorKind.InvalidArgument, "invalid media type"))
        }
        String mediaType = fullType.substring(0, slash)
        String subtype = fullType.substring(slash + 1, fullType.length() - slash - 1)
        if !isToken(mediaType) || !isToken(subtype) {
            return Err(mimeError(ErrorKind.InvalidArgument, "invalid media token"))
        }
        List<String> names = []
        List<String> values = []
        Int index = 1
        while index < parts.length() {
            String parameter = parts.get(index).trim()
            if parameter.length() > 0 {
                Int equals = parameter.indexOf("=")
                if equals <= 0 {
                    return Err(mimeError(ErrorKind.InvalidArgument, "invalid media parameter"))
                }
                String name = parameter.substring(0, equals).trim()
                String value = parameter.substring(equals + 1, parameter.length() - equals - 1).trim()
                if value.length() >= 2 && value.startsWith("\"") && value.endsWith("\"") {
                    value = value.substring(1, value.length() - 2)
                }
                if !isToken(name) {
                    return Err(mimeError(ErrorKind.InvalidArgument, "invalid parameter name"))
                }
                names.push(name.toLower())
                values.push(value)
            }
            index = index + 1
        }
        return Ok(new MediaType(mediaType, subtype, names, values))
    }

    String type() { return self._type }
    String subtype() { return self._subtype }

    String? parameter(String name) {
        if name == null { return null }
        String key = name.toLower()
        Int index = 0
        while index < self._names.length() {
            if self._names.get(index) == key { return self._values.get(index) }
            index = index + 1
        }
        return null
    }

    String? charset() { return self.parameter("charset") }

    MediaType withParameter(String name, String value) {
        if name == null || name == "" || value == null || !isToken(name) {
            throw "MediaType.withParameter: invalid argument"
        }
        List<String> names = []
        List<String> values = []
        Int index = 0
        while index < self._names.length() {
            names.push(self._names.get(index))
            values.push(self._values.get(index))
            index = index + 1
        }
        names.push(name.toLower())
        values.push(value)
        return new MediaType(self._type, self._subtype, names, values)
    }

    String text() {
        String result = self._type + "/" + self._subtype
        Int index = 0
        while index < self._names.length() {
            result = result + "; " + self._names.get(index) + "=" + self._values.get(index)
            index = index + 1
        }
        return result
    }

    Bool isText() { return self._type == "text" }
    Bool isJson() { return self._type == "application" && (self._subtype == "json" || self._subtype.endsWith("+json")) }
    Bool isFormUrlEncoded() { return self._type == "application" && self._subtype == "x-www-form-urlencoded" }
    Bool isMultipart() { return self._type == "multipart" }

    Bool equals(MediaType other) {
        if other == null { return false }
        return self.text() == other.text()
    }
    String toString() { return self.text() }
}

class MimeTypes {
    static MediaType json() { List<String> n = []; List<String> v = []; return new MediaType("application", "json", n, v) }
    static MediaType text() { List<String> n = []; List<String> v = []; return new MediaType("text", "plain", n, v) }
    static MediaType octetStream() { List<String> n = []; List<String> v = []; return new MediaType("application", "octet-stream", n, v) }
    static MediaType formUrlEncoded() { List<String> n = []; List<String> v = []; return new MediaType("application", "x-www-form-urlencoded", n, v) }
    static MediaType multipartFormData() { List<String> n = []; List<String> v = []; return new MediaType("multipart", "form-data", n, v) }

    static MediaType? fromExtension(String extension) {
        if extension == null { return null }
        String normalized = extension.trim().toLower()
        if normalized.startsWith(".") { normalized = normalized.substring(1, normalized.length() - 1) }
        if normalized == "json" { return MimeTypes.json() }
        if normalized == "txt" || normalized == "text" || normalized == "log" { return MimeTypes.text() }
        if normalized == "html" || normalized == "htm" { List<String> n = []; List<String> v = []; return new MediaType("text", "html", n, v) }
        if normalized == "css" { List<String> n = []; List<String> v = []; return new MediaType("text", "css", n, v) }
        if normalized == "js" { List<String> n = []; List<String> v = []; return new MediaType("application", "javascript", n, v) }
        if normalized == "xml" { List<String> n = []; List<String> v = []; return new MediaType("application", "xml", n, v) }
        if normalized == "png" { List<String> n = []; List<String> v = []; return new MediaType("image", "png", n, v) }
        if normalized == "jpg" || normalized == "jpeg" { List<String> n = []; List<String> v = []; return new MediaType("image", "jpeg", n, v) }
        if normalized == "gif" { List<String> n = []; List<String> v = []; return new MediaType("image", "gif", n, v) }
        if normalized == "svg" { List<String> n = []; List<String> v = []; return new MediaType("image", "svg+xml", n, v) }
        if normalized == "pdf" { List<String> n = []; List<String> v = []; return new MediaType("application", "pdf", n, v) }
        if normalized == "zip" { List<String> n = []; List<String> v = []; return new MediaType("application", "zip", n, v) }
        if normalized == "csv" { List<String> n = []; List<String> v = []; return new MediaType("text", "csv", n, v) }
        return null
    }

    static String? extensionFor(MediaType type) {
        if type == null { return null }
        String full = type.type() + "/" + type.subtype()
        if full == "application/json" { return "json" }
        if full == "text/plain" { return "txt" }
        if full == "text/html" { return "html" }
        if full == "text/css" { return "css" }
        if full == "application/javascript" { return "js" }
        if full == "application/xml" { return "xml" }
        if full == "image/png" { return "png" }
        if full == "image/jpeg" { return "jpg" }
        if full == "image/gif" { return "gif" }
        if full == "image/svg+xml" { return "svg" }
        if full == "application/pdf" { return "pdf" }
        if full == "application/zip" { return "zip" }
        if full == "text/csv" { return "csv" }
        return null
    }

    static String? charsetFor(MediaType type) {
        if type == null { return null }
        String? explicitCharset = type.charset()
        if explicitCharset != null { return explicitCharset }
        if type.isText() { return "utf-8" }
        if type.isJson() { return "utf-8" }
        return null
    }
}
