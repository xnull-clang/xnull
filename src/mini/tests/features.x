static Int main() {
    Double x = 1.5
    Int bits = (0x0F << 4) | 3
    print($"x={x} bits={bits}")
    String? missing = null
    if missing == null {
        print("none")
    }
    Int n = 7
    print(n > 3 ? n >> 1 : 0)
    return 0
}
