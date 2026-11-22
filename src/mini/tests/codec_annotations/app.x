package app.codec
import xdk.codec

@Serializable
class User {
    @JsonName("user_name")
    String name
    Int age
    Bool active
    User(String name, Int age, Bool active) {
        self.name = name
        self.age = age
        self.active = active
    }
}

@Serializable
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

@Serializable
class Wrapper {
    User user
    Wrapper(User user) {
        self.user = user
    }
}
