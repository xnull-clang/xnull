package app.http
import xdk.codec
import xdk.net.http

@Serializable
class CreateUser {
    String name
    Int age
    CreateUser(String name, Int age) {
        self.name = name
        self.age = age
    }
}

class UserApi {
    @HttpRoute("/users/{id}", HttpMethod.Get)
    HttpResponse getUser(String id, @Query("verbose") String? verbose, @Header("X-Token") String token) {
        String body = id + ":" + verbose + ":" + token
        return HttpResponse.of(200).withBody(HttpBody.fromText(body))
    }

    @HttpRoute("/users", HttpMethod.Post)
    HttpResponse create(@Body CreateUser body) {
        return HttpResponse.of(201).withBody(HttpBody.fromText(body.name + ":" + str(body.age)))
    }

    @HttpRoute("/search", HttpMethod.Get)
    HttpResponse search(@Query("limit") Int limit) {
        return HttpResponse.of(200).withBody(HttpBody.fromText(str(limit)))
    }

    @HttpRoute("/items/{itemId}", HttpMethod.Get)
    HttpResponse item(Int itemId) {
        return HttpResponse.of(200).withBody(HttpBody.fromText(str(itemId)))
    }

    @HttpRoute("/big/{value}", HttpMethod.Get)
    HttpResponse big(Long value) {
        return HttpResponse.of(200).withBody(HttpBody.fromText(str(value)))
    }

    @HttpRoute("/health", HttpMethod.Get)
    HttpResponse health() {
        return HttpResponse.of(204)
    }
}
