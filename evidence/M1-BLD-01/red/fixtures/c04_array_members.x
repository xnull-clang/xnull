static Int main() {
    Int[] values = [1, 2, 3]
    print(values[0])
    values[1] = 9
    print(values.join("-"))
    print(values.length())
    Int[] empty = []
    print(empty.length())
    print(empty.join(","))
    Bool[] bs = [true, false]
    print(bs.join(","))
    Double[] ds = [1.5, 2.5]
    print(ds.join(","))
    return 0
}
