import xdk.errors
import xdk.math
import xdk.net.http
import xdk.net.uri
import xdk.text

static Uri parseUri(String text) {
    return Uri.parse(text).value()
}

static String bodyText(HttpResponse response) {
    return response.body().readText(maxLongValue()).value()
}

static Int main(String[] args) {
    Int port = parseInt(args[0]).value()
    Int refused = parseInt(args[1]).value()
    String base = "http://127.0.0.1:" + str(port)
    Context context = Context.background()
    HttpClient client = new HttpClient()

    Result<HttpResponse, Error> hello = client.get(context, parseUri(base + "/hello"))
    print("hello=" + str(hello.value().status().code()) + "," + str(hello.value().isSuccess()) + "," + bodyText(hello.value()))
    Long? helloLength = hello.value().headers().contentLength()
    print("hello-length=" + str(helloLength != null) + "," + str(helloLength as Long))

    HttpBody payload = HttpBody.fromText("payload")
    Result<HttpResponse, Error> echo = client.post(context, parseUri(base + "/echo"), payload)
    print("echo=" + str(echo.value().status().code()) + "," + str(echo.value().isSuccess()) + "," + bodyText(echo.value()))

    HttpBody closedBody = HttpBody.fromText("closed")
    closedBody.close()
    Result<HttpResponse, Error> bodyResult = client.post(context, parseUri(base + "/echo"), closedBody)
    if bodyResult.isErr() {
        print("body-error=" + errorKindName(bodyResult.error().kind()))
    } else {
        print("body-error=ok")
    }

    Result<HttpResponse, Error> missing = client.get(context, parseUri(base + "/missing"))
    print("missing=" + str(missing.value().status().code()) + "," + str(missing.value().isSuccess()) + "," + bodyText(missing.value()))

    Result<HttpResponse, Error> refusedResult = client.get(context, parseUri("http://127.0.0.1:" + str(refused) + "/hello"))
    if refusedResult.isErr() {
        print("refused=" + errorKindName(refusedResult.error().kind()))
    } else {
        print("refused=ok")
    }

    Context cancelled = Context.background()
    cancelled.cancel()
    Result<HttpResponse, Error> cancelledResult = client.get(cancelled, parseUri(base + "/hello"))
    if cancelledResult.isErr() {
        print("cancel=" + errorKindName(cancelledResult.error().kind()))
    } else {
        print("cancel=ok")
    }

    Result<HttpResponse, Error> schemeResult = client.get(context, parseUri("https://127.0.0.1:" + str(port) + "/hello"))
    if schemeResult.isErr() {
        print("scheme=" + errorKindName(schemeResult.error().kind()))
    } else {
        print("scheme=ok")
    }

    HttpClientOptions options = new HttpClientOptions()
    options.baseUri(parseUri(base))
    HttpClient baseClient = new HttpClient(options)
    Result<HttpResponse, Error> baseResult = baseClient.get(context, parseUri("/hello"))
    print("base=" + str(baseResult.value().status().code()) + "," + str(baseResult.value().isSuccess()) + "," + bodyText(baseResult.value()))
    baseClient.close()

    Result<Unit, Error> firstClose = client.close()
    Result<Unit, Error> secondClose = client.close()
    Result<HttpResponse, Error> closedResult = client.get(context, parseUri(base + "/hello"))
    if closedResult.isErr() {
        print("close=" + str(firstClose.isOk()) + "," + str(secondClose.isOk()) + "," + str(client.isOpen()) + "," +
            errorKindName(closedResult.error().kind()))
    } else {
        print("close=ok")
    }
    print("base-option=" + str(options.baseUriOrNull() != null))
    return 0
}
