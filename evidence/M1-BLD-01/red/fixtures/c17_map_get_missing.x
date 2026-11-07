static Int main() {
    Map<String, Int> m = ["a": 1]
    print(m.get("missing"))
    print(m.get("missing") == null)
    if (m.get("missing") == null) {
        print("null")
    }
    return 0
}
