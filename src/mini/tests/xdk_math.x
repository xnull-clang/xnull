import xdk.math

static Int128 addInt128(Int128 left, Int128 right) {
    return left + right
}

static Int main() {
    print(sqrt(9.0))
    print(absI(-7))
    print(minI(3, 8))
    print(clampI(12, 0, 10))
    print(isNaN(NaN()))

    Int128 a = 1
    Int128 b = 2
    print(a + b)
    print(a * b)
    print(a < b)
    print(str(a))
    Int128 wide = 170141183460469231731687303715884105726
    print(wide)
    Int128 negative = -170141183460469231731687303715884105726
    print(negative)
    print(addInt128(5, 6))
    print(int128Max())
    print(int128Min())

    print(addI128Checked(1, 2).value())
    print(addI128Checked(int128Max(), 1).isErr())
    print(subI128Checked(int128Min(), 1).isErr())
    print(mulI128Checked(3, 4).value())
    print(mulI128Checked(int128Min(), -1).isErr())
    print(divI128Checked(7, 2).value())
    print(divI128Checked(1, 0).isErr())
    print(modI128Checked(-7, 3).value())
    print(negI128Checked(int128Min()).isErr())
    print(absI128Checked(-5).value())
    return 0
}
