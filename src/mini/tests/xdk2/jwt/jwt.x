package xdk2.jwt
import xdk.jwt
import xdk.errors
import xdk.codec
import xdk.runtime
import xdk.time

static Bytes secretBytes() { return Bytes.fromString("your-256-bit-secret") }

static JwtHeader hs256(String kid) {
    return new JwtHeader(JwtAlgorithm.Hs256, "JWT", kid)
}

static JwtClaims claimsWith(String subject) {
    JwtClaims claims = new JwtClaims()
    claims.set("sub", Json.string(subject))
    return claims
}

static String tokenFor(JwtClaims claims, Bytes key) {
    JwtHeader header = new JwtHeader(JwtAlgorithm.Hs256)
    Result<String, Error> encoded = Jwt.encode(header, claims, key)
    return encoded.value()
}

static Int main() {
    String rfc = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
    Result<JwtToken, Error> parsed = Jwt.decode(rfc)
    JwtToken token = parsed.value()
    print("rfc=" + str(parsed.isOk()) + "," + jwtAlgorithmName(token.header().algorithm()) + "," +
        token.header().type() + "," + str(token.claims().subject()) + "," + str(token.claims().issuedAtSeconds()) + "," +
        str(token.signature().length()))

    Bytes key = secretBytes()
    JwtClaims claims = claimsWith("user-1")
    claims.set("iss", Json.string("issuer-a"))
    claims.set("jti", Json.string("id-1"))
    claims.set("iat", Json.number("1700000000"))
    JsonValue audience = Json.array()
    JsonArray audienceArray = audience.asArray() as JsonArray
    audienceArray.add(Json.string("api"))
    audienceArray.add(Json.string("web"))
    claims.set("aud", audience)
    String encoded = tokenFor(claims, key)
    List<String> parts = encoded.split(".")
    print("encode=" + str(parts.length()) + "," + str(encoded.indexOf("=") < 0) + "," +
        str(encoded.startsWith("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9")))
    Result<JwtToken, Error> decoded = Jwt.decode(encoded)
    JwtToken roundtrip = decoded.value()
    print("roundtrip=" + str(roundtrip.claims().subject()) + "," +
        str(roundtrip.claims().audiences().length()) + "," + roundtrip.claims().audiences().get(0) + "," +
        roundtrip.claims().audiences().get(1))

    JwtOptions options = new JwtOptions()
    options.issuer("issuer-a")
    options.audience("api")
    Result<JwtClaims, Error> verified = Jwt.verify(encoded, key, options)
    print("verify=" + str(verified.isOk()) + "," + str(verified.value().subject()) + "," +
        str(verified.value().jwtId()))
    Result<JwtClaims, Error> wrongKey = Jwt.verify(encoded, Bytes.fromString("wrong"), options)
    print("wrong-key=" + str(wrongKey.isErr()) + "," + errorKindName(wrongKey.error().kind()))
    String tampered = parts.get(0) + "." + Base64.encodeBytes(Bytes.fromString("{\"sub\":\"evil\"}"), true, false) + "." +
        parts.get(2)
    Result<JwtClaims, Error> tamperedResult = Jwt.verify(tampered, key, options)
    print("tampered=" + str(tamperedResult.isErr()) + "," +
        errorKindName(tamperedResult.error().kind()))

    JwtHeader hs384 = new JwtHeader(JwtAlgorithm.Hs384)
    Result<String, Error> unsupported = Jwt.encode(hs384, claims, key)
    print("unsupported-encode=" + str(unsupported.isErr()) + "," +
        errorKindName(unsupported.error().kind()))
    String forgedHeader = Base64.encodeBytes(Bytes.fromString("{\"alg\":\"HS384\",\"typ\":\"JWT\"}"), true, false)
    String forgedClaims = Base64.encodeBytes(Bytes.fromString("{\"sub\":\"x\"}"), true, false)
    String forged = forgedHeader + "." + forgedClaims + ".AA"
    Result<JwtClaims, Error> unsupportedVerify = Jwt.verify(forged, key, options)
    print("unsupported-verify=" + str(unsupportedVerify.isErr()) + "," +
        errorKindName(unsupportedVerify.error().kind()))

    JwtOptions basicOptions = new JwtOptions()
    Long now = nowWall() / 1000
    JwtClaims expiring = claimsWith("exp")
    expiring.set("exp", Json.number(str(now + 100)))
    String expiringToken = tokenFor(expiring, key)
    Result<JwtClaims, Error> fresh = Jwt.verify(expiringToken, key, basicOptions)
    print("exp-fresh=" + str(fresh.isOk()) + "," + str(expiring.isExpired(now, 0)))
    JwtClaims expired = claimsWith("expired")
    expired.set("exp", Json.number(str(now - 100)))
    String expiredToken = tokenFor(expired, key)
    Result<JwtClaims, Error> stale = Jwt.verify(expiredToken, key, basicOptions)
    print("exp-stale=" + str(stale.isErr()) + "," + errorKindName(stale.error().kind()) + "," +
        str(expired.isExpired(now, 0)) + "," + str(expired.isExpired(now, 200)))
    JwtOptions noExp = new JwtOptions()
    noExp.verifyExpiration(false)
    Result<JwtClaims, Error> staleAllowed = Jwt.verify(expiredToken, key, noExp)
    print("exp-disabled=" + str(staleAllowed.isOk()))

    JwtClaims future = claimsWith("nbf")
    future.set("nbf", Json.number(str(now + 100)))
    String futureToken = tokenFor(future, key)
    Result<JwtClaims, Error> tooEarly = Jwt.verify(futureToken, key, basicOptions)
    JwtOptions leeway = new JwtOptions()
    leeway.leewaySeconds(200)
    Result<JwtClaims, Error> leewayOk = Jwt.verify(futureToken, key, leeway)
    print("nbf=" + str(tooEarly.isErr()) + "," + errorKindName(tooEarly.error().kind()) + "," +
        str(leewayOk.isOk()))

    JwtOptions wrongIssuer = new JwtOptions()
    wrongIssuer.issuer("issuer-b")
    Result<JwtClaims, Error> issuerMismatch = Jwt.verify(encoded, key, wrongIssuer)
    JwtOptions wrongAudience = new JwtOptions()
    wrongAudience.audience("mobile")
    Result<JwtClaims, Error> audienceMismatch = Jwt.verify(encoded, key, wrongAudience)
    JwtOptions required = new JwtOptions()
    required.require("scope")
    Result<JwtClaims, Error> missing = Jwt.verify(encoded, key, required)
    print("claims-check=" + errorKindName(issuerMismatch.error().kind()) + "," +
        errorKindName(audienceMismatch.error().kind()) + "," + errorKindName(missing.error().kind()))

    print("bad2=" + errorKindName(Jwt.decode("a.b").error().kind()) + "," +
        errorKindName(Jwt.decode("a.b.c.d").error().kind()) + "," +
        errorKindName(Jwt.decode("!!.e30.AA").error().kind()) + "," +
        errorKindName(Jwt.decode(Base64.encodeBytes(Bytes.fromString("not-json"), true, false) + ".e30.AA").error().kind()))
    print("alg=" + jwtAlgorithmName(JwtAlgorithm.Hs256) + "," + jwtAlgorithmName(JwtAlgorithm.EdDsa) + "," +
        str(parseJwtAlgorithm("hs256").isOk()) + "," + str(parseJwtAlgorithm("none").isErr()))
    return 0
}
