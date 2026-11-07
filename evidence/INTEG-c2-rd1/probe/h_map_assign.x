static Int main() {
    Map<String, Int> m = ["a": 1]
    m = ["b": 2]
    print(m is Map)
    print(m.getOr("b", -1))
    return 0
}
