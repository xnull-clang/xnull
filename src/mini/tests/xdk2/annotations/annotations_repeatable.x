@Target(Type)
@Repeatable
@annotation Tag {
    final String value = ""
}

@Tag("first")
@Tag("second")
@Tag("third")
class Tagged {
}

static Int main() {
    print("repeatable")
    return 0
}
