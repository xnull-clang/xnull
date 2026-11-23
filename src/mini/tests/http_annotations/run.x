package app.http
import xdk.net.http
import generated.CodecGenerated
import generated.HttpGenerated

class CreateUser {
    String name
    Int age
    CreateUser(String name, Int age) {
        self.name = name
        self.age = age
    }
}

class UserApi {
    HttpResponse getUser(String id, String? verbose, String token) {
        String suffix = "none"
        if verbose != null {
            suffix = verbose as String
        }
        return HttpResponse.of(200).withBody(HttpBody.fromText(id + ":" + suffix + ":" + token))
    }

    HttpResponse create(CreateUser body) {
        return HttpResponse.of(201).withBody(HttpBody.fromText(body.name + ":" + str(body.age)))
    }

    HttpResponse search(Int limit) {
        return HttpResponse.of(200).withBody(HttpBody.fromText(str(limit)))
    }

    HttpResponse item(Int itemId) {
        return HttpResponse.of(200).withBody(HttpBody.fromText(str(itemId)))
    }

    HttpResponse big(Long value) {
        return HttpResponse.of(200).withBody(HttpBody.fromText(str(value)))
    }

    HttpResponse health() {
        return HttpResponse.of(204)
    }
}

static Uri uriOf(String text) {
    return Uri.parse(text).value()
}

static String bodyOf(HttpResponse response) {
    if response.body().isEmpty() { return "" }
    return response.body().readText(4096).value()
}

