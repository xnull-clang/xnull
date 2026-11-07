static Int main() {
    List<String> l = ["a"]
    Map<String, Int> m = ["a": 1]
    print(m.getOr(l.get(0), 0))
    return 0
}
