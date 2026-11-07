static Int main() {
    Map<String, Int> m = ["a": 1]
    Int? miss = m.get("z")
    print(miss == null)
    print(m.get("z") ?? 7)
    print(m.getOr("z", 9))
    print(m.get("a") ?? -1)
    print(m.getOr("a", -1))
    print(m.has("z"))
    print(m.remove("z"))
    print(m.remove("a"))
    print(m.length())
    return 0
}
