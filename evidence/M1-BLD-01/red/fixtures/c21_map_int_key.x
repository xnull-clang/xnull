static Int main() {
    Map<Int, String> m = [1: "one"]
    m.put(2, "two")
    print(m.get(1))
    print(m.getOr(3, "none"))
    print(m.keys().join(","))
    return 0
}
