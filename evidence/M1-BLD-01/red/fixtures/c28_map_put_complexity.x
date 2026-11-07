static Int main() {
    Map<Int, Int> m = [:]
    for i in 0..<200000 {
        m.put(i, i)
    }
    print(m.length())
    return 0
}
