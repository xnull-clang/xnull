package xdk2.api
import xdk.api
import xdk.errors
import xdk.codec
import xdk.net.http
import xdk.validate
import xdk.time

static Int main() {
    ProblemDetails notFound = ProblemDetails.of(404)
    ProblemDetails detailed = notFound.withType("urn:example:not-found")
        .withDetail("missing")
        .withInstance("/users/42")
        .extension("request_id", Json.string("abc"))
    JsonObject json = detailed.toJson()
    JsonValue typeValue = json.getOr("type", Json.nullValue())
    String typeText = typeValue.asString() as String
    print("problem=" + str(notFound.status()) + "," + notFound.title() + "," +
        str(notFound.isClientError()) + "," + str(notFound.isServerError()) + "," +
        typeText + "," +
        str(json.has("detail")) + "," + str(json.has("instance")) + "," +
        str(json.has("request_id")) + "," + detailed.describe())

    List<ValidationError> validationErrors = [new ValidationError("name", "required", "name is required")]
    ProblemDetails validationProblem = ProblemDetails.fromValidation(validationErrors)
    JsonObject validationJson = validationProblem.toJson()
    JsonValue? errorsValue = validationJson.getOrNull("errors")
    JsonValue actualErrors = errorsValue as JsonValue
    JsonArray errorsArray = actualErrors.asArray() as JsonArray
    print("validation=" + str(validationProblem.status()) + "," +
        validationProblem.title() + "," + str(errorsArray.length()) + "," +
        str(validationProblem.copy().equals(validationProblem)))

    print("auth=" + authSchemeName(AuthScheme.Basic) + "," +
        authSchemeName(AuthScheme.ApiKeyQuery) + "," +
        authSchemeOpenApiType(AuthScheme.Bearer) + "," +
        authSchemeOpenApiLocation(AuthScheme.ApiKeyCookie) + "," +
        authSchemeOpenApiLocation(AuthScheme.Bearer) + "," +
        authSchemeChallenge(AuthScheme.Basic, "") + "," +
        authSchemeChallenge(AuthScheme.Basic, "api") + "," +
        authSchemeChallenge(AuthScheme.Bearer, "x") + "," +
        authSchemeChallenge(AuthScheme.ApiKeyHeader, ""))

    CorsPolicy cors = new CorsPolicy()
    cors.allowOrigin("https://app.example").allowOrigin("https://admin.example")
    cors.allowMethod(HttpMethod.Post).allowHeader("Content-Type").allowHeader("Authorization")
    cors.exposeHeader("X-Rate-Limit").allowCredentials(true).maxAgeSeconds(600 as Long)
    print("cors=" + str(cors.isOriginAllowed("https://app.example")) + "," +
        str(cors.isOriginAllowed("https://other.example")) + "," +
        str(cors.allowedMethods().length()) + "," + str(cors.isHeaderAllowed("content-type")) +
        "," + str(cors.isAllowCredentials()) + "," + str(cors.getMaxAgeSeconds()))
    Map<String, String> actual = cors.actualHeaders("https://app.example")
    print("cors-actual=" + actual.getOr("Access-Control-Allow-Origin", "") + "," +
        actual.getOr("Access-Control-Allow-Credentials", "") + "," +
        actual.getOr("Access-Control-Expose-Headers", ""))
    List<String> requestedHeaders = ["Content-Type"]
    Map<String, String> preflight = cors.preflightHeaders("https://app.example",
        HttpMethod.Post, requestedHeaders)
    Map<String, String> rejected = cors.preflightHeaders("https://other.example",
        HttpMethod.Post, requestedHeaders)
    List<String> forbiddenHeaders = ["X-Unknown"]
    Map<String, String> forbidden = cors.preflightHeaders("https://app.example",
        HttpMethod.Post, forbiddenHeaders)
    print("cors-preflight=" + str(preflight.keys().length() > 0) + "," +
        preflight.getOr("Access-Control-Allow-Methods", "") + "," +
        preflight.getOr("Access-Control-Max-Age", "") + "," +
        str(rejected.keys().length()) + "," + str(forbidden.keys().length()))

    RateLimitPolicy rate = new RateLimitPolicy(2, 50 as Long)
    Bool first = rate.allow("client")
    Bool second = rate.allow("client")
    Bool third = rate.allow("client")
    Bool other = rate.allow("other")
    sleepMs(60 as Long)
    Bool afterWindow = rate.allow("client")
    print("rate=" + str(first) + "," + str(second) + "," + str(third) + "," +
        str(other) + "," + str(afterWindow) + "," + str(rate.limit()) + "," +
        str(rate.windowMillis()) + "," + str(rate.isIncludeRoute()))

    RateLimitPolicy bounded = new RateLimitPolicy(5, 1000 as Long)
    bounded.withMaximumKeys(1)
    Bool keyOne = bounded.allow("one")
    Bool keyTwo = bounded.allow("two")
    boolTestPrint(keyOne, keyTwo)
    RateLimitPolicy rateCopy = rate.copy()
    print("rate-copy=" + str(rateCopy.allow("client")) + "," + str(rateCopy.limit()) + "," +
        str(rateCopy.getMaximumKeys()))
    return 0
}

static Void boolTestPrint(Bool keyOne, Bool keyTwo) {
    print("rate-keys=" + str(keyOne) + "," + str(keyTwo))
}
