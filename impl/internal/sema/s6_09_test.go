package sema

import "testing"

// S6-09：xdk.net socket plain/Async + net.http 子包签名。
func TestS609NetSignatures(t *testing.T) {
	// socket 面：只导入 xdk.net。
	expectNone(t, `import xdk.net
import xdk.tasks
import xdk.errors

@tasks
static Int main() {
    Context c = Context.background()
    Result<Socket, Error> s = connect("example.com", 80)
    Socket sock = s.value()
    Result<Int, Error> n = sock.readAsync(c, Bytes.fromString("x"))
    Result<Int, Error> w = connectAsync(c, "example.com", 80).value().write(Bytes.fromString("x"))
    Result<void, Error> cl = sock.close()

    Result<Listener, Error> l = bind("0.0.0.0", 8080)
    Result<Socket, Error> a = l.value().acceptAsync(c)
    Result<void, Error> lc = l.value().close()
    return n.value()
}`)

	// HTTP 面：只导入 xdk.net.http；HttpResponse 必须由子包再导出。
	expectNone(t, `import xdk.net.http
import xdk.tasks
import xdk.errors
@tasks
static Int main() {
    Context c = Context.background()
    Bytes body = Bytes.fromString("")
    Result<HttpResponse, ErrorKind> r = httpRequestAsync(c, "GET", "http://example.com", 80, "/", body)
    HttpResponse resp = r.value()
    print(httpStatus(resp))
    print(httpBodyText(resp))
    print(httpResponseClose(resp))
    var g = getAsync(c, "http://example.com")
    return 0
}`)

	// 子包符号导入。
	expectNone(t, `import xdk.net.http.getAsync
import xdk.tasks
@tasks
static Int main() {
    Context c = Context.background()
    var r = getAsync(c, "http://example.com")
    return 0
}`)
}

func TestS609NetNegative(t *testing.T) {
	expectCode(t, `import xdk.net
static Int main() { Result<Socket, Error> s = connect(1, 80); return 0 }`, TyAssignability)
	expectCode(t, `import xdk.net
import xdk.errors
static Int main() { Result<Socket, Error> s = connectAsync("h", 80); return 0 }`, TyAssignability)
	expectCode(t, `import xdk.net.http
import xdk.errors
static Int main() { Result<Response, Error> r = getAsync("http://x"); return 0 }`, TyAssignability)
	expectCode(t, `import xdk.net
static Int f(Socket s) { s.nope(); return 0 }`, TyXdkUnsupported)
	expectCode(t, `import xdk.net.http.nope
static Int main() { return 0 }`, ResNotFound)
}
