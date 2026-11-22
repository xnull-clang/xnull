class Holder {
    Long shift(Long bits, Int index) {
        if index < 0 { return 0 }
        return bits >> (index * 8)
    }
}
static Int main() {
    Holder h = new Holder()
    print(h.shift(256, 1))
    print(1L << 40)
    print(0xFFL & 0x0FL)
    print(-1L >> 8)
    return 0
}
