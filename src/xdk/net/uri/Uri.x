// xdk.net.uri — URI parsing, components, query strings, percent encoding.
// Tier: L5；依赖：xdk.errors、xdk.text、xdk.bytes；稳定性：preview。
package xdk.net.uri
import xdk.errors
import xdk.text
import xdk.bytes

Error uriError(ErrorKind kind, String message) { return new BasicError(kind, message) }

Bool uriAsciiLetter(String text) {
    if text == "" { return false }
    Char c = text.charAt(0)
    Bool lower = c >= 'a' && c <= 'z'
    Bool upper = c >= 'A' && c <= 'Z'
    return lower || upper
}

Bool isValidScheme(String scheme) {
    if scheme == null || scheme == "" { return false }
    if !uriAsciiLetter(scheme.substring(0, 1)) { return false }
    Int index = 1
    while index < scheme.length() {
        String c = scheme.substring(index, 1)
        Bool letter = uriAsciiLetter(c)
        Bool digit = c >= "0" && c <= "9"
        if !letter && !digit && c != "+" && c != "-" && c != "." { return false }
        index = index + 1
    }
    return true
}

Int uriHexValue(String text) {
    if text == "" { return -1 }
    String c = text.substring(0, 1)
    if c >= "0" && c <= "9" { return (c.charAt(0) - '0') as Int }
    if c >= "a" && c <= "f" { return (c.charAt(0) - 'a' + 10) as Int }
    if c >= "A" && c <= "F" { return (c.charAt(0) - 'A' + 10) as Int }
    return -1
}

String uriHexDigit(Int value) {
    if value < 10 { return str(value) }
    if value == 10 { return "A" }
    if value == 11 { return "B" }
    if value == 12 { return "C" }
    if value == 13 { return "D" }
    if value == 14 { return "E" }
    return "F"
}

String percentEncode(String text, String allowed) {
    if text == null || allowed == null { throw "percentEncode: null argument" }
    String result = ""
    Int index = 0
    while index < text.length() {
        String c = text.substring(index, 1)
        Int code = c.charAt(0) as Int
        Bool keep = false
        if code < 128 {
            Int allowedIndex = 0
            while allowedIndex < allowed.length() {
                if allowed.substring(allowedIndex, 1) == c { keep = true; break }
                allowedIndex = allowedIndex + 1
            }
        }
        if keep {
            result = result + c
        } else {
            Bytes encoded = fromUtf8(c)
            Int byteIndex = 0
            while byteIndex < encoded.length() {
                Int value = encoded.get(byteIndex)
                result = result + "%" + uriHexDigit(value / 16) + uriHexDigit(value % 16)
                byteIndex = byteIndex + 1
            }
        }
        index = index + 1
    }
    return result
}

Result<String, Error> percentDecode(String text) {
    if text == null { throw "percentDecode: null text" }
    Bytes result = Bytes.fromString("")
    Int index = 0
    while index < text.length() {
        String c = text.substring(index, 1)
        if c == "%" {
            if index + 2 >= text.length() {
                return Err(uriError(ErrorKind.DataCorrupted, "truncated percent escape"))
            }
            Int high = uriHexValue(text.substring(index + 1, 1))
            Int low = uriHexValue(text.substring(index + 2, 1))
            if high < 0 || low < 0 {
                return Err(uriError(ErrorKind.DataCorrupted, "invalid percent escape"))
            }
            result.push(high * 16 + low)
            index = index + 3
        } else {
            Bytes raw = fromUtf8(c)
            Int rawIndex = 0
            while rawIndex < raw.length() {
                result.push(raw.get(rawIndex))
                rawIndex = rawIndex + 1
            }
            index = index + 1
        }
    }
    return Ok(result.toString())
}

