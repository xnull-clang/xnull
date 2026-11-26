package xdk2.numerics
import xdk.numerics
import xdk.errors
import xdk.collections
import xdk.math
import xdk.linalg

static Double quadratic(Double x) { return x * x - 2.0 }
static Double quadraticDerivative(Double x) { return 2.0 * x }

static Bool near(Double left, Double right, Double tolerance) {
    Double difference = left - right
    if difference < 0.0 { difference = 0.0 - difference }
    return difference <= tolerance
}

static Int main() {
    List<Double> cubicCoefficients = [-6.0, 11.0, -6.0, 1.0]
    Polynomial cubic = Polynomial.of(cubicCoefficients)
    print("poly=" + str(cubic.degree()) + "," + str(cubic.coefficientCount()) + "," +
        str(near(cubic.at(2.0), 0.0, 0.0000001)) + "," +
        str(near(cubic.at(0.0), -6.0, 0.0000001)) + "," +
        str(cubic.coefficient(2)) + "," + str(cubic.coefficient(9)))

    List<Double> leftCoefficients = [1.0, 2.0]
    List<Double> rightCoefficients = [3.0, 1.0]
    Polynomial left = Polynomial.of(leftCoefficients)
    Polynomial right = Polynomial.of(rightCoefficients)
    Polynomial sum = left.add(right)
    Polynomial difference = left.sub(right)
    Polynomial product = left.mul(right)
    Polynomial derivative = cubic.derivative()
    Polynomial integral = cubic.integral(0.0)
    print("poly-ops=" + str(sum.coefficient(0)) + "," + str(sum.coefficient(1)) + "," +
        str(difference.coefficient(0)) + "," + str(difference.coefficient(1)) + "," +
        str(product.coefficient(0)) + "," + str(product.coefficient(1)) + "," +
        str(product.coefficient(2)) + "," + str(derivative.at(1.0)) + "," +
        str(near(integral.derivative().at(2.0), cubic.at(2.0), 0.0000001)))

    List<Double> dividendCoefficients = [-1.0, 0.0, 1.0]
    List<Double> divisorCoefficients = [-1.0, 1.0]
    Polynomial dividend = Polynomial.of(dividendCoefficients)
    Polynomial divisor = Polynomial.of(divisorCoefficients)
    Result<Pair<Polynomial, Polynomial>, Error> division = dividend.divMod(divisor)
    print("poly-div=" + str(division.isOk()) + "," +
        str(division.value().first().degree()) + "," +
        str(division.value().first().coefficient(0)) + "," +
        str(division.value().first().coefficient(1)) + "," +
        str(division.value().second().isZero()) + "," +
        str(dividend.divMod(Polynomial.zero()).isErr()))

    List<Double> linearCoefficients = [4.0, 2.0]
    List<Double> quadraticCoefficients = [2.0, -3.0, 1.0]
    List<Double> noRootCoefficients = [1.0, 0.0, 1.0]
    List<Double> linearRoots = Polynomial.of(linearCoefficients).roots()
    List<Double> quadraticRoots = Polynomial.of(quadraticCoefficients).roots()
    List<Double> noRoots = Polynomial.of(noRootCoefficients).roots()
    List<Double> cubicRoots = cubic.roots()
    print("poly-roots=" + str(linearRoots.length()) + "," +
        str(near(linearRoots.get(0), -2.0, 0.0000001)) + "," +
        str(quadraticRoots.length()) + "," +
        str(near(quadraticRoots.get(0), 1.0, 0.0000001)) + "," +
        str(near(quadraticRoots.get(1), 2.0, 0.0000001)) + "," +
        str(noRoots.length()) + "," + str(cubicRoots.length()) + "," +
        str(near(cubicRoots.get(0), 1.0, 0.001)) + "," +
        str(near(cubicRoots.get(2), 3.0, 0.001)))

    Polynomial copied = Polynomial.of(cubicCoefficients)
    print("poly-equals=" + str(cubic.equals(copied)) + "," +
        str(cubic.equals(null)) + "," + str(cubic.toString().length() > 0) + "," +
        str(Polynomial.zero().degree()) + "," +
        str(Polynomial.monomial(3, 2.0).degree()))

    Double(Double) rootFunction = (Double x) -> quadratic(x)
    Double(Double) rootDerivative = (Double x) -> quadraticDerivative(x)
    Result<Double, Error> bisected = RootFinder.bisect(rootFunction, 0.0, 2.0,
        0.00000001, 200)
    Result<Double, Error> brented = RootFinder.brent(rootFunction, 0.0, 2.0,
        0.00000001, 200)
    Result<Double, Error> newtoned = RootFinder.newton(rootFunction, rootDerivative,
        1.0, 0.00000001, 100)
    Result<Double, Error> secanted = RootFinder.secant(rootFunction, 0.0, 2.0,
        0.00000001, 100)
    Double expected = sqrt(2.0)
    print("rootfind=" + str(near(bisected.value(), expected, 0.000001)) + "," +
        str(near(brented.value(), expected, 0.000001)) + "," +
        str(near(newtoned.value(), expected, 0.000001)) + "," +
        str(near(secanted.value(), expected, 0.000001)))
    print("rootfind-errors=" +
        errorKindName(RootFinder.bisect(rootFunction, 2.0, 3.0, 0.00000001, 20).error().kind()) +
        "," + errorKindName(RootFinder.newton((Double x) -> x * x + 1.0,
            (Double x) -> 2.0 * x, 0.0, 0.00000001, 10).error().kind()) + "," +
        errorKindName(RootFinder.secant(rootFunction, 1.0, 1.0, 0.00000001, 10).error().kind()))

    List<Double> xs = [0.0, 1.0, 2.0]
    List<Double> ys = [0.0, 1.0, 4.0]
    Interpolation linear = Interpolation.linear(xs, ys).value()
    Result<Double, Error> linearHalf = linear.at(0.5)
    Result<Double, Error> linearBetween = linear.at(1.5)
    Result<Double, Error> linearLeft = linear.at(-1.0)
    Result<Double, Error> linearRight = linear.at(3.0)
    print("interp-linear=" + str(near(linearHalf.value(), 0.5, 0.0000001)) + "," +
        str(near(linearBetween.value(), 2.5, 0.0000001)) + "," +
        str(near(linearLeft.value(), -1.0, 0.0000001)) + "," +
        str(near(linearRight.value(), 7.0, 0.0000001)))

    Interpolation spline = Interpolation.cubicSpline(xs, ys).value()
    print("interp-spline=" + str(near(spline.at(0.0).value(), 0.0, 0.0000001)) +
        "," + str(near(spline.at(1.0).value(), 1.0, 0.0000001)) + "," +
        str(near(spline.at(2.0).value(), 4.0, 0.0000001)) + "," +
        str(near(spline.at(-1.0).value(), 0.0, 0.0000001)) + "," +
        str(spline.at(0.5).isOk()))

    Interpolation pchip = Interpolation.pchip(xs, ys).value()
    print("interp-pchip=" + str(near(pchip.at(0.5).value(), 0.5, 0.3)) + "," +
        str(near(pchip.at(1.5).value(), 2.5, 0.3)) + "," +
        str(near(pchip.at(3.0).value(), 4.0, 0.0000001)))
    List<Double> badXs = [0.0, 0.0, 1.0]
    List<Double> oneX = [0.0]
    List<Double> oneY = [1.0]
    print("interp-invalid=" + str(Interpolation.linear(badXs, ys).isErr()) + "," +
        str(Interpolation.linear(oneX, oneY).isErr()))

    Double(Double) squareFunction = (Double x) -> x * x
    Double(Double) linearFunction = (Double x) -> x
    Double(Double) cubicFunction = (Double x) -> x * x * x
    Double(Double) exponentialFunction = (Double x) -> exp(0.0 - x)
    Result<Double, Error> simpsonValue = Integration.integrate(Context.background(),
        squareFunction, 0.0, 1.0, 0.0000000001, 100)
    Result<Double, Error> gaussValue = Integration.integrateGaussLegendre(
        Context.background(), squareFunction, 0.0, 1.0, 5)
    Result<Double, Error> tanhValue = Integration.integrateTanhSinh(
        Context.background(), squareFunction, 0.0, 1.0, 0.0000000001, 20)
    Result<Double, Error> infiniteValue = Integration.integrateInfinite(
        Context.background(), exponentialFunction, 0.0, 1.0 / 0.0, 0.0000000001, 20)
    print("integration=" + str(simpsonValue.isOk()) + "," +
        str(near(simpsonValue.value(), 1.0 / 3.0, 0.000001)) + "," +
        str(near(gaussValue.value(), 1.0 / 3.0, 0.000001)) + "," +
        str(near(tanhValue.value(), 1.0 / 3.0, 0.000001)) + "," +
        str(near(infiniteValue.value(), 1.0, 0.000001)))

    Result<Double, Error> gaussLinear = Integration.integrateGaussLegendre(
        Context.background(), linearFunction, 0.0, 1.0, 1)
    Result<Double, Error> gaussOne = Integration.integrateGaussLegendre(
        Context.background(), cubicFunction, 0.0, 1.0, 1)
    Result<Double, Error> gaussTwo = Integration.integrateGaussLegendre(
        Context.background(), cubicFunction, 0.0, 1.0, 2)
    Result<Double, Error> gaussFive = Integration.integrateGaussLegendre(
        Context.background(), cubicFunction, 0.0, 1.0, 5)
    print("integration-gauss=" +
        str(near(gaussLinear.value(), 0.5, 0.000001)) + "," +
        str(near(gaussOne.value(), 0.125, 0.000001)) + "," +
        str(near(gaussTwo.value(), 0.25, 0.000001)) + "," +
        str(near(gaussFive.value(), 0.25, 0.000001)))

    Double zeroTolerance = 0.0
    print("integration-errors=" +
        errorKindName(Integration.integrate(Context.background(), squareFunction,
            0.0, 1.0, zeroTolerance, 10).error().kind()) + "," +
        errorKindName(Integration.integrateGaussLegendre(Context.background(),
            squareFunction, 0.0, 1.0, 0).error().kind()) + "," +
        errorKindName(Integration.integrateTanhSinh(Context.background(),
            squareFunction, 0.0, 1.0, zeroTolerance, 10).error().kind()) + "," +
        errorKindName(Integration.integrateInfinite(Context.background(),
            exponentialFunction, 0.0, 1.0, 0.0000000001,
            20).error().kind()))

    Double(Double) shiftedQuadratic = (Double x) -> (x - 2.0) * (x - 2.0)
    Double(Double) shiftedCubic = (Double x) -> (x - 3.0) * (x - 3.0)
    Result<Pair<Double, Double>, Error> bounded = Optimization.minimizeBounded(
        Context.background(), shiftedQuadratic, -5.0, 5.0, 0.0000000001, 1000)
    Result<Pair<Double, Double>, Error> oneD = Optimization.minimize1d(
        Context.background(), shiftedCubic, 0.0, 1.0, 0.0000000001, 1000)
    print("optimize-1d=" + str(near(bounded.value().first(), 2.0, 0.000001)) +
        "," + str(near(bounded.value().second(), 0.0, 0.0000000001)) + "," +
        str(near(oneD.value().first(), 3.0, 0.000001)) + "," +
        str(near(oneD.value().second(), 0.0, 0.0000000001)))

    Double(List<Double>) rosenbrock = (List<Double> point) ->
        (1.0 - point.get(0)) * (1.0 - point.get(0)) +
        100.0 * (point.get(1) - point.get(0) * point.get(0)) *
            (point.get(1) - point.get(0) * point.get(0))
    List<Double>(List<Double>) paraboloidGradient = (List<Double> point) -> {
        List<Double> gradient = []
        gradient.push(2.0 * (point.get(0) - 1.5))
        gradient.push(2.0 * (point.get(1) + 2.5))
        return gradient
    }
    List<Double> rosenbrockStart = [-1.2, 1.0]
    Result<Pair<List<Double>, Double>, Error> nelder = Optimization.minimizeNelderMead(
        Context.background(), rosenbrock, rosenbrockStart, 0.0000000001, 10000)
    print("optimize-rosenbrock=" + str(nelder.isOk()) + "," +
        str(near(nelder.value().first().get(0), 1.0, 0.000001)) + "," +
        str(near(nelder.value().first().get(1), 1.0, 0.000001)) + "," +
        str(isFinite(nelder.value().second())))

    Double(List<Double>) paraboloid = (List<Double> point) ->
        (point.get(0) - 1.5) * (point.get(0) - 1.5) +
        (point.get(1) + 2.5) * (point.get(1) + 2.5)
    List<Double> paraboloidStart = [0.0, 0.0]
    Result<Pair<List<Double>, Double>, Error> generic = Optimization.minimize(
        Context.background(), paraboloid, paraboloidStart, 0.0000000001, 1000)
    Result<Pair<List<Double>, Double>, Error> bfgs = Optimization.minimizeBfgs(
        Context.background(), paraboloid, paraboloidGradient, paraboloidStart,
        0.0000000001, 1000)
    print("optimize-bfgs=" + str(bfgs.isOk()) + "," +
        str(near(bfgs.value().first().get(0), 1.5, 0.000001)) + "," +
        str(near(bfgs.value().first().get(1), -2.5, 0.000001)) + "," +
        str(isFinite(bfgs.value().second())))
    print("optimize-generic=" + str(generic.isOk()) + "," +
        str(near(generic.value().first().get(0), 1.5, 0.000001)) + "," +
        str(near(generic.value().first().get(1), -2.5, 0.000001)) + "," +
        str(near(generic.value().second(), 0.0, 0.0000000001)))

    List<Double> emptyState = []
    Result<Pair<Double, Double>, Error> badBounded = Optimization.minimizeBounded(
        Context.background(), shiftedQuadratic, 1.0, 1.0, 0.0000000001, 10)
    Result<Pair<Double, Double>, Error> badOneD = Optimization.minimize1d(
        Context.background(), shiftedCubic, 0.0, 0.0, 0.0000000001, 10)
    Result<Pair<List<Double>, Double>, Error> badNelder =
        Optimization.minimizeNelderMead(Context.background(), rosenbrock,
            emptyState, 0.0000000001, 10)
    Result<Pair<List<Double>, Double>, Error> badBfgs = Optimization.minimizeBfgs(
        Context.background(), paraboloid, paraboloidGradient, emptyState,
        0.0000000001, 10)
    print("optimize-errors=" + errorKindName(badBounded.error().kind()) + "," +
        errorKindName(badOneD.error().kind()) + "," +
        errorKindName(badNelder.error().kind()) + "," +
        errorKindName(badBfgs.error().kind()))

    List<Double>(Double, List<Double>) decay = (Double t, List<Double> y) -> {
        List<Double> next = []
        next.push(0.0 - y.get(0))
        return next
    }
    Matrix(Double, List<Double>) testDecayJacobian = (Double t, List<Double> y) -> {
        List<Double> values = []
        values.push(-1.0)
        return new Matrix(1, 1, values)
    }
    List<Double> decayInitial = [1.0]
    Result<Pair<List<Double>, List<List<Double>>>, Error> rk4Result =
        OdeSolver.solveRk4(Context.background(), decay, 0.0, decayInitial, 1.0,
            0.01, 1000)
    Result<Pair<List<Double>, List<List<Double>>>, Error> dormandPrince =
        OdeSolver.solveDormandPrince(Context.background(), decay, 0.0,
            decayInitial, 1.0, 0.0000000001, 0.01, 0.1, 1000)
    Result<Pair<List<Double>, List<List<Double>>>, Error> implicitResult =
        OdeSolver.solveImplicitEuler(Context.background(), decay, testDecayJacobian,
            0.0, decayInitial, 1.0, 0.01, 0.0000000001, 20, 1000)
    Result<Pair<List<Double>, List<List<Double>>>, Error> adaptive =
        OdeSolver.solve(Context.background(), decay, 0.0, decayInitial, 1.0,
            0.0000000001, 1000)
    Double expectedDecay = exp(0.0 - 1.0)
    print("ode-rk4=" + str(near(rk4Result.value().second().get(
        rk4Result.value().second().length() - 1).get(0), expectedDecay, 0.000001)) +
        "," + str(near(rk4Result.value().first().get(0), 0.0, 0.0000001)) + "," +
        str(near(rk4Result.value().first().get(rk4Result.value().first().length() - 1),
            1.0, 0.0000001)))
    print("ode-dp=" + str(near(dormandPrince.value().second().get(
        dormandPrince.value().second().length() - 1).get(0), expectedDecay,
        0.000001)) + "," +
        str(near(dormandPrince.value().first().get(0), 0.0, 0.0000001)) + "," +
        str(near(dormandPrince.value().first().get(
            dormandPrince.value().first().length() - 1), 1.0, 0.0000001)))
    print("ode-implicit=" + str(near(implicitResult.value().second().get(
        implicitResult.value().second().length() - 1).get(0), expectedDecay,
        0.005)) + "," +
        str(near(implicitResult.value().first().get(0), 0.0, 0.0000001)) + "," +
        str(near(implicitResult.value().first().get(
            implicitResult.value().first().length() - 1), 1.0, 0.0000001)))
    print("ode-solve=" + str(near(adaptive.value().second().get(
        adaptive.value().second().length() - 1).get(0), expectedDecay,
        0.000001)) + "," +
        str(near(adaptive.value().first().get(0), 0.0, 0.0000001)) + "," +
        str(near(adaptive.value().first().get(
            adaptive.value().first().length() - 1), 1.0, 0.0000001)))

    print("ode-errors=" +
        errorKindName(OdeSolver.solveRk4(Context.background(), decay, 0.0,
            emptyState, 1.0, 0.01, 10).error().kind()) + "," +
        errorKindName(OdeSolver.solveDormandPrince(Context.background(), decay,
            0.0, decayInitial, 1.0, 0.0, 0.01, 0.1, 10).error().kind()) + "," +
        errorKindName(OdeSolver.solveImplicitEuler(Context.background(), decay,
            testDecayJacobian, 0.0, decayInitial, 1.0, 0.0, 0.0000000001, 10,
            10).error().kind()))

    print("numerics=" + str(Numerics.defaultTolerance()) + "," +
        str(Numerics.defaultMaxIterations()) + "," + Numerics.backendName() + "," +
        Numerics.version())

    BigInt ten = BigInt.parse("10", 20).value()
    BigInt biHundred = BigInt.parse("100", 20).value()
    BigInt biMinus = BigInt.parse("-456", 20).value()
    BigInt leading = BigInt.parse("+000123", 20).value()
    BigInt hugeText = BigInt.parse("123456789012345678901234567890", 40).value()
    print("bigint-parse=" + ten.toString() + "," + biHundred.toString() + "," +
        biMinus.toString() + "," + leading.toString() + "," + hugeText.toString() +
        "," + BigInt.zero().toString() + "," +
        BigInt.parse("-0", 2).value().toString() + "," +
        str(BigInt.parse("", 2).isErr()) + "," +
        errorKindName(BigInt.parse("12x", 3).error().kind()) + "," +
        errorKindName(BigInt.parse("1234", 3).error().kind()))

    BigInt longMax = BigInt.fromLong(9223372036854775807 as Long)
    BigInt longMin = BigInt.fromLong(-9223372036854775807 as Long - 1 as Long)
    print("bigint-long=" + longMax.toString() + "," + longMin.toString() + "," +
        str(longMax.toLong().value()) + "," + str(longMin.toLong().value()) + "," +
        str(BigInt.fromInt(-7).toString()) + "," +
        BigInt.fromDoubleExact(123.0).value().toString() + "," +
        BigInt.fromDoubleExact(-45.0).value().toString() + "," +
        errorKindName(BigInt.fromDoubleExact(1.5).error().kind()) + "," +
        errorKindName(BigInt.fromDoubleExact(1000000000000000000000000000000.0).error().kind()))

    BigInt biCross = BigInt.parse("4294967296", 40).value()
    BigInt crossProduct = biCross.multiply(biCross)
    BigInt bigProduct = BigInt.parse("987654321987654321", 40).value()
        .multiply(BigInt.parse("123456789", 20).value())
    BigInt biSum = BigInt.parse("18446744073709551615", 40).value()
        .add(BigInt.one())
    print("bigint-arith=" + crossProduct.toString() + "," + bigProduct.toString() +
        "," + biSum.toString() + "," +
        BigInt.parse("1000000", 10).value().subtract(BigInt.one()).toString() + "," +
        BigInt.parse("5", 2).value().subtract(BigInt.parse("8", 2).value()).toString())

    BigInt biDividend = BigInt.parse("12345678901234567890", 40).value()
    BigInt biDivisor = BigInt.parse("987654321", 20).value()
    Result<BigIntPair, Error> biDivision = biDividend.divideAndRemainder(biDivisor)
    BigIntPair biDivisionValue = biDivision.value()
    BigInt negativeDividend = BigInt.parse("-7", 2).value()
    BigInt biThree = BigInt.parse("3", 2).value()
    Result<BigInt, Error> negativeDivide = negativeDividend.divide(biThree)
    Result<BigInt, Error> negativeRemainder = negativeDividend.remainder(biThree)
    Result<BigInt, Error> negativeMod = negativeDividend.mod(biThree)
    print("bigint-divide=" + biDivisionValue.quotient().toString() + "," +
        biDivisionValue.remainderValue().toString() + "," +
        negativeDivide.value().toString() + "," + negativeRemainder.value().toString() + "," +
        negativeMod.value().toString() + "," +
        errorKindName(biDividend.divide(BigInt.zero()).error().kind()) + "," +
        errorKindName(negativeDividend.mod(BigInt.parse("-3", 2).value()).error().kind()))

    BigInt biTwo = BigInt.parse("2", 2).value()
    BigInt biPower = biTwo.pow(Context.background(), 10).value()
    BigInt zeroPower = BigInt.zero().pow(Context.background(), 0).value()
    BigInt modPower = BigInt.parse("4", 2).value().modPow(Context.background(),
        BigInt.parse("13", 3).value(), BigInt.parse("497", 4).value()).value()
    BigInt inverse = BigInt.parse("3", 2).value().modInverse(
        BigInt.parse("11", 3).value()).value()
    BigInt gcdValue = BigInt.parse("48", 3).value().gcd(
        BigInt.parse("180", 4).value())
    BigInt lcmValue = BigInt.parse("48", 3).value().lcm(
        BigInt.parse("180", 4).value())
    Context cancelledPower = Context.background()
    cancelledPower.cancel()
    print("bigint-power=" + biPower.toString() + "," + zeroPower.toString() + "," +
        modPower.toString() + "," + inverse.toString() + "," + gcdValue.toString() +
        "," + lcmValue.toString() + "," +
        errorKindName(biTwo.pow(cancelledPower, 100).error().kind()) + "," +
        errorKindName(biTwo.pow(Context.background(), -1).error().kind()))

    BigInt biShifted = BigInt.one().shiftLeft(100).value()
    BigInt shiftedBack = biShifted.shiftRight(100).value()
    BigInt negativeShift = BigInt.parse("-7", 2).value().shiftRight(1).value()
    BigInt bitValue = BigInt.parse("5", 2).value()
    print("bigint-bits=" + biShifted.toString() + "," + shiftedBack.toString() + "," +
        negativeShift.toString() + "," + str(bitValue.testBit(0)) + "," +
        str(bitValue.testBit(1)) + "," + str(bitValue.testBit(2)) + "," +
        str(bitValue.bitLength()) + "," +
        str(BigInt.one().shiftLeft(64).value().bitLength()) + "," +
        errorKindName(BigInt.one().shiftLeft(-1).error().kind()))

    BigInt biSquare = BigInt.parse("100000000000000000000", 30).value()
    BigInt squareRoot = biSquare.multiply(biSquare).sqrt(Context.background()).value()
    BigInt tenToForty = BigInt.parse("10000000000000000000000000000000000000000", 50).value()
    BigInt almostSquare = tenToForty.add(BigInt.parse("12345", 6).value())
    BigInt floorRoot = almostSquare.sqrt(Context.background()).value()
    print("bigint-sqrt=" + squareRoot.toString() + "," + floorRoot.toString() + "," +
        almostSquare.subtract(floorRoot.multiply(floorRoot)).toString() + "," +
        BigInt.parse("144", 3).value().sqrt(Context.background()).value().toString() +
        "," + errorKindName(BigInt.fromInt(-1).sqrt(Context.background()).error().kind()))

    print("bigint-convert=" + str(BigInt.parse("2147483647", 12).value().toInt().value()) +
        "," + errorKindName(BigInt.parse("2147483648", 12).value().toInt().error().kind()) +
        "," + errorKindName(BigInt.parse("9223372036854775808", 20).value().toLong().error().kind()) +
        "," + str(BigInt.fromInt(42).toDouble()) + "," +
        str(BigInt.fromInt(-3).signum()) + "," +
        str(BigInt.zero().isZero()) + "," +
        str(BigInt.fromInt(-3).isNegative()) + "," +
        str(BigInt.fromInt(5).compare(BigInt.fromInt(3))) + "," +
        str(BigInt.fromInt(5).equals(BigInt.fromInt(5))))

    return 0
}
