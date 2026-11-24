#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.jwt
import xdk.jwt
import xdk.errors

static Int main(String[] args) {
    String name = args.get(0)
    Bytes key = Bytes.fromString("secret")
    JwtHeader header = new JwtHeader(JwtAlgorithm.Hs256)
    JwtClaims claims = new JwtClaims()
    JwtOptions options = new JwtOptions()
    if name == "encodeHeader" {
        String token = Jwt.encode(null, claims, key).value()
    } else if name == "encodeClaims" {
        String token = Jwt.encode(header, null, key).value()
    } else if name == "decodeNull" {
        JwtToken token = Jwt.decode(null).value()
    } else if name == "verifyNull" {
        JwtClaims result = Jwt.verify("a.b.c", null, options).value()
    } else if name == "leeway" {
        options.leewaySeconds(-1)
    } else if name == "issuer" {
        options.issuer("")
    } else if name == "require" {
        options.require("")
    } else if name == "authNullSecret" {
        JwtAuthenticator auth = new JwtAuthenticator(null, new JwtOptions())
    } else if name == "authEmptySecret" {
        JwtAuthenticator auth = new JwtAuthenticator(Bytes.fromString(""), new JwtOptions())
    } else if name == "authNullOptions" {
        JwtAuthenticator auth = new JwtAuthenticator(Bytes.fromString("x"), null)
    } else if name == "authNullCredential" {
        JwtAuthenticator auth = new JwtAuthenticator(Bytes.fromString("x"), new JwtOptions())
        Context context = Context.background()
        Result<Principal, Error> result = auth.authenticate(context, null)
    } else if name == "claimSet" {
        claims.set(null, Json.string("x"))
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || { cat "$TMP/build.err" >&2; exit 1; }
check_panic() {
    name=$1
    marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && { echo "jwt panic: $name did not fail" >&2; exit 1; }
    grep -Fq "$marker" "$TMP/$name.err" || { echo "jwt panic: $name missing marker '$marker'" >&2; cat "$TMP/$name.err" >&2; exit 1; }
}
check_panic encodeHeader "Jwt.encode: null argument"
check_panic encodeClaims "Jwt.encode: null argument"
check_panic decodeNull "Jwt.decode: null"
check_panic verifyNull "Jwt.verify: null argument"
check_panic leeway "JwtOptions.leewaySeconds: negative"
check_panic issuer "JwtOptions.issuer: empty"
check_panic require "JwtOptions.require: empty"
check_panic claimSet "JwtClaims.set: null argument"
check_panic authNullSecret "JwtAuthenticator: null argument"
check_panic authEmptySecret "JwtAuthenticator: empty secret"
check_panic authNullOptions "JwtAuthenticator: null argument"
check_panic authNullCredential "JwtAuthenticator.authenticate: null argument"
echo "jwt_panic: PASS"
