static Int main() {
    List<Int> xs = [1]
    xs = [2]
    xs.push(3)
    print(xs is List)
    print(xs.length())
    return 0
}
