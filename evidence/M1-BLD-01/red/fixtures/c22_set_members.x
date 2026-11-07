static Int main() {
    Set<Int> s = [3, 1, 3]
    print(s.length())
    print(s.add(2))
    print(s.add(1))
    print(s.has(2))
    print(s.at(0))
    print(s.remove(3))
    print(s.remove(99))
    for x in s {
        print(x)
    }
    s.clear()
    print(s.length())
    return 0
}
