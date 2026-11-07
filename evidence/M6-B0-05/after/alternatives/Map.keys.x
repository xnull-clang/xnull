static Int main() {
    Map<String, Int> m = ["a": 1]
    List<String> keys = ["a"]
    m.put("b", 2)
    keys.push("b")
    print(keys.length())
    print(keys.get(0))
    return 0
}
