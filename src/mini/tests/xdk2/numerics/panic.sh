#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/numerics-panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.numerics
import xdk.numerics
import xdk.errors
import xdk.linalg

static Int main(String[] args) {
    String name = args.get(0)
    if name == "polyNull" {
        Polynomial value = Polynomial.of(null)
    } else if name == "polyMonomial" {
        Polynomial value = Polynomial.monomial(-1, 1.0)
    } else if name == "polyCoefficient" {
        List<Double> values = [1.0]
        Polynomial polynomial = Polynomial.of(values)
        Double value = polynomial.coefficient(-1)
    } else if name == "polyAdd" {
        List<Double> values = [1.0]
        Polynomial polynomial = Polynomial.of(values)
        Polynomial value = polynomial.add(null)
    } else if name == "polySub" {
        List<Double> values = [1.0]
        Polynomial polynomial = Polynomial.of(values)
        Polynomial value = polynomial.sub(null)
    } else if name == "polyMul" {
        List<Double> values = [1.0]
        Polynomial polynomial = Polynomial.of(values)
        Polynomial value = polynomial.mul(null)
    } else if name == "polyDivNull" {
        List<Double> values = [1.0]
        Polynomial polynomial = Polynomial.of(values)
        Result<Pair<Polynomial, Polynomial>, Error> value = polynomial.divMod(null)
    } else if name == "interpLinearNull" {
        List<Double> values = [1.0]
        Result<Interpolation, Error> value = Interpolation.linear(null, values)
    } else if name == "interpSplineNull" {
        List<Double> values = [1.0]
        Result<Interpolation, Error> value = Interpolation.cubicSpline(null, values)
    } else if name == "interpPchipNull" {
        List<Double> values = [1.0]
        Result<Interpolation, Error> value = Interpolation.pchip(null, values)
    } else if name == "integrateNull" {
        Context context = null
        Double(Double) integrand = (Double x) -> x * x
        Result<Double, Error> value = Integration.integrate(context, integrand,
            0.0, 1.0, 0.0000000001, 10)
    } else if name == "integrateGaussNull" {
        Context context = null
        Double(Double) integrand = (Double x) -> x * x
        Result<Double, Error> value = Integration.integrateGaussLegendre(context,
            integrand, 0.0, 1.0, 5)
    } else if name == "integrateTanhNull" {
        Context context = null
        Double(Double) integrand = (Double x) -> x * x
        Result<Double, Error> value = Integration.integrateTanhSinh(context,
            integrand, 0.0, 1.0, 0.0000000001, 10)
    } else if name == "integrateInfiniteNull" {
        Context context = null
        Double(Double) integrand = (Double x) -> exp(0.0 - x)
        Result<Double, Error> value = Integration.integrateInfinite(context,
            integrand, 0.0, Inf(), 0.0000000001, 10)
    } else if name == "optimizeBoundedNull" {
        Context context = null
        Double(Double) objective = (Double x) -> x * x
        Result<Pair<Double, Double>, Error> value = Optimization.minimizeBounded(
            context, objective, -1.0, 1.0, 0.0000000001, 10)
    } else if name == "optimizeOneDNull" {
        Context context = null
        Double(Double) objective = (Double x) -> x * x
        Result<Pair<Double, Double>, Error> value = Optimization.minimize1d(
            context, objective, 0.0, 1.0, 0.0000000001, 10)
    } else if name == "optimizeNelderNull" {
        Context context = null
        Double(List<Double>) objective = (List<Double> point) ->
            point.get(0) * point.get(0)
        List<Double> point = [0.0]
        Result<Pair<List<Double>, Double>, Error> value =
            Optimization.minimizeNelderMead(context, objective, point,
                0.0000000001, 10)
    } else if name == "optimizeBfgsNull" {
        Context context = null
        Double(List<Double>) objective = (List<Double> point) ->
            point.get(0) * point.get(0)
        List<Double>(List<Double>) gradient = (List<Double> point) -> {
            List<Double> result = []
            result.push(2.0 * point.get(0))
            return result
        }
        List<Double> point = [0.0]
        Result<Pair<List<Double>, Double>, Error> value = Optimization.minimizeBfgs(
            context, objective, gradient, point, 0.0000000001, 10)
    } else if name == "odeRk4Null" {
        Context context = null
        List<Double>(Double, List<Double>) derivative = (Double t, List<Double> y) -> {
            List<Double> result = []
            result.push(0.0 - y.get(0))
            return result
        }
        List<Double> initial = [1.0]
        Result<Pair<List<Double>, List<List<Double>>>, Error> value =
            OdeSolver.solveRk4(context, derivative, 0.0, initial, 1.0, 0.01, 10)
    } else if name == "odeDpNull" {
        Context context = null
        List<Double>(Double, List<Double>) derivative = (Double t, List<Double> y) -> {
            List<Double> result = []
            result.push(0.0 - y.get(0))
            return result
        }
        List<Double> initial = [1.0]
        Result<Pair<List<Double>, List<List<Double>>>, Error> value =
            OdeSolver.solveDormandPrince(context, derivative, 0.0, initial, 1.0,
                0.0000000001, 0.01, 0.1, 10)
    } else if name == "odeImplicitNull" {
        Context context = null
        List<Double>(Double, List<Double>) derivative = (Double t, List<Double> y) -> {
            List<Double> result = []
            result.push(0.0 - y.get(0))
            return result
        }
        Matrix(Double, List<Double>) jacobian = (Double t, List<Double> y) -> {
            List<Double> values = []
            values.push(-1.0)
            return new Matrix(1, 1, values)
        }
        List<Double> initial = [1.0]
        Result<Pair<List<Double>, List<List<Double>>>, Error> value =
            OdeSolver.solveImplicitEuler(context, derivative, jacobian, 0.0,
                initial, 1.0, 0.01, 0.0000000001, 10, 10)
    } else if name == "bigParseNull" {
        Result<BigInt, Error> value = BigInt.parse(null, 10)
    } else if name == "bigPowNull" {
        Result<BigInt, Error> value = BigInt.fromInt(2).pow(null, 2)
    } else if name == "bigTestBitNegative" {
        Bool value = BigInt.fromInt(2).testBit(-1)
    } else if name == "bigAddNull" {
        BigInt value = BigInt.fromInt(1).add(null)
    } else if name == "bigFloatSqrtNull" {
        BigFloat value = BigFloat.parse("2", 64, RoundingMode.HalfEven, 5).value()
        Context context = null
        Result<BigFloat, Error> result = value.sqrt(context, 64, RoundingMode.HalfEven)
    } else if name == "bigFloatAddNull" {
        BigFloat value = BigFloat.parse("2", 64, RoundingMode.HalfEven, 5).value()
        Result<BigFloat, Error> result = value.add(null, 64, RoundingMode.HalfEven)
    } else if name == "fftNull" {
        Context context = null
        List<Complex> values = []
        Result<List<Complex>, Error> value = Fft.forward(context, values)
    } else if name == "signalNull" {
        Context context = null
        List<Double> values = []
        values.push(1.0)
        List<Double> kernel = []
        kernel.push(1.0)
        Result<List<Double>, Error> value = SignalBuffer.convolve(context, values, kernel)
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || { cat "$TMP/build.err" >&2; exit 1; }
check_panic() {
    name=$1
    marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && { echo "numerics panic: $name did not fail" >&2; exit 1; }
    grep -Fq "$marker" "$TMP/$name.err" || { echo "numerics panic: $name missing '$marker'" >&2; cat "$TMP/$name.err" >&2; exit 1; }
}
check_panic polyNull "Polynomial.of: null coefficients"
check_panic polyMonomial "Polynomial.monomial: negative degree"
check_panic polyCoefficient "Polynomial.coefficient: negative index"
check_panic polyAdd "Polynomial.add: null"
check_panic polySub "Polynomial.sub: null"
check_panic polyMul "Polynomial.mul: null"
check_panic polyDivNull "Polynomial.divMod: null"
check_panic interpLinearNull "Interpolation: null data"
check_panic interpSplineNull "Interpolation: null data"
check_panic interpPchipNull "Interpolation: null data"
check_panic integrateNull "Integration.integrateSimpson: null argument"
check_panic integrateGaussNull "Integration.integrateGaussLegendre: null argument"
check_panic integrateTanhNull "Integration.integrateTanhSinh: null argument"
check_panic integrateInfiniteNull "Integration.integrateInfinite: null argument"
check_panic optimizeBoundedNull "Optimization.minimizeBounded: null argument"
check_panic optimizeOneDNull "Optimization.minimize1d: null argument"
check_panic optimizeNelderNull "Optimization.minimizeNelderMead: null argument"
check_panic optimizeBfgsNull "Optimization.minimizeBfgs: null argument"
check_panic odeRk4Null "OdeSolver.solveRk4: null argument"
check_panic odeDpNull "OdeSolver.solveDormandPrince: null argument"
check_panic odeImplicitNull "OdeSolver.solveImplicitEuler: null argument"
check_panic bigParseNull "BigInt.parse: null text"
# removed bigParseEmpty "BigInt.parse: empty"
# removed bigParseMax "BigInt.parse: too many digits"
# removed bigParseDigit "BigInt.parse: invalid digit"
# removed bigDoubleFraction "BigInt.fromDoubleExact: not an integer"
# removed bigDoubleInfinite "BigInt.fromDoubleExact: not an integer"
# removed bigDivideZero "BigInt: divide by zero"
# removed bigModZero "BigInt.mod: modulus must be positive"
# removed bigPowNegative "BigInt.pow: negative exponent"
check_panic bigPowNull "BigInt.pow: null context"
# removed bigModPowNegative "BigInt.modPow: negative exponent"
# removed bigShiftNegative "BigInt.shiftLeft: invalid bit count"
check_panic bigTestBitNegative "BigInt.testBit: negative index"
# removed bigSqrtNegative "BigInt.sqrt: negative"
# removed bigToInt "BigInt.toInt: overflow"
# removed bigToLong "BigInt.toLong: overflow"
check_panic bigAddNull "BigInt.add: null"
check_panic bigFloatSqrtNull "BigFloat.sqrt: null context"
check_panic bigFloatAddNull "BigFloat.add: null argument"
check_panic fftNull "Fft.transform: null argument"
check_panic signalNull "SignalBuffer.convolve: null argument"
echo "numerics_panic: PASS"
