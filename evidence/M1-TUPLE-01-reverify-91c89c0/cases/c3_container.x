static Int main() {
    List<(Int, Int)> xs = [(7, 8)]
    print(xs.get(0).0)
    (Int, Int)[] arr = [(9, 10)]
    print(arr[0].1)
    (Int, Int)[] fixed = new (Int, Int)[2]
    print(fixed[0].0)
    print(fixed[0].1)
    return 0
}
