static Int main() {
    Map<String, Int> m = ["a": 1]
    if m.has("z") {
        print(m.getOr("z", 0))
    } else {
        print("null")
    }
    return 0
}
