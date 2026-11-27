package xdk2.numerics_transcendental
import xdk.numerics
import xdk.math
import xdk.errors

static Bool near(Double left, Double right, Double tolerance) {
    Double difference = left - right
    if difference < 0.0 { difference = 0.0 - difference }
    return difference <= tolerance
}

static Int main() {
    // ---------- BigFloat transcendentals ----------
    Context bfContext = Context.background()
    BigFloat bfExp = BigFloat.one(64).value().exp(bfContext, 64, RoundingMode.HalfEven).value()
    BigFloat bfLog = bfExp.log(bfContext, 64, RoundingMode.HalfEven).value()
    BigFloat transTwo = BigFloat.fromInt(2, 64, RoundingMode.HalfEven).value()
    BigFloat transTen = BigFloat.fromInt(10, 64, RoundingMode.HalfEven).value()
    BigFloat transHalf = BigFloat.parse("0.5", 64, RoundingMode.HalfEven, 5).value()
    BigFloat bfPow = transTwo.pow(bfContext, transTen, 64, RoundingMode.HalfEven).value()
    BigFloat bfSqrt = transTwo.pow(bfContext, transHalf, 64, RoundingMode.HalfEven).value()
    print("bigfloat-transcendental=" + str(near(bfExp.toDouble(), 2.718281828459045, 0.0000001)) +
        "," + str(near(bfLog.toDouble(), 1.0, 0.0000001)) +
        "," + str(bfPow.toDecimalString(bfContext, 0, RoundingMode.HalfEven).value() == "1024") +
        "," + str(near(bfSqrt.toDouble(), 1.4142135623730951, 0.0000001)) +
        "," + str(near(BigFloat.one(64).value().log(bfContext, 64,
            RoundingMode.HalfEven).value().toDouble(), 0.0, 0.0000001)))
    Result<BigFloat, Error> badLog = BigFloat.fromInt(-2, 64,
        RoundingMode.HalfEven).value().log(bfContext, 64, RoundingMode.HalfEven)
    Result<BigFloat, Error> badPow = BigFloat.fromInt(-2, 64,
        RoundingMode.HalfEven).value().pow(bfContext, transHalf, 64, RoundingMode.HalfEven)
    print("bigfloat-transcendental-errors=" + errorKindName(badLog.error().kind()) +
        "," + errorKindName(badPow.error().kind()))

    return 0
}
