package sema

import "testing"

// S4-01：xdk.errors 的 ErrorKind/Error 协议注册与实现检查。
func TestS4ErrorsProtocol(t *testing.T) {
	expectNone(t, `import xdk.errors
class E implements Error {
    ErrorKind kind() { return ErrorKind.Io }
    String describe() { return "io" }
}
static Int main() {
    E e = new E()
    Error x = e
    ErrorKind k = ErrorKind.Io
    return 0
}`)

	expectCode(t, `import xdk.errors
class E implements Error {
    ErrorKind kind() { return ErrorKind.Io }
}
static Int main() { return 0 }`, TyProtoImpl)

	expectCode(t, `import xdk.errors
class E implements Error {
    ErrorKind kind() { return ErrorKind.Io }
    String describe() { return "e" }
}
static Int main() {
    ErrorKind k = ErrorKind.Nope
    return 0
}`, TyEnumRule)
}
