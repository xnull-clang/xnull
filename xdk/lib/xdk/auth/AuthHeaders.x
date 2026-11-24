package xdk.auth
import xdk.errors

class AuthHeaders {
    private AuthHeaders() { }

    static Result<Credential, Error> bearer(String header) {
        if header == null { return Err(new BasicError(ErrorKind.InvalidArgument, "missing Authorization header")) }
        String text = header.trim()
        if !text.toLower().startsWith("bearer ") {
            return Err(new BasicError(ErrorKind.InvalidArgument, "Authorization must use Bearer scheme"))
        }
        String token = text.substring(7, text.length() - 7).trim()
        if token == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "empty Bearer token"))
        }
        return Ok(Credential.jwt(token))
    }

    static Credential apiKey(String value) {
        if value == null || value == "" { throw "AuthHeaders.apiKey: empty value" }
        return Credential.apiKey(value)
    }
}
