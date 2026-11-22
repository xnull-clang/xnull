package xdk2.http
import xdk.net.http
import xdk.net.uri
import xdk.errors

static Uri uriOf(String text) {
    return Uri.parse(text).value()
}

static Int main() {
    // ---- method / version ----
    print("method=" + httpMethodName(HttpMethod.Get) + "," + httpMethodName(HttpMethod.Connect))
    Result<HttpMethod, Error> methodResult = parseHttpMethod("post")
    HttpMethod parsedMethod = methodResult.value() as HttpMethod
    print("method-parse=" + httpMethodName(parsedMethod))
    print("method-bad=" + str(parseHttpMethod("FOO").isErr()))
    print("version=" + httpVersionName(HttpVersion.Http10) + "," + httpVersionName(HttpVersion.Http2))
    Result<HttpVersion, Error> versionResult = parseHttpVersion("http/2.0")
    HttpVersion parsedVersion = versionResult.value() as HttpVersion
    print("version-parse=" + httpVersionName(parsedVersion))
    print("version-bad=" + str(parseHttpVersion("HTTP/3").isErr()))

    // ---- status ----
    print("samesite=" + sameSiteName(parseSameSite("strict").value() as SameSite) + "," + str(parseSameSite("bad").isErr()))
    HttpStatus ok = HttpStatus.of(200)
    HttpStatus missing = HttpStatus.of(404)
    print("status=" + str(ok.code()) + "," + ok.reason() + "," + ok.toString())
    print("status-class=" + str(HttpStatus.of(100).isInformational()) + "," + str(ok.isSuccess()) + "," + str(HttpStatus.of(302).isRedirect()) + "," + str(missing.isClientError()) + "," + str(HttpStatus.of(500).isServerError()))
    print("status-equals=" + str(ok.equals(HttpStatus.of(200))) + "," + str(ok.equals(missing)))
    print("status-unknown=" + str(HttpStatus.of(599).reason() == "") + "," + HttpStatus.of(599).toString())

    HttpHeader sampleHeader = new HttpHeader("X-Test", "value")
    HttpHeader sameHeader = new HttpHeader("X-Test", "value")
    print("header=" + str(sampleHeader.equals(sameHeader)) + "," + sampleHeader.toString())

    // ---- headers ----
    HttpHeaders headers = new HttpHeaders()
    headers.add("Content-Type", "text/plain")
    headers.add("Accept", "text/plain")
    headers.add("accept", "application/json")
    headers.set("User-Agent", "xdk-test")
    headers.set("Content-Length", "5")
    print("headers-len=" + str(headers.length()))
    String? contentTypeHeader = headers.getOrNull("CONTENT-TYPE")
    String contentTypeText = contentTypeHeader as String
    print("headers-get=" + str(contentTypeText == "text/plain"))
    print("headers-all=" + str(headers.getAll("Accept").length()) + "," + headers.getAll("accept").get(1))
    print("headers-getor=" + headers.getOr("missing", "fallback"))
    print("headers-has=" + str(headers.has("ACCEPT")) + "," + str(headers.has("missing")))
    print("headers-entries=" + str(headers.entries().length()))
    MediaType? contentType = headers.contentType()
    MediaType media = contentType as MediaType
    print("headers-content-type=" + media.type() + "/" + media.subtype())
    Long? contentLengthValue = headers.contentLength()
    Long contentLength = contentLengthValue as Long
    String? userAgentValue = headers.userAgent()
    String userAgent = userAgentValue as String
    print("headers-content-length=" + str(contentLength))
    print("headers-user-agent=" + userAgent)
    HttpHeaders copied = headers.copy()
    copied.remove("Accept")
    print("headers-copy=" + str(copied.length()) + "," + str(headers.length()))
    headers.set("Accept", "text/html")
    String? acceptValue = headers.getOrNull("accept")
    String accept = acceptValue as String
    print("headers-set=" + str(headers.getAll("Accept").length()) + "," + accept)
    headers.clear()
    print("headers-clear=" + str(headers.length()))

    // ---- body ----
    HttpBody body = HttpBody.fromText("hello")
    print("body-empty=" + str(HttpBody.empty().isEmpty()) + "," + str(body.isEmpty()))
    Long? bodyLengthValue = body.contentLength()
    Long bodyLength = bodyLengthValue as Long
    print("body-length=" + str(bodyLength))
    Result<Bytes, Error> readResult = body.readAll(5)
    Bytes readBytes = readResult.value()
    String readBytesText = readBytes.toString()
    print("body-read=" + readBytesText)
    print("body-read-limit=" + str(body.readAll(4).isErr()))
    print("body-text=" + body.readText(5).value())
    Bytes? bodyBytesValue = body.bytes()
    Bytes bodyBytes = bodyBytesValue as Bytes
    String bodyBytesText = bodyBytes.toString()
    print("body-bytes=" + bodyBytesText)
    print("body-close=" + str(body.close().isOk()) + "," + str(body.close().isOk()))
    print("body-closed-read=" + str(body.readAll(5).isErr()))
    HttpBody emptyBody = HttpBody.empty()
    Long? emptyLengthValue = emptyBody.contentLength()
    Long emptyLength = emptyLengthValue as Long
    print("body-empty-length=" + str(emptyLength))

    // ---- request ----
    Uri target = uriOf("https://example.com/api/items?q=1")
    HttpRequest request = new HttpRequest(HttpMethod.Post, target)
    print("request-base=" + httpMethodName(request.method()) + "," + httpVersionName(request.version()) + "," + str(request.headers().length()) + "," + str(request.body().isEmpty()))
    HttpRequest withHeader = request.withHeader("X-Test", "one")
    print("request-with-header=" + str(withHeader.headers().has("x-test")) + "," + str(request.headers().has("x-test")))
    HttpHeaders requestHeaders = new HttpHeaders()
    requestHeaders.add("Accept", "application/json")
    HttpRequest withHeaders = request.withHeaders(requestHeaders)
    print("request-with-headers=" + str(withHeaders.headers().length()) + "," + str(request.headers().length()))
    HttpRequest withBody = request.withBody(HttpBody.fromText("x"))
    print("request-with-body=" + str(withBody.body().isEmpty()) + "," + str(request.body().isEmpty()))
    HttpRequest withVersion = request.withVersion(HttpVersion.Http2)
    print("request-with-version=" + httpVersionName(withVersion.version()) + "," + httpVersionName(request.version()))
    HttpRequest withUri = request.withUri(uriOf("https://example.com/other"))
    print("request-with-uri=" + withUri.uri().path())

    // ---- response ----
    HttpResponse created = HttpResponse.of(201)
    print("response=" + str(created.status().code()) + "," + created.status().reason() + "," + str(created.isSuccess()))
    HttpResponse notFound = created.withStatus(404)
    print("response-with-status=" + str(notFound.status().code()) + "," + str(notFound.isClientError()) + "," + str(created.isSuccess()))
    HttpResponse withResponseHeader = created.withHeader("Location", "/x")
    print("response-with-header=" + str(withResponseHeader.headers().has("location")) + "," + str(created.headers().has("location")))
    HttpResponse withResponseBody = created.withBody(HttpBody.fromText("ok"))
    print("response-with-body=" + str(withResponseBody.body().isEmpty()) + "," + str(created.body().isEmpty()))

    // ---- server options ----
    HttpServerOptions options = new HttpServerOptions()
    print("options=" + str(options.getMaxHeaderBytes()) + "," + str(options.getMaxBodyBytes()) + "," + str(options.isKeepAlive()) + "," + str(options.isHttp2()))
    options.maxHeaderBytes(1024)
    options.maxBodyBytes(2048)
    options.readTimeoutMillis(100)
    options.writeTimeoutMillis(200)
    options.keepAlive(false)
    options.maxConnections(4)
    options.http2(true)
    print("options-set=" + str(options.getMaxHeaderBytes()) + "," + str(options.getMaxBodyBytes()) + "," + str(options.getReadTimeoutMillis()) + "," + str(options.getWriteTimeoutMillis()) + "," + str(options.isKeepAlive()) + "," + str(options.getMaxConnections()) + "," + str(options.isHttp2()))
    HttpServerOptions optionsCopy = options.copy()
    optionsCopy.maxHeaderBytes(77)
    print("options-copy=" + str(optionsCopy.getMaxHeaderBytes()) + "," + str(options.getMaxHeaderBytes()))

    // ---- form ----
    Result<Form, Error> parsedForm = Form.parse("a=1&b=two+words&a=3&empty=")
    Form form = parsedForm.value()
    print("form-len=" + str(form.length()) + "," + str(form.getAll("a").length()))
    String? formAValue = form.getOrNull("a")
    String formA = formAValue as String
    print("form-values=" + formA + "," + form.getOr("b", "x") + "," + form.getOr("empty", "x") + "," + form.getOr("missing", "fallback"))
    print("form-encode=" + form.encode())
    print("form-body=" + form.toBody().readText(64).value())
    form.set("a", "9")
    String? formSetValue = form.getOrNull("a")
    String formSet = formSetValue as String
    print("form-set=" + str(form.getAll("a").length()) + "," + formSet)
    Form formCopy = form.copy()
    formCopy.clear()
    print("form-copy=" + str(formCopy.length()) + "," + str(form.length()))
    print("form-remove=" + str(form.remove("a")) + "," + str(form.length()))
    print("form-bad=" + str(Form.parse("a=%ZZ").isErr()))

    // ---- cookie ----
    Result<Cookie, Error> setCookie = Cookie.parseSetCookie("sid=abc; Domain=example.com; Path=/app; Secure; HttpOnly; SameSite=Lax; Max-Age=0")
    Cookie cookie = setCookie.value()
    print("cookie=" + cookie.name() + "," + cookie.value() + "," + cookie.domain() + "," + cookie.path())
    print("cookie-flags=" + str(cookie.isSecure()) + "," + str(cookie.isHttpOnly()) + "," + sameSiteName(cookie.sameSiteValue()) + "," + str(cookie.expiresValue()))
    print("cookie-header=" + cookie.headerValue())
    print("cookie-match=" + str(cookie.matches(uriOf("https://example.com/app/x"))) + "," + str(cookie.matches(uriOf("http://example.com/app/x"))) + "," + str(cookie.matches(uriOf("https://other.com/app/x"))) + "," + str(cookie.matches(uriOf("https://example.com/other"))))
    Result<List<Cookie>, Error> cookies = Cookie.parseCookieHeader("a=1; b=2")
    print("cookie-list=" + str(cookies.value().length()) + "," + cookies.value().get(1).name())
    print("cookie-list-bad=" + str(Cookie.parseCookieHeader("bad").isErr()))

    // ---- cookie jar ----
    CookieJar jar = new CookieJar()
    Cookie plain = Cookie.parseSetCookie("a=1; Domain=example.com; Path=/").value()
    Cookie otherCookie = Cookie.parseSetCookie("b=2; Domain=example.com; Path=/").value()
    Cookie expired = Cookie.parseSetCookie("old=1; Domain=example.com; Path=/; Max-Age=0").value()
    jar.store(plain)
    jar.store(otherCookie)
    jar.store(expired)
    Cookie replaced = Cookie.parseSetCookie("a=9; Domain=example.com; Path=/").value()
    jar.store(replaced)
    print("jar-len=" + str(jar.length()))
    String? jarHeaderValue = jar.headerForRequest(uriOf("https://example.com/x"))
    String jarHeader = jarHeaderValue as String
    print("jar-header=" + jarHeader)
    print("jar-miss=" + str(jar.headerForRequest(uriOf("https://other.com/x")) == null))
    print("jar-expired=" + str(jar.removeExpired(1)) + "," + str(jar.length()))
    String? cleanHeaderValue = jar.headerForRequest(uriOf("https://example.com/x"))
    String cleanHeader = cleanHeaderValue as String
    print("jar-header-clean=" + cleanHeader)
    jar.clear()
    print("jar-clear=" + str(jar.length()))
    return 0
}
