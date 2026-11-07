static Int main() {
    Map<String, Int> m = ["a": 1, "b": 2]
    Set<Int> s = [1, 2, 2, 3]
    print(m.get("a") + m.get("b") + s.length())
    return 0
}
