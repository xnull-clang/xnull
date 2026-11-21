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

    print(factorial(5).value())
    print(factorial(-1).isErr())
    print(factorial(13).isErr())

    List<Double> empty = []
    List<Double> one = [4.0]
    print(sum(empty))
    print(isNaN(mean(empty)))
    print(isNaN(median(empty)))
    print(isNaN(variance(empty)))
    print(isNaN(quantile(empty, 0.5)))
    print(mean(one))
    print(median(one))
    print(variance(one))
    List<Double> two = [1.0, 3.0]
    print(quantile(two, -1.0))
    print(quantile(two, 2.0))

    print(addIntChecked(1, 2).value())
    print(addIntChecked(maxIntValue(), 1).isErr())
    print(addIntChecked(minIntValue(), -1).isErr())
    print(subIntChecked(minIntValue(), 1).isErr())
    print(mulIntChecked(65536, 65536).isErr())
    print(divIntChecked(1, 0).isErr())
    print(divIntChecked(minIntValue(), -1).isErr())
    print(modIntChecked(minIntValue(), -1).value())
    print(negIntChecked(minIntValue()).isErr())
    print(absIntChecked(-5).value())

    print(addLongChecked(1, 2).value())
    print(addLongChecked(maxLongValue(), 1).isErr())
    print(subLongChecked(minLongValue(), 1).isErr())
    print(mulLongChecked(4000000000, 4000000000).isErr())
    Long negativeBig = 0 - (4000000000 as Long)
    print(mulLongChecked(negativeBig, 4000000000 as Long).isErr())
    print(divLongChecked(1, 0).isErr())
    print(divLongChecked(minLongValue(), -1).isErr())
    print(modLongChecked(minLongValue(), -1).value())
    print(negLongChecked(minLongValue()).isErr())
    print(absLongChecked(-5).value())

    print(addIntSaturating(maxIntValue(), 1))
    print(subIntSaturating(minIntValue(), 1))
    print(mulIntSaturating(65536, 65536))
    print(mulIntSaturating(-65536, 65536))
    print(addLongSaturating(maxLongValue(), 1))
    print(subLongSaturating(minLongValue(), 1))
    print(mulLongSaturating(4000000000, 4000000000))
    print(mulLongSaturating(negativeBig, 4000000000 as Long))

    print(permutations(5, 2).value())
    print(permutations(5, 0).value())
    print(permutations(-1, 2).isErr())
    print(permutations(3, 4).isErr())
    print(permutations(21, 21).isErr())
    print(combinations(5, 2).value())
    print(combinations(5, 0).value())
    print(combinations(5, 5).value())
    print(combinations(100, 50).isErr())
    return 0
}
