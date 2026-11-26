#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/api-panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.api
import xdk.api
import xdk.codec
import xdk.net.http
import xdk.validate

static Int main(String[] args) {
    String name = args.get(0)
    if name == "problemStatusLow" {
        ProblemDetails value = ProblemDetails.of(99)
    } else if name == "problemStatusHigh" {
        ProblemDetails value = ProblemDetails.of(600)
    } else if name == "problemTypeEmpty" {
        ProblemDetails value = ProblemDetails.of(400).withType("")
    } else if name == "problemTypeMultiline" {
        ProblemDetails value = ProblemDetails.of(400).withType("a\nb")
    } else if name == "problemTitleEmpty" {
        ProblemDetails value = ProblemDetails.of(400).withTitle("")
    } else if name == "problemTitleMultiline" {
        ProblemDetails value = ProblemDetails.of(400).withTitle("a\rb")
    } else if name == "problemDetailNull" {
        ProblemDetails value = ProblemDetails.of(400).withDetail(null)
    } else if name == "problemInstanceNull" {
        ProblemDetails value = ProblemDetails.of(400).withInstance(null)
    } else if name == "problemExtensionEmpty" {
        ProblemDetails value = ProblemDetails.of(400).extension("", Json.string("x"))
    } else if name == "problemExtensionReserved" {
        ProblemDetails value = ProblemDetails.of(400).extension("status", Json.string("x"))
    } else if name == "problemExtensionNull" {
        ProblemDetails value = ProblemDetails.of(400).extension("x", null)
    } else if name == "problemValidationNull" {
        ProblemDetails value = ProblemDetails.fromValidation(null)
    } else if name == "authRealmNull" {
        String value = authSchemeChallenge(AuthScheme.Basic, null)
    } else if name == "authRealmQuote" {
        String value = authSchemeChallenge(AuthScheme.Basic, "a\"b")
    } else if name == "authRealmBackslash" {
        String value = authSchemeChallenge(AuthScheme.Basic, "a\\b")
    } else if name == "authRealmNewline" {
        String value = authSchemeChallenge(AuthScheme.Basic, "a\nb")
    } else if name == "corsOriginEmpty" {
        CorsPolicy policy = new CorsPolicy()
        CorsPolicy value = policy.allowOrigin("")
    } else if name == "corsOriginMultiline" {
        CorsPolicy policy = new CorsPolicy()
        CorsPolicy value = policy.allowOrigin("a\nb")
    } else if name == "corsOriginsNull" {
        CorsPolicy policy = new CorsPolicy()
        CorsPolicy value = policy.allowOrigins(null)
    } else if name == "corsWildcardCredentials" {
        CorsPolicy policy = new CorsPolicy()
        policy.allowAnyOrigin()
        CorsPolicy value = policy.allowCredentials(true)
    } else if name == "corsCredentialsWildcard" {
        CorsPolicy policy = new CorsPolicy()
        policy.allowCredentials(true)
        CorsPolicy value = policy.allowAnyOrigin()
    } else if name == "corsHeaderInvalid" {
        CorsPolicy policy = new CorsPolicy()
        CorsPolicy value = policy.allowHeader("bad header")
    } else if name == "corsExposeInvalid" {
        CorsPolicy policy = new CorsPolicy()
        CorsPolicy value = policy.exposeHeader("bad\nheader")
    } else if name == "corsMaxAge" {
        CorsPolicy policy = new CorsPolicy()
        CorsPolicy value = policy.maxAgeSeconds(-1 as Long)
    } else if name == "rateLimit" {
        RateLimitPolicy value = new RateLimitPolicy(0, 1000 as Long)
    } else if name == "rateWindow" {
        RateLimitPolicy value = new RateLimitPolicy(1, 0 as Long)
    } else if name == "rateKeyHeader" {
        RateLimitPolicy policy = new RateLimitPolicy(1, 1000 as Long)
        RateLimitPolicy value = policy.withKeyHeader("")
    } else if name == "rateMaximumKeys" {
        RateLimitPolicy policy = new RateLimitPolicy(1, 1000 as Long)
        RateLimitPolicy value = policy.withMaximumKeys(0)
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || { cat "$TMP/build.err" >&2; exit 1; }
check_panic() {
    name=$1; marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && { echo "api panic: $name did not fail" >&2; exit 1; }
    grep -Fq "$marker" "$TMP/$name.err" || { echo "api panic: $name missing '$marker'" >&2; cat "$TMP/$name.err" >&2; exit 1; }
}
check_panic problemStatusLow "ProblemDetails: invalid status"
check_panic problemStatusHigh "ProblemDetails: invalid status"
check_panic problemTypeEmpty "ProblemDetails.withType: empty type"
check_panic problemTypeMultiline "ProblemDetails.withType: multiline"
check_panic problemTitleEmpty "ProblemDetails.withTitle: empty title"
check_panic problemTitleMultiline "ProblemDetails.withTitle: multiline"
check_panic problemDetailNull "ProblemDetails.withDetail: null"
check_panic problemInstanceNull "ProblemDetails.withInstance: null"
check_panic problemExtensionEmpty "ProblemDetails.extension: empty name"
check_panic problemExtensionReserved "ProblemDetails.extension: reserved name"
check_panic problemExtensionNull "ProblemDetails.extension: null value"
check_panic problemValidationNull "ProblemDetails.fromValidation: null errors"
check_panic authRealmNull "authSchemeChallenge: null realm"
check_panic authRealmQuote "authSchemeChallenge: invalid realm"
check_panic authRealmBackslash "authSchemeChallenge: invalid realm"
check_panic authRealmNewline "authSchemeChallenge: invalid realm"
check_panic corsOriginEmpty "CorsPolicy.allowOrigin: empty origin"
check_panic corsOriginMultiline "CorsPolicy.allowOrigin: multiline origin"
check_panic corsOriginsNull "CorsPolicy.allowOrigins: null"
check_panic corsWildcardCredentials "CorsPolicy.allowCredentials: wildcard already configured"
check_panic corsCredentialsWildcard "CorsPolicy.allowOrigin: wildcard with credentials"
check_panic corsHeaderInvalid "CorsPolicy.allowHeader: invalid name"
check_panic corsExposeInvalid "CorsPolicy.exposeHeader: invalid name"
check_panic corsMaxAge "CorsPolicy.maxAgeSeconds: invalid"
check_panic rateLimit "RateLimitPolicy: invalid limit or window"
check_panic rateWindow "RateLimitPolicy: invalid limit or window"
check_panic rateKeyHeader "RateLimitPolicy.withKeyHeader: invalid"
check_panic rateMaximumKeys "RateLimitPolicy.withMaximumKeys: invalid"
echo "api_panic: PASS"
