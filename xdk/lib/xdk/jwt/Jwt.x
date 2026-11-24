package xdk.jwt
import xdk.errors
import xdk.bytes
import xdk.codec
import xdk.crypto
import xdk.runtime

enum JwtAlgorithm {
    Unknown,
    Hs256,
    Hs384,
    Hs512,
    Rs256,
    Rs384,
    Rs512,
    Ps256,
    Ps384,
    Ps512,
    Es256,
    Es384,
    EdDsa,
    Sm2Sm3,
}

String jwtAlgorithmName(JwtAlgorithm algorithm) {
    if algorithm == JwtAlgorithm.Hs256 { return "HS256" }
    if algorithm == JwtAlgorithm.Hs384 { return "HS384" }
    if algorithm == JwtAlgorithm.Hs512 { return "HS512" }
    if algorithm == JwtAlgorithm.Rs256 { return "RS256" }
    if algorithm == JwtAlgorithm.Rs384 { return "RS384" }
    if algorithm == JwtAlgorithm.Rs512 { return "RS512" }
    if algorithm == JwtAlgorithm.Ps256 { return "PS256" }
    if algorithm == JwtAlgorithm.Ps384 { return "PS384" }
    if algorithm == JwtAlgorithm.Ps512 { return "PS512" }
    if algorithm == JwtAlgorithm.Es256 { return "ES256" }
    if algorithm == JwtAlgorithm.Es384 { return "ES384" }
    if algorithm == JwtAlgorithm.EdDsa { return "EdDSA" }
    if algorithm == JwtAlgorithm.Sm2Sm3 { return "SM2-SM3" }
    return "unknown"
}

JwtAlgorithm jwtAlgorithmFromText(String text) {
    if text == null { throw "parseJwtAlgorithm: null" }
    String value = text.toUpper()
    if value == "HS256" { return JwtAlgorithm.Hs256 }
    if value == "HS384" { return JwtAlgorithm.Hs384 }
    if value == "HS512" { return JwtAlgorithm.Hs512 }
    if value == "RS256" { return JwtAlgorithm.Rs256 }
    if value == "RS384" { return JwtAlgorithm.Rs384 }
    if value == "RS512" { return JwtAlgorithm.Rs512 }
    if value == "PS256" { return JwtAlgorithm.Ps256 }
    if value == "PS384" { return JwtAlgorithm.Ps384 }
    if value == "PS512" { return JwtAlgorithm.Ps512 }
    if value == "ES256" { return JwtAlgorithm.Es256 }
    if value == "ES384" { return JwtAlgorithm.Es384 }
    if value == "EDDSA" { return JwtAlgorithm.EdDsa }
    if value == "SM2-SM3" { return JwtAlgorithm.Sm2Sm3 }
    return JwtAlgorithm.Unknown
}

Result<JwtAlgorithm, Error> parseJwtAlgorithm(String text) {
    if text == null { throw "parseJwtAlgorithm: null" }
    JwtAlgorithm algorithm = jwtAlgorithmFromText(text)
    if algorithm == JwtAlgorithm.Unknown {
        return Err(jwtError(ErrorKind.InvalidArgument, "unsupported JWT algorithm: " + text))
    }
    return Ok(algorithm)
}

static Error jwtError(ErrorKind kind, String message) {
    BasicError error = new BasicError(kind, message)
    return error
}

static Bool jwtSameText(String? left, String? right) {
    if left == null && right == null { return true }
    if left == null || right == null { return false }
    String leftText = left as String
    String rightText = right as String
    return leftText == rightText
}

static JsonValue jwtObjectValue(JsonObject object) {
    JsonValue value = Json.object()
    JsonObject target = value.asObject() as JsonObject
    List<String> keys = object.keys()
    Int index = 0
    while index < keys.length() {
        String key = keys.get(index)
        JsonValue? item = object.getOrNull(key)
        if item != null { target.set(key, item as JsonValue) }
        index = index + 1
    }
    return value
}

class JwtHeader {
    final JwtAlgorithm _algorithm
    final String _type
    final String? _keyId

    JwtHeader(JwtAlgorithm algorithm) {
        if algorithm == null || algorithm == JwtAlgorithm.Unknown { throw "JwtHeader: null algorithm" }
        self._algorithm = algorithm
        self._type = "JWT"
        self._keyId = null
    }

    JwtHeader(JwtAlgorithm algorithm, String type, String? keyId) {
        if algorithm == null || algorithm == JwtAlgorithm.Unknown { throw "JwtHeader: null algorithm" }
        if type == null || type == "" { throw "JwtHeader: empty type" }
        self._algorithm = algorithm
        self._type = type
        self._keyId = keyId
    }

