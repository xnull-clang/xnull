class V { Int x = 0; }
static Int main() {
    List<V> xs = []
    V a = new V()
    a.x = 5
    xs.push(a)
    print(xs.get(0).x)
    return 0
}
