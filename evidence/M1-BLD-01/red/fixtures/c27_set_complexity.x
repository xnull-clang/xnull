static Int main() {
    Set<Int> s = []
    for i in 0..<20000 {
        s.add(i)
    }
    Int hit = 0
    for i in 0..<20000 {
        if (s.has(i)) {
            hit += 1
        }
    }
    for i in 0..<10000 {
        s.remove(i)
    }
    print(hit)
    print(s.length())
    return 0
}