    JwtAlgorithm algorithm() { return self._algorithm }
    String type() { return self._type }
    String? keyId() { return self._keyId }
}

class JwtClaims {
    final JsonObject _claims

    JwtClaims() {
        self._claims = new JsonObject()
    }

    JwtClaims(JsonObject claims) {
        if claims == null { throw "JwtClaims: null" }
        self._claims = claims.copy()
    }

    Void set(String name, JsonValue value) {
        if name == null || value == null { throw "JwtClaims.set: null argument" }
        self._claims.set(name, value)
    }

    JsonValue? getOrNull(String name) {
        if name == null { throw "JwtClaims.getOrNull: null name" }
        return self._claims.getOrNull(name)
    }

    Result<String, Error> string(String name) {
        JsonValue? value = self.getOrNull(name)
        if value == null { return Err(jwtError(ErrorKind.NotFound, "claim missing: " + name)) }
        JsonValue actual = value as JsonValue
        if !actual.isString() { return Err(jwtError(ErrorKind.InvalidArgument, "claim is not string: " + name)) }
        return Ok(actual.asString() as String)
    }

    Result<Long, Error> longValue(String name) {
        JsonValue? value = self.getOrNull(name)
        if value == null { return Err(jwtError(ErrorKind.NotFound, "claim missing: " + name)) }
        JsonValue actual = value as JsonValue
        if !actual.isNumber() { return Err(jwtError(ErrorKind.InvalidArgument, "claim is not number: " + name)) }
        JsonNumber number = actual.asNumber() as JsonNumber
        return number.asLong()
    }

    String? subject() {
        Result<String, Error> value = self.string("sub")
        if value.isErr() { return null }
        return value.value()
    }

    String? issuer() {
        Result<String, Error> value = self.string("iss")
        if value.isErr() { return null }
        return value.value()
    }

    String? jwtId() {
        Result<String, Error> value = self.string("jti")
        if value.isErr() { return null }
        return value.value()
    }

    List<String> audiences() {
        JsonValue? value = self.getOrNull("aud")
        List<String> result = []
        if value == null { return result }
        JsonValue actual = value as JsonValue
        if actual.isString() {
            result.push(actual.asString() as String)
            return result
        }
        if actual.isArray() {
            JsonArray array = actual.asArray() as JsonArray
            Int index = 0
            while index < array.length() {
                JsonValue item = array.get(index)
                if item.isString() { result.push(item.asString() as String) }
                index = index + 1
            }
        }
        return result
    }

    Long? expiresAtSeconds() {
        Result<Long, Error> value = self.longValue("exp")
        if value.isErr() { return null }
        return value.value()
    }

    Long? notBeforeSeconds() {
        Result<Long, Error> value = self.longValue("nbf")
        if value.isErr() { return null }
        return value.value()
    }

    Long? issuedAtSeconds() {
        Result<Long, Error> value = self.longValue("iat")
        if value.isErr() { return null }
        return value.value()
    }

    Bool isExpired(Long nowSeconds, Long leewaySeconds) {
        Long? exp = self.expiresAtSeconds()
        if exp == null { return false }
        return nowSeconds - leewaySeconds >= (exp as Long)
    }

    JsonObject toJson() { return self._claims.copy() }
    JwtClaims copy() { return new JwtClaims(self._claims) }
}

class JwtOptions {
    Long _leewaySeconds
    String? _issuer
    String? _audience
    List<String> _requiredClaims
    Bool _verifyExpiration
    Bool _verifyNotBefore

    JwtOptions() {
        self._leewaySeconds = 0
        self._issuer = null
        self._audience = null
        self._requiredClaims = []
        self._verifyExpiration = true
        self._verifyNotBefore = true
    }

    JwtOptions leewaySeconds(Long value) {
        if value < 0 { throw "JwtOptions.leewaySeconds: negative" }
        self._leewaySeconds = value
        return self
    }

    JwtOptions issuer(String value) {
        if value == null || value == "" { throw "JwtOptions.issuer: empty" }
        self._issuer = value
        return self
    }

    JwtOptions audience(String value) {
        if value == null || value == "" { throw "JwtOptions.audience: empty" }
        self._audience = value
        return self
    }

    JwtOptions require(String claim) {
        if claim == null || claim == "" { throw "JwtOptions.require: empty" }
        self._requiredClaims.push(claim)
        return self
    }

    JwtOptions verifyExpiration(Bool value) {
        self._verifyExpiration = value
        return self
    }

