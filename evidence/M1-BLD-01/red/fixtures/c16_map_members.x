static Int main() {
    Map<String, Int> m = ["b": 2, "a": 1]
    m.put("c", 3)
    print(m.get("a"))
    print(m.getOr("z", 99))
    print(m.has("b"))
    print(m.remove("a"))
    print(m.has("a"))
    print(m.length())
    print(m.keys().join(","))
    print(m.values().join(","))
    m.clear()
    print(m.length())
    print([:].length())
    return 0
}
