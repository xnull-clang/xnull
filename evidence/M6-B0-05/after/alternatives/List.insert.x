static Int main() {
    List<Int> l = [1, 3]
    l.push(0)
    Int i = l.length() - 1
    while i > 1 {
        l.set(i, l.get(i - 1))
        i = i - 1
    }
    l.set(1, 2)
    print(l.get(1))
    print(l.length())
    return 0
}