    JwtOptions verifyNotBefore(Bool value) {
        self._verifyNotBefore = value
        return self
    }

    Long getLeewaySeconds() { return self._leewaySeconds }
    String? getIssuer() { return self._issuer }
    String? getAudience() { return self._audience }
    List<String> getRequiredClaims() { return self._requiredClaims.copy() }
    Bool isVerifyExpiration() { return self._verifyExpiration }
    Bool isVerifyNotBefore() { return self._verifyNotBefore }

    JwtOptions copy() {
        JwtOptions result = new JwtOptions()
        result.leewaySeconds(self._leewaySeconds)
        if self._issuer != null { result.issuer(self._issuer as String) }
        if self._audience != null { result.audience(self._audience as String) }
        Int index = 0
        while index < self._requiredClaims.length() {
            result.require(self._requiredClaims.get(index))
            index = index + 1
        }
        result.verifyExpiration(self._verifyExpiration)
        result.verifyNotBefore(self._verifyNotBefore)
        return result
    }
}

class JwtToken {
    final JwtHeader _header
    final JwtClaims _claims
    final Bytes _signature
    final String _raw

    JwtToken(JwtHeader header, JwtClaims claims, Bytes signature, String raw) {
        if header == null || claims == null || signature == null || raw == null {
            throw "JwtToken: null argument"
        }
        self._header = header
        self._claims = claims.copy()
        self._signature = copy(signature)
        self._raw = raw
    }

    JwtHeader header() { return self._header }
    JwtClaims claims() { return self._claims.copy() }
    Bytes signature() { return copy(self._signature) }
    String raw() { return self._raw }
}

class Jwt {
    private Jwt() { }

    static Result<String, Error> encode(JwtHeader header, JwtClaims claims, Bytes secret) {
        if header == null || claims == null || secret == null { throw "Jwt.encode: null argument" }
        if header.algorithm() != JwtAlgorithm.Hs256 {
            return Err(jwtError(ErrorKind.Unsupported, "JWT algorithm is not supported: " + jwtAlgorithmName(header.algorithm())))
        }
        JsonValue headerValue = Json.object()
        JsonObject headerJson = headerValue.asObject() as JsonObject
        headerJson.set("alg", Json.string("HS256"))
        headerJson.set("typ", Json.string(header.type()))
        if header.keyId() != null { headerJson.set("kid", Json.string(header.keyId() as String)) }
        JsonValue claimsValue = jwtObjectValue(claims.toJson())
        String headerText = Base64.encodeBytes(Bytes.fromString(Json.stringify(headerValue)), true, false)
        String claimsText = Base64.encodeBytes(Bytes.fromString(Json.stringify(claimsValue)), true, false)
        String signingInput = headerText + "." + claimsText
        Bytes signature = Hmac.sign(HashAlgorithm.Sha256, secret, Bytes.fromString(signingInput))
        String signatureText = Base64.encodeBytes(signature, true, false)
        return Ok(signingInput + "." + signatureText)
    }

