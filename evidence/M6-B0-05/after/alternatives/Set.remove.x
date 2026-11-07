static Int main() {
    Set<Int> s = [1]
    Set<Int> kept = []
    for x in s {
        if x != 1 {
            kept.add(x)
        }
    }
    s = kept
    print(s.has(1))
    return 0
}