static Int main() {
    UserApiRouter router = new UserApiRouter(new UserApi())
    print("matches=" + str(router.matches(HttpMethod.Get, "/users/42")) + "," + str(router.matches(HttpMethod.Post, "/users/42")) + "," + str(router.matches(HttpMethod.Get, "/missing")))

    HttpRequest getRequest = new HttpRequest(HttpMethod.Get, uriOf("http://localhost/users/42?verbose=yes"))
    getRequest = getRequest.withHeader("X-Token", "t1")
    HttpResponse getResponse = router.dispatch(getRequest)
    print("get=" + str(getResponse.status().code()) + "," + bodyOf(getResponse))

    HttpRequest noVerbose = new HttpRequest(HttpMethod.Get, uriOf("http://localhost/users/7"))
    noVerbose = noVerbose.withHeader("X-Token", "t2")
    print("optional=" + bodyOf(router.dispatch(noVerbose)))

    HttpRequest noHeader = new HttpRequest(HttpMethod.Get, uriOf("http://localhost/users/42"))
    HttpResponse noHeaderResponse = router.dispatch(noHeader)
    print("missing-header=" + str(noHeaderResponse.status().code()) + "," + bodyOf(noHeaderResponse))

    HttpRequest createRequest = new HttpRequest(HttpMethod.Post, uriOf("http://localhost/users"))
    createRequest = createRequest.withBody(HttpBody.fromText("{\"name\":\"Ada\",\"age\":30}"))
    HttpResponse createResponse = router.dispatch(createRequest)
    print("create=" + str(createResponse.status().code()) + "," + bodyOf(createResponse))

    HttpRequest badBody = new HttpRequest(HttpMethod.Post, uriOf("http://localhost/users"))
    badBody = badBody.withBody(HttpBody.fromText("{\"name\":"))
    HttpResponse badBodyResponse = router.dispatch(badBody)
    print("bad-body=" + str(badBodyResponse.status().code()) + "," + bodyOf(badBodyResponse))

    HttpRequest searchRequest = new HttpRequest(HttpMethod.Get, uriOf("http://localhost/search?limit=5"))
    print("query=" + bodyOf(router.dispatch(searchRequest)))
    HttpRequest missingQuery = new HttpRequest(HttpMethod.Get, uriOf("http://localhost/search"))
    HttpResponse missingQueryResponse = router.dispatch(missingQuery)
    print("missing-query=" + str(missingQueryResponse.status().code()) + "," + bodyOf(missingQueryResponse))
    HttpRequest badQuery = new HttpRequest(HttpMethod.Get, uriOf("http://localhost/search?limit=x"))
    HttpResponse badQueryResponse = router.dispatch(badQuery)
    print("bad-query=" + str(badQueryResponse.status().code()) + "," + bodyOf(badQueryResponse))

    HttpRequest encodedSpace = new HttpRequest(HttpMethod.Get, uriOf("http://localhost/users/A%20B"))
    encodedSpace = encodedSpace.withHeader("X-Token", "enc")
    print("path-space=" + bodyOf(router.dispatch(encodedSpace)))
    HttpRequest encodedChinese = new HttpRequest(HttpMethod.Get, uriOf("http://localhost/users/%E4%B8%AD"))
    encodedChinese = encodedChinese.withHeader("X-Token", "enc")
    print("path-chinese=" + bodyOf(router.dispatch(encodedChinese)))
    HttpRequest encodedSlash = new HttpRequest(HttpMethod.Get, uriOf("http://localhost/users/A%2FB"))
    encodedSlash = encodedSlash.withHeader("X-Token", "enc")
    print("path-slash=" + bodyOf(router.dispatch(encodedSlash)))
    HttpRequest badPercent = new HttpRequest(HttpMethod.Get, uriOf("http://localhost/users/%ZZ"))
    badPercent = badPercent.withHeader("X-Token", "enc")
    HttpResponse badPercentResponse = router.dispatch(badPercent)
    print("path-bad=" + str(badPercentResponse.status().code()) + "," + bodyOf(badPercentResponse))
    HttpRequest truncatedPercent = new HttpRequest(HttpMethod.Get, uriOf("http://localhost/users/%E4"))
    truncatedPercent = truncatedPercent.withHeader("X-Token", "enc")
    HttpResponse truncatedResponse = router.dispatch(truncatedPercent)
    print("path-truncated=" + str(truncatedResponse.status().code()) + "," + bodyOf(truncatedResponse))

    HttpRequest itemRequest = new HttpRequest(HttpMethod.Get, uriOf("http://localhost/items/7"))
    print("path-int=" + bodyOf(router.dispatch(itemRequest)))
    HttpRequest badItem = new HttpRequest(HttpMethod.Get, uriOf("http://localhost/items/x"))
    print("path-int-bad=" + str(router.dispatch(badItem).status().code()))

    HttpRequest notFound = new HttpRequest(HttpMethod.Get, uriOf("http://localhost/nope"))
    print("not-found=" + str(router.dispatch(notFound).status().code()))

    HttpRequest wrongMethod = new HttpRequest(HttpMethod.Post, uriOf("http://localhost/users/42"))
    HttpResponse wrongMethodResponse = router.dispatch(wrongMethod)
    String? allowValue = methodAllow(wrongMethodResponse)
    String allow = allowValue as String
    print("method=" + str(wrongMethodResponse.status().code()) + "," + allow)

    HttpRequest bigRequest = new HttpRequest(HttpMethod.Get, uriOf("http://localhost/big/9000000000"))
    print("path-long=" + bodyOf(router.dispatch(bigRequest)))
    HttpRequest badBig = new HttpRequest(HttpMethod.Get, uriOf("http://localhost/big/x"))
    print("path-long-bad=" + str(router.dispatch(badBig).status().code()))
    HttpRequest maxBig = new HttpRequest(HttpMethod.Get, uriOf("http://localhost/big/9223372036854775807"))
    print("path-long-max=" + bodyOf(router.dispatch(maxBig)))
    HttpRequest minBig = new HttpRequest(HttpMethod.Get, uriOf("http://localhost/big/-9223372036854775808"))
    print("path-long-min=" + bodyOf(router.dispatch(minBig)))
    HttpRequest overBig = new HttpRequest(HttpMethod.Get, uriOf("http://localhost/big/9223372036854775808"))
    print("path-long-over=" + str(router.dispatch(overBig).status().code()))
    HttpRequest underBig = new HttpRequest(HttpMethod.Get, uriOf("http://localhost/big/-9223372036854775809"))
    print("path-long-under=" + str(router.dispatch(underBig).status().code()))
    HttpRequest emptyBig = new HttpRequest(HttpMethod.Get, uriOf("http://localhost/big/"))
    print("path-long-empty=" + str(router.dispatch(emptyBig).status().code()))
    HttpRequest plusBig = new HttpRequest(HttpMethod.Get, uriOf("http://localhost/big/+1"))
    print("path-long-plus=" + str(router.dispatch(plusBig).status().code()))
    HttpRequest junkBig = new HttpRequest(HttpMethod.Get, uriOf("http://localhost/big/1x"))
    print("path-long-junk=" + str(router.dispatch(junkBig).status().code()))

    HttpRequest healthRequest = new HttpRequest(HttpMethod.Get, uriOf("http://localhost/health"))
    print("health=" + str(router.dispatch(healthRequest).status().code()))
    return 0
}

static String? methodAllow(HttpResponse response) {
    return response.headers().getOrNull("Allow")
}
