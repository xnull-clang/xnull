static Int main() {
    List<Int> xs = [1, 2]
    xs.push(3)
    xs.insert(1, 9)
    xs.set(0, 7)
    print(xs.get(0))
    print(xs[1])
    xs[1] = 8
    print(xs.get(1))
    print(xs.length())
    xs.remove(0)
    print(xs.get(0))
    print(xs.length())
    xs.clear()
    print(xs.length())
    return 0
}
