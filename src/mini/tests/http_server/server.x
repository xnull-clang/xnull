package app.httpserver
import xdk.errors
import xdk.fs
import xdk.net.http
import xdk.net.uri
import xdk.text

class EchoHandler implements HttpHandler {
    Result<Unit, Error> handle(Context context, HttpExchange exchange) {
        if exchange == null || context == null { throw "EchoHandler: null argument" }
        String path = exchange.request().uri().path()
        if path == "/hello" {
            HttpResponse response = HttpResponse.of(200)
            response = response.withBody(HttpBody.fromText("hello"))
            return exchange.respond(response)
        }
        if path == "/echo" {
            Result<String, Error> body = exchange.request().body().readText(65536)
            if body.isErr() {
                return exchange.respondStatus(500)
            }
            List<String> testValues = exchange.request().headers().getAll("X-Test")
            String summary = str(testValues.length()) + ":"
            Int headerIndex = 0
            while headerIndex < testValues.length() {
                if headerIndex > 0 { summary = summary + "," }
                summary = summary + testValues.get(headerIndex)
                headerIndex = headerIndex + 1
            }
            HttpResponse response = HttpResponse.of(200)
            response = response.withHeader("X-Test", summary)
            response = response.withBody(HttpBody.fromText(body.value() + "|" + summary))
            return exchange.respond(response)
        }
        if path == "/twice" {
            Result<Unit, Error> first = exchange.respond(HttpResponse.of(200))
            Result<Unit, Error> second = exchange.respond(HttpResponse.of(200))
            if first.isOk() && second.isErr() {
                print("respond-twice=true," + errorKindName(second.error().kind()))
            } else {
                print("respond-twice=false")
            }
            return Ok()
        }
        if path == "/unresponded" {
            return Ok()
        }
        HttpResponse missing = HttpResponse.of(404)
        missing = missing.withBody(HttpBody.fromText("missing"))
        return exchange.respond(missing)
    }
}

static Int main(String[] args) {
    Int port = parseInt(args[0]).value()
    Int maxRequests = parseInt(args[1]).value()
    String readyPath = args[2]
    Context context = Context.background()
    Result<HttpServer, Error> bound = HttpServer.bind(context, "127.0.0.1", port)
    if bound.isErr() {
        print("bind=" + errorKindName(bound.error().kind()))
        return 1
    }
    HttpServer server = bound.value()
    EchoHandler handler = new EchoHandler()
    Context cancelled = Context.background()
    cancelled.cancel()
    Result<Unit, Error> cancelledServe = server.serve(cancelled, handler, 1)
    if cancelledServe.isErr() {
        print("serve-cancel=true," + errorKindName(cancelledServe.error().kind()))
    } else {
        print("serve-cancel=false")
    }
    Result<Long, Error> ready = writeText(readyPath, "ready")
    if ready.isErr() {
        print("ready=false")
        return 1
    }
    Result<Unit, Error> served = server.serve(context, handler, maxRequests)
    print("served=" + str(served.isOk()))
    Result<Unit, Error> firstClose = server.close()
    Result<Unit, Error> secondClose = server.close()
    print("close=" + str(firstClose.isOk()) + "," + str(secondClose.isOk()) + "," + str(server.isOpen()))
    return 0
}
