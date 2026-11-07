static Int main() {
    Map<String, Int> m = ["a": 1]
    print(m.getOr("a", 42))
    print(m.getOr("z", 42))
    print(m.getOr("z", 0))
    return 0
}
