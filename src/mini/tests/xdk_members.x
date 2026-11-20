static Int main() {
    List<Int> items = [1, 2, 3]
    items.clear()
    print(items.length())

    Set<Int> seen = Set.of(1, 2, 3)
    print(seen.remove(2))
    print(seen.length())
    seen.clear()
    print(seen.length())

    Map<String, Int> map = [:]
    map.put("a", 1)
    map.clear()
    print(map.length())
    return 0
}
