static Int main() {
    Set<Int> s = [1]
    s = [2]
    print(s is Set)
    s.add(3)
    print(s.length())
    return 0
}
