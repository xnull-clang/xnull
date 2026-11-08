static Int main() {
    List<String> a = []
    a.push("first")
    if true {
        a = []
        a.push("second")
    }
    Int i = 0
    List<String> xs = []
    while i < 50000 {
        xs.push("x" + str(i))
        i = i + 1
    }
    print(a.get(0))
    return 0
}
