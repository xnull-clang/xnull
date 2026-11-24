#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.auth
import xdk.auth
import xdk.errors
import xdk.tasks

class Same implements Authenticator {
    final AuthScheme _scheme
    Same(AuthScheme scheme) { self._scheme = scheme }
    AuthScheme scheme() { return self._scheme }
    Result<Principal, Error> authenticate(Context context, Credential credential) {
        return Ok(Principal.authenticated("u", self._scheme))
    }
}

static Int main(String[] args) {
    String name = args.get(0)
    Context context = Context.background()
    if name == "credentialNull" {
        Credential value = new Credential(null, "x")
    } else if name == "credentialEmpty" {
        Credential value = new Credential(AuthScheme.Jwt, "")
    } else if name == "subject" {
        Principal value = Principal.authenticated("", AuthScheme.Jwt)
    } else if name == "anonymousScheme" {
        Principal value = Principal.authenticated("u", AuthScheme.Anonymous)
    } else if name == "serviceNull" {
        AuthService service = AuthService.create(null)
    } else if name == "serviceNullAuth" {
        List<Authenticator> values = []
        values.push(null)
        AuthService service = AuthService.create(values)
    } else if name == "duplicate" {
        List<Authenticator> values = []
        values.push(new Same(AuthScheme.Jwt))
        values.push(new Same(AuthScheme.Jwt))
        AuthService service = AuthService.create(values)
    } else if name == "authNull" {
        Credential credential = Credential.jwt("x")
        List<Authenticator> values = []
        AuthService service = AuthService.create(values)
        Result<Principal, Error> result = service.authenticate(null, credential)
    } else if name == "role" {
        Principal value = Principal.authenticated("u", AuthScheme.Jwt)
        Principal changed = value.withRole("")
    } else if name == "permission" {
        Principal value = Principal.authenticated("u", AuthScheme.Jwt)
        Principal changed = value.withPermission("")
    } else if name == "claim" {
        Principal value = Principal.authenticated("u", AuthScheme.Jwt)
        Principal changed = value.withClaim("k", null)
    } else if name == "parseNull" {
        Result<AuthScheme, Error> parsed = parseAuthScheme(null)
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || { cat "$TMP/build.err" >&2; exit 1; }
check_panic() {
    name=$1
    marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && { echo "auth panic: $name did not fail" >&2; exit 1; }
    grep -Fq "$marker" "$TMP/$name.err" || { echo "auth panic: $name missing '$marker'" >&2; cat "$TMP/$name.err" >&2; exit 1; }
}
check_panic credentialNull "Credential: null scheme"
check_panic credentialEmpty "Credential: empty value"
check_panic subject "Principal.authenticated: empty subject"
check_panic anonymousScheme "Principal.authenticated: invalid scheme"
check_panic serviceNull "AuthService.create: null list"
check_panic serviceNullAuth "AuthService.create: null authenticator"
check_panic duplicate "AuthService.create: duplicate scheme: jwt"
check_panic authNull "AuthService.authenticate: null argument"
check_panic role "Principal.withRole: empty"
check_panic permission "Principal.withPermission: empty"
check_panic claim "Principal.withClaim: invalid"
check_panic parseNull "parseAuthScheme: null"
echo "auth_panic: PASS"
