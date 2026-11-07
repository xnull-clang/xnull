static Int main() {
    Map<String, Int> m = ["a": 1]
    if m.has("a") {
        print(m.getOr("a", 0))
    }
    return 0
}
