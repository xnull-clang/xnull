package app.codec
import xdk.codec
import generated.CodecGenerated

// Mirrors app.x with plain classes: annotations are only needed by the processor.
class User {
    String name
    Int age
    Bool active
    User(String name, Int age, Bool active) {
        self.name = name
        self.age = age
        self.active = active
    }
}

class Profile {
    String display_name
    Long score
    Double ratio
    Profile(String display_name, Long score, Double ratio) {
        self.display_name = display_name
        self.score = score
        self.ratio = ratio
    }
}

class Wrapper {
    User user
    Wrapper(User user) {
        self.user = user
    }
}

static Int main() {
    User user = new User("Ada", 30, true)
    JsonValue encoded = UserToJson(user)
    print("name=" + Json.getString(encoded, "user_name").value())
    print("age=" + str(Json.getInt(encoded, "age").value()))
    print("active=" + str(Json.getBool(encoded, "active").value()))
    JsonObject encodedObject = encoded.asObject() as JsonObject
    print("field-count=" + str(encodedObject.length()))

    Result<User, Error> decoded = UserFromJson(encoded)
    print("roundtrip=" + str(decoded.isOk()))
    User roundtrip = decoded.value()
    print("value=" + roundtrip.name + "," + str(roundtrip.age) + "," + str(roundtrip.active))

    Profile profile = new Profile("Ada", 1234567890123, 1.5)
    JsonValue profileJson = ProfileToJson(profile)
    print("default-name=" + Json.getString(profileJson, "displayname").value())
    JsonValue? scoreValue = Json.get(profileJson, "score")
    JsonValue scoreJson = scoreValue as JsonValue
    print("long=" + str(scoreJson.isNumber()))
    Result<Profile, Error> profileBack = ProfileFromJson(profileJson)
    print("profile=" + profileBack.value().display_name + "," + str(profileBack.value().score) + "," + str(profileBack.value().ratio))

    Wrapper wrapper = new Wrapper(user)
    JsonValue wrapperJson = WrapperToJson(wrapper)
    Result<Wrapper, Error> wrapperBack = WrapperFromJson(wrapperJson)
    print("nested=" + wrapperBack.value().user.name)

    Result<JsonValue, Error> missingJson = Json.parse("{\"age\":1,\"active\":true}")
    Result<User, Error> missingUser = UserFromJson(missingJson.value())
    print("missing-err=" + str(missingUser.isErr()))
    String missingMessage = missingUser.error().describe()
    print("missing-name=" + str(missingMessage.indexOf("user_name") >= 0))

    Result<JsonValue, Error> wrongTypeJson = Json.parse("{\"user_name\":1,\"age\":1,\"active\":true}")
    Result<User, Error> wrongTypeUser = UserFromJson(wrongTypeJson.value())
    print("type-err=" + str(wrongTypeUser.isErr()))
    String typeMessage = wrongTypeUser.error().describe()
    print("type-name=" + str(typeMessage.indexOf("user_name") >= 0))

    Result<JsonValue, Error> extraJson = Json.parse("{\"user_name\":\"X\",\"age\":2,\"active\":false,\"extra\":1}")
    Result<User, Error> extraUser = UserFromJson(extraJson.value())
    print("unknown-ignored=" + extraUser.value().name + "," + str(extraUser.value().age))

    print("non-object=" + str(UserFromJson(Json.number("1")).isErr()))
    return 0
}
