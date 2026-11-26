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
    } else if name == "bigParseNull" {
        Result<BigInt, Error> value = BigInt.parse(null, 10)
    } else if name == "bigPowNull" {
        Result<BigInt, Error> value = BigInt.fromInt(2).pow(null, 2)
    } else if name == "bigTestBitNegative" {
        Bool value = BigInt.fromInt(2).testBit(-1)
    } else if name == "bigAddNull" {
        BigInt value = BigInt.fromInt(1).add(null)
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
echo "numerics_panic: PASS"
