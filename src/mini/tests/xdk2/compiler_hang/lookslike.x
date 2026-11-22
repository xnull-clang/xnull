class Holder {
    Long shift(Long bits, Int index) {
        if index < 0 { return 0 }
        return bits >> (index * 8)
    }
}
static Int main() {
    Holder h = new Holder()
    print(h.shift(256, 1))
    Long one = 1
    print(one << 40)
    Long mask = 255
    Long low = 15
    print(mask & low)
    Long minus = -1
    print(minus >> 8)
    return 0
}
