// xdk.net.mime — media types and common extension mappings.
// Tier: L5；依赖：xdk.errors、xdk.text；稳定性：preview。
package xdk.net.mime
import xdk.errors
import xdk.text

Error mimeError(ErrorKind kind, String message) { return new BasicError(kind, message) }

class MediaType {
    final String _type
    final String _subtype
    final Map<String, String> _parameters

    MediaType(String mediaType, String mediaSubtype, Map<String, String> parameters) {
        if mediaType == null || mediaType == "" || mediaSubtype == null || mediaSubtype == "" {
            throw "MediaType: empty type/subtype"
        }
        if parameters == null { throw "MediaType: null parameters" }
        self._type = mediaType.toLower()
        self._subtype = mediaSubtype.toLower()
        self._parameters = [:]
        List<String> names = parameters.keys()
        Int index = 0
        while index < names.length() {
            String name = names.get(index)
            self._parameters.put(name.toLower(), parameters.getOr(name, ""))
            index = index + 1
        }
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
        Map<String, String> parameters = [:]
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
                parameters.put(name.toLower(), value)
            }
            index = index + 1
        }
        return Ok(new MediaType(mediaType, subtype, parameters))
    }

    String type() { return self._type }
    String subtype() { return self._subtype }
    String? parameter(String name) {
        if name == null { return null }
        return self._parameters.getOrNull(name.toLower())
    }
    Map<String, String> parameters() { return self._parameters.copy() }
    String? charset() { return self.parameter("charset") }

    MediaType withParameter(String name, String value) {
        if name == null || name == "" || value == null || !isToken(name) {
            throw "MediaType.withParameter: invalid argument"
        }
        Map<String, String> next = self._parameters.copy()
        next.put(name.toLower(), value)
        return new MediaType(self._type, self._subtype, next)
    }

    String text() {
        String result = self._type + "/" + self._subtype
        List<String> names = self._parameters.keys()
        Int index = 0
        while index < names.length() {
            result = result + "; " + names.get(index) + "=" + self._parameters.getOr(names.get(index), "")
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

Bool isToken(String text) {
    if text == null || text == "" { return false }
    Int index = 0
    while index < text.length() {
        String c = text.substring(index, 1)
        Bool letter = (c >= "a" && c <= "z") || (c >= "A" && c <= "Z")
        Bool digit = c >= "0" && c <= "9"
        Bool allowed = c == "!" || c == "#" || c == "$" || c == "%" || c == "&" ||
            c == "'" || c == "*" || c == "+" || c == "-" || c == "." || c == "^" ||
            c == "_" || c == "`" || c == "|" || c == "~"
        if !letter && !digit && !allowed { return false }
        index = index + 1
    }
    return true
}

class MimeTypes {
    static MediaType json() { return new MediaType("application", "json", [:]) }
    static MediaType text() { return new MediaType("text", "plain", [:]) }
    static MediaType octetStream() { return new MediaType("application", "octet-stream", [:]) }
    static MediaType formUrlEncoded() { return new MediaType("application", "x-www-form-urlencoded", [:]) }
    static MediaType multipartFormData() { return new MediaType("multipart", "form-data", [:]) }

    static MediaType? fromExtension(String extension) {
        if extension == null { return null }
        String normalized = extension.trim().toLower()
        if normalized.startsWith(".") { normalized = normalized.substring(1, normalized.length() - 1) }
        if normalized == "json" { return json() }
        if normalized == "txt" || normalized == "text" || normalized == "log" { return text() }
        if normalized == "html" || normalized == "htm" { return new MediaType("text", "html", [:]) }
        if normalized == "css" { return new MediaType("text", "css", [:]) }
        if normalized == "js" { return new MediaType("application", "javascript", [:]) }
        if normalized == "xml" { return new MediaType("application", "xml", [:]) }
        if normalized == "png" { return new MediaType("image", "png", [:]) }
        if normalized == "jpg" || normalized == "jpeg" { return new MediaType("image", "jpeg", [:]) }
        if normalized == "gif" { return new MediaType("image", "gif", [:]) }
        if normalized == "svg" { return new MediaType("image", "svg+xml", [:]) }
        if normalized == "pdf" { return new MediaType("application", "pdf", [:]) }
        if normalized == "zip" { return new MediaType("application", "zip", [:]) }
        if normalized == "csv" { return new MediaType("text", "csv", [:]) }
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
