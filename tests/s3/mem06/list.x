static Int main() {
    List<Int> xs = [1, 2, 3]
    Int removed = xs.remove(1)
    Int n = xs.length()
    xs.clear()
    print(removed + n + xs.length())
    return 0
}