    static Result<JwtToken, Error> decode(String token) {
        if token == null { throw "Jwt.decode: null" }
        List<String> parts = token.split(".")
        if parts.length() != 3 { return Err(jwtError(ErrorKind.DataCorrupted, "JWT: expected three segments")) }
        if parts.get(0) == "" || parts.get(1) == "" || parts.get(2) == "" {
            return Err(jwtError(ErrorKind.DataCorrupted, "JWT: empty segment"))
        }
        Result<Bytes, Error> headerBytes = Base64.decodeText(parts.get(0), true, false)
        if headerBytes.isErr() { return Err(jwtError(ErrorKind.DataCorrupted, "JWT: invalid header base64url")) }
        Result<Bytes, Error> claimsBytes = Base64.decodeText(parts.get(1), true, false)
        if claimsBytes.isErr() { return Err(jwtError(ErrorKind.DataCorrupted, "JWT: invalid claims base64url")) }
        Result<Bytes, Error> signatureBytes = Base64.decodeText(parts.get(2), true, false)
        if signatureBytes.isErr() { return Err(jwtError(ErrorKind.DataCorrupted, "JWT: invalid signature base64url")) }
        Result<JsonValue, Error> headerParsed = Json.parse(headerBytes.value().toString())
        if headerParsed.isErr() || !headerParsed.value().isObject() {
            return Err(jwtError(ErrorKind.DataCorrupted, "JWT: invalid header JSON"))
        }
        Result<JsonValue, Error> claimsParsed = Json.parse(claimsBytes.value().toString())
        if claimsParsed.isErr() || !claimsParsed.value().isObject() {
            return Err(jwtError(ErrorKind.DataCorrupted, "JWT: invalid claims JSON"))
        }
        JsonObject headerJson = headerParsed.value().asObject() as JsonObject
        JsonValue? algRaw = headerJson.getOrNull("alg")
        if algRaw == null { return Err(jwtError(ErrorKind.DataCorrupted, "JWT: missing alg")) }
        JsonValue algNode = algRaw as JsonValue
        if !algNode.isString() { return Err(jwtError(ErrorKind.DataCorrupted, "JWT: invalid alg")) }
        String algValue = algNode.asString() as String
        JwtAlgorithm resolvedAlgorithm = jwtAlgorithmFromText(algValue)
        if resolvedAlgorithm == JwtAlgorithm.Unknown {
            return Err(jwtError(ErrorKind.DataCorrupted, "JWT: invalid alg"))
        }
        String type = "JWT"
        JsonValue? typeRaw = headerJson.getOrNull("typ")
        if typeRaw != null {
            JsonValue typeNode = typeRaw as JsonValue
            if typeNode.isString() { type = typeNode.asString() as String }
        }
        String? keyId = null
        JsonValue? kidRaw = headerJson.getOrNull("kid")
        if kidRaw != null {
            JsonValue kidNode = kidRaw as JsonValue
            if kidNode.isString() { keyId = kidNode.asString() as String }
        }
        JwtHeader header = new JwtHeader(resolvedAlgorithm, type, keyId)
        JsonObject claimsJson = claimsParsed.value().asObject() as JsonObject
        JwtClaims claims = new JwtClaims(claimsJson)
        return Ok(new JwtToken(header, claims, signatureBytes.value(), token))
    }

    static Result<JwtClaims, Error> verify(String token, Bytes secret, JwtOptions options) {
        if token == null || secret == null || options == null { throw "Jwt.verify: null argument" }
        Result<JwtToken, Error> parsed = Jwt.decode(token)
        if parsed.isErr() { return Err(parsed.error()) }
        JwtToken value = parsed.value()
        JwtClaims claims = value.claims()
        if value.header().algorithm() != JwtAlgorithm.Hs256 {
            return Err(jwtError(ErrorKind.Unsupported, "JWT algorithm is not supported: " + jwtAlgorithmName(value.header().algorithm())))
        }
        List<String> parts = token.split(".")
        String signingInput = parts.get(0) + "." + parts.get(1)
        Bytes expected = Hmac.sign(HashAlgorithm.Sha256, secret, Bytes.fromString(signingInput))
        if !ConstantTime.equals(expected, value.signature()) {
            return Err(jwtError(ErrorKind.PermissionDenied, "JWT signature verification failed"))
        }
        JwtOptions checked = options.copy()
        Long now = nowWall() / 1000
        Long? exp = claims.expiresAtSeconds()
        if checked.isVerifyExpiration() && exp != null {
            if claims.isExpired(now, checked.getLeewaySeconds()) {
                return Err(jwtError(ErrorKind.PermissionDenied, "JWT token expired"))
            }
        }
        Long? nbf = claims.notBeforeSeconds()
        if checked.isVerifyNotBefore() && nbf != null {
            if (nbf as Long) > now + checked.getLeewaySeconds() {
                return Err(jwtError(ErrorKind.PermissionDenied, "JWT token not yet valid"))
            }
        }
        String? expectedIssuer = checked.getIssuer()
        if expectedIssuer != null {
            JwtClaims issuerClaims = Jwt.decode(token).value().claims()
            String? actualIssuer = issuerClaims.issuer()
            if !jwtSameText(actualIssuer, expectedIssuer) {
                return Err(jwtError(ErrorKind.PermissionDenied, "JWT issuer mismatch"))
            }
        }
        String? expectedAudience = checked.getAudience()
        if expectedAudience != null {
            List<String> audiences = claims.audiences()
            String expectedText = expectedAudience as String
            Bool found = false
            Int index = 0
            while index < audiences.length() {
                String item = audiences.get(index)
                if item == expectedText { found = true }
                index = index + 1
            }
            if !found { return Err(jwtError(ErrorKind.PermissionDenied, "JWT audience mismatch")) }
        }
        List<String> required = checked.getRequiredClaims()
        Int index = 0
        while index < required.length() {
            if claims.getOrNull(required.get(index)) == null {
                return Err(jwtError(ErrorKind.NotFound, "JWT required claim missing: " + required.get(index)))
            }
            index = index + 1
        }
        return Ok(claims.copy())
    }
}
