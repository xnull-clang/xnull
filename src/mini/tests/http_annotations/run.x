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

    HttpRequest healthRequest = new HttpRequest(HttpMethod.Get, uriOf("http://localhost/health"))
    print("health=" + str(router.dispatch(healthRequest).status().code()))
    return 0
}

static String? methodAllow(HttpResponse response) {
    return response.headers().getOrNull("Allow")
}
