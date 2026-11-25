package xdk2.numerics
import xdk.numerics
import xdk.errors
import xdk.math

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

    print("numerics=" + str(Numerics.defaultTolerance()) + "," +
        str(Numerics.defaultMaxIterations()) + "," + Numerics.backendName() + "," +
        Numerics.version())
    return 0
}
