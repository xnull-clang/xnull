static Int main() {
    Map<String, Int> m = ["a": 1]
    m.remove("a")
    print(m.has("a"))
    return 0
}
