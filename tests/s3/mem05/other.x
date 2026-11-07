class V { Int x = 1; }
class H { V v; }
static Int take(V v) { return v.x }
static Int main() {
    H h = new H()
    h.v = new V()
    h.v.x = 3
    print(take(h.v) + h.v.x)
    return 0
}