String queryEncode(String text) {
    return percentEncode(text, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}

Result<String, Error> queryDecode(String text) {
    if text == null { throw "queryDecode: null text" }
    return percentDecode(text.replace("+", " "))
}

class Query {
    final List<String> _names
    final List<String> _values

    Query() {
        self._names = []
        self._values = []
    }

    static Query parseValue(String text) {
        Query result = new Query()
        if text == null || text == "" { return result }
        List<String> pairs = text.split("&")
        Int index = 0
        while index < pairs.length() {
            String pair = pairs.get(index)
            if pair.length() > 0 {
                Int equals = pair.indexOf("=")
                String name = pair
                String value = ""
                if equals >= 0 {
                    name = pair.substring(0, equals)
                    value = pair.substring(equals + 1, pair.length() - equals - 1)
                }
                Result<String, Error> decodedName = queryDecode(name)
                Result<String, Error> decodedValue = queryDecode(value)
                if decodedName.isOk() && decodedValue.isOk() {
                    result.add(decodedName.value(), decodedValue.value())
                }
                index = index + 1
            } else {
                index = index + 1
            }
        }
        return result
    }

    static Result<Query, Error> parse(String text) {
        if text == null { throw "Query.parse: null text" }
        return Ok(parseValue(text))
    }

    Void add(String name, String value) {
        if name == null || name == "" || value == null { throw "Query.add: invalid argument" }
        self._names.push(name)
        self._values.push(value)
    }

    Void set(String name, String value) {
        if name == null || name == "" || value == null { throw "Query.set: invalid argument" }
        self.remove(name)
        self.add(name, value)
    }

    String? getOrNull(String name) {
        Int index = 0
        while index < self._names.length() {
            if self._names.get(index) == name { return self._values.get(index) }
            index = index + 1
        }
        return null
    }

    String getOr(String name, String fallback) {
        if fallback == null { throw "Query.getOr: null fallback" }
        String? found = self.getOrNull(name)
        if found == null { return fallback }
        return found as String
    }

    List<String> getAll(String name) {
        List<String> result = []
        Int index = 0
        while index < self._names.length() {
            if self._names.get(index) == name { result.push(self._values.get(index)) }
            index = index + 1
        }
        return result
    }

    Bool has(String name) { return self.getOrNull(name) != null }
    Bool remove(String name) {
        Bool removed = false
        Int index = self._names.length() - 1
        while index >= 0 {
            if self._names.get(index) == name {
                self._names.remove(index)
                self._values.remove(index)
                removed = true
            }
            index = index - 1
        }
        return removed
    }

    Int length() { return self._names.length() }
    List<String> names() { return self._names.copy() }
    List<String> values() { return self._values.copy() }

    String encode() {
        String result = ""
        Int index = 0
        while index < self._names.length() {
            if index > 0 { result = result + "&" }
            result = result + queryEncode(self._names.get(index)) + "=" + queryEncode(self._values.get(index))
            index = index + 1
        }
        return result
    }

    Void clear() { self._names.clear(); self._values.clear() }
    Query copy() {
        Query result = new Query()
        Int index = 0
        while index < self._names.length() {
            result.add(self._names.get(index), self._values.get(index))
            index = index + 1
        }
        return result
    }
    String toString() { return self.encode() }
}

class Uri {
    final String? _scheme
    final String? _userInfo
    final String? _host
    final Int? _port
    final String _path
    final Query _query
    final Bool _hasQuery
    final String? _fragment

    Uri(String? scheme, String? userInfo, String? host, Int? port, String path,
        Query query, Bool hasQuery, String? fragment) {
        if scheme != null && !isValidScheme(scheme) { throw "Uri: invalid scheme" }
        if port != null && (port < 0 || port > 65535) { throw "Uri: invalid port" }
        if path == null || query == null { throw "Uri: null path/query" }
        self._scheme = scheme
        self._userInfo = userInfo
        self._host = host
        self._port = port
        self._path = path
        self._query = query
        self._hasQuery = hasQuery
        self._fragment = fragment
    }

    static Result<Uri, Error> parse(String text) {
        if text == null { throw "Uri.parse: null text" }
        String remaining = text
        String? scheme = null
        Int colon = remaining.indexOf(":")
        Int slash = remaining.indexOf("/")
        Int question = remaining.indexOf("?")
        Int hash = remaining.indexOf("#")
        Bool hasScheme = colon >= 0 && (slash < 0 || colon < slash) &&
            (question < 0 || colon < question) && (hash < 0 || colon < hash)
        if hasScheme {
            String candidate = remaining.substring(0, colon)
            if !isValidScheme(candidate) {
                return Err(uriError(ErrorKind.InvalidArgument, "Uri.parse: invalid scheme"))
            }
            scheme = candidate
            remaining = remaining.substring(colon + 1, remaining.length() - colon - 1)
        }
        String? host = null
        String? userInfo = null
        Int? port = null
        Bool hasAuthority = remaining.startsWith("//")
        if hasAuthority {
            remaining = remaining.substring(2, remaining.length() - 2)
            Int end = remaining.length()
            Int slashAt = remaining.indexOf("/")
            Int questionAt = remaining.indexOf("?")
            Int hashAt = remaining.indexOf("#")
            if slashAt >= 0 && slashAt < end { end = slashAt }
            if questionAt >= 0 && questionAt < end { end = questionAt }
            if hashAt >= 0 && hashAt < end { end = hashAt }
            String authority = remaining.substring(0, end)
            remaining = remaining.substring(end, remaining.length() - end)
            Int at = authority.indexOf("@")
            if at >= 0 {
                userInfo = authority.substring(0, at)
                authority = authority.substring(at + 1, authority.length() - at - 1)
            }
            Int portColon = authority.indexOf(":")
            if portColon >= 0 {
                host = authority.substring(0, portColon)
                String portText = authority.substring(portColon + 1, authority.length() - portColon - 1)
                Result<Int, Error> parsedPort = parseInt(portText)
                if !parsedPort.isOk() {
                    return Err(uriError(ErrorKind.InvalidArgument, "Uri.parse: invalid port"))
                }
                port = parsedPort.value()
                if port < 0 || port > 65535 {
                    return Err(uriError(ErrorKind.InvalidArgument, "Uri.parse: invalid port"))
                }
            } else {
                host = authority
            }
        }
        String path = remaining
        String? queryText = null
        String? fragment = null
        Int queryAt = path.indexOf("?")
        Int fragmentAt = path.indexOf("#")
        if fragmentAt >= 0 {
            fragment = path.substring(fragmentAt + 1, path.length() - fragmentAt - 1)
            path = path.substring(0, fragmentAt)
        }
        queryAt = path.indexOf("?")
        if queryAt >= 0 {
            queryText = path.substring(queryAt + 1, path.length() - queryAt - 1)
            path = path.substring(0, queryAt)
        }
        Query query = new Query()
        Bool hasQuery = queryText != null
        if queryText != null { query = Query.parseValue(queryText as String) }
        return Ok(new Uri(scheme, userInfo, host, port, path, query, hasQuery, fragment))
    }

    String? scheme() { return self._scheme }
    String? userInfo() { return self._userInfo }
    String? host() { return self._host }
    Int? port() { return self._port }
    String path() { return self._path }
    Query query() { return self._query.copy() }
    Bool hasQuery() { return self._hasQuery }
    String? fragment() { return self._fragment }
    Bool isAbsolute() { return self._scheme != null }

    String? authority() {
        if self._host == null { return null }
        String result = self._host as String
        if self._userInfo != null { result = (self._userInfo as String) + "@" + result }
        if self._port != null { result = result + ":" + str(self._port as Int) }
        return result
    }

    String text() {
        String result = ""
        if self._scheme != null { result = (self._scheme as String) + ":" }
        if self._host != null {
            result = result + "//" + self.authority()
        }
        result = result + self._path
        if self._hasQuery { result = result + "?" + self._query.encode() }
        if self._fragment != null { result = result + "#" + (self._fragment as String) }
        return result
    }

    Uri withScheme(String scheme) {
        if !isValidScheme(scheme) { throw "Uri.withScheme: invalid scheme" }
        return new Uri(scheme, self._userInfo, self._host, self._port, self._path, self._query.copy(), self._hasQuery, self._fragment)
    }
    Uri withUserInfo(String? userInfo) {
        return new Uri(self._scheme, userInfo, self._host, self._port, self._path, self._query.copy(), self._hasQuery, self._fragment)
    }
    Uri withHost(String host) {
        if host == null || host == "" { throw "Uri.withHost: empty host" }
        return new Uri(self._scheme, self._userInfo, host, self._port, self._path, self._query.copy(), self._hasQuery, self._fragment)
    }
    Uri withPort(Int? port) {
        if port != null && (port < 0 || port > 65535) { throw "Uri.withPort: invalid port" }
        return new Uri(self._scheme, self._userInfo, self._host, port, self._path, self._query.copy(), self._hasQuery, self._fragment)
    }
    Uri withPath(String path) {
        if path == null { throw "Uri.withPath: null path" }
        return new Uri(self._scheme, self._userInfo, self._host, self._port, path, self._query.copy(), self._hasQuery, self._fragment)
    }
    Uri withQuery(Query query) {
        if query == null { throw "Uri.withQuery: null query" }
        return new Uri(self._scheme, self._userInfo, self._host, self._port, self._path, query.copy(), true, self._fragment)
    }
    Uri withoutQuery() {
        return new Uri(self._scheme, self._userInfo, self._host, self._port, self._path, new Query(), false, self._fragment)
    }
    Uri withFragment(String? fragment) {
        return new Uri(self._scheme, self._userInfo, self._host, self._port, self._path, self._query.copy(), self._hasQuery, fragment)
    }
    Uri withoutFragment() {
        return new Uri(self._scheme, self._userInfo, self._host, self._port, self._path, self._query.copy(), self._hasQuery, null)
    }

    Result<Uri, Error> resolve(Uri reference) {
        if reference == null { throw "Uri.resolve: null reference" }
        if reference.isAbsolute() { return Ok(reference) }
        if reference.path().startsWith("/") {
            return Ok(new Uri(self._scheme, null, self._host, self._port, reference.path(), reference.query(), reference.hasQuery(), reference.fragment()))
        }
        String basePath = self._path
        Int slash = basePath.lastIndexOf("/")
        String directory = ""
        if slash >= 0 { directory = basePath.substring(0, slash + 1) }
        return Ok(new Uri(self._scheme, self._userInfo, self._host, self._port, directory + reference.path(), reference.query(), reference.hasQuery(), reference.fragment()))
    }

    Bool equals(Uri other) {
        if other == null { return false }
        return self.text() == other.text()
    }
    String toString() { return self.text() }
}
