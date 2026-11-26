// xdk.numerics —— 多项式/求根/插值核心（M22.1）
//
// 实现实系数 Polynomial、RootFinder、Interpolation、Numerics 门面。
// BigInt/BigFloat/FFT/ODE/特殊函数/积分/优化留后续。
package xdk.numerics
import xdk.errors
import xdk.math
import xdk.collections
import xdk.linalg

// ---------- Polynomial ----------
class Polynomial {
    final List<Double> _coefficients

    private Polynomial(List<Double> coefficients) {
        List<Double> copied = coefficients.copy()
        while copied.length() > 0 {
            if copied.get(copied.length() - 1) != 0.0 { break }
            copied.remove(copied.length() - 1)
        }
        self._coefficients = copied
    }

    static Polynomial of(List<Double> coefficients) {
        if coefficients == null { throw "Polynomial.of: null coefficients" }
        return new Polynomial(coefficients)
    }

    static Polynomial zero() {
        List<Double> empty = []
        return new Polynomial(empty)
    }

    static Polynomial constant(Double value) {
        List<Double> values = []
        values.push(value)
        return new Polynomial(values)
    }

    static Polynomial monomial(Int degree, Double coefficient) {
        if degree < 0 { throw "Polynomial.monomial: negative degree" }
        List<Double> values = []
        Int index = 0
        while index < degree {
            values.push(0.0)
            index = index + 1
        }
        values.push(coefficient)
        return new Polynomial(values)
    }

    List<Double> coefficients() { return self._coefficients.copy() }
    Int degree() { return self._coefficients.length() - 1 }
    Int coefficientCount() { return self._coefficients.length() }
    Bool isZero() { return self._coefficients.length() == 0 }

    Double coefficient(Int index) {
        if index < 0 { throw "Polynomial.coefficient: negative index" }
        if index >= self._coefficients.length() { return 0.0 }
        return self._coefficients.get(index)
    }

    Double at(Double value) {
        Double result = 0.0
        Int index = self._coefficients.length() - 1
        while index >= 0 {
            result = result * value + self._coefficients.get(index)
            index = index - 1
        }
        return result
    }

    Polynomial add(Polynomial other) {
        if other == null { throw "Polynomial.add: null" }
        Int count = self._coefficients.length()
        if other.coefficientCount() > count { count = other.coefficientCount() }
        List<Double> values = []
        Int index = 0
        while index < count {
            values.push(self.coefficient(index) + other.coefficient(index))
            index = index + 1
        }
        return new Polynomial(values)
    }

    Polynomial sub(Polynomial other) {
        if other == null { throw "Polynomial.sub: null" }
        Int count = self._coefficients.length()
        if other.coefficientCount() > count { count = other.coefficientCount() }
        List<Double> values = []
        Int index = 0
        while index < count {
            values.push(self.coefficient(index) - other.coefficient(index))
            index = index + 1
        }
        return new Polynomial(values)
    }

    Polynomial mul(Polynomial other) {
        if other == null { throw "Polynomial.mul: null" }
        if self.isZero() || other.isZero() { return Polynomial.zero() }
        List<Double> values = []
        Int count = self.degree() + other.degree() + 1
        Int index = 0
        while index < count {
            values.push(0.0)
            index = index + 1
        }
        Int left = 0
        while left < self._coefficients.length() {
            Int right = 0
            while right < other.coefficientCount() {
                values.set(left + right, values.get(left + right) +
                    self._coefficients.get(left) * other.coefficient(right))
                right = right + 1
            }
            left = left + 1
        }
        return new Polynomial(values)
    }

    Polynomial derivative() {
        if self._coefficients.length() <= 1 { return Polynomial.zero() }
        List<Double> values = []
        Int index = 1
        while index < self._coefficients.length() {
            values.push(self._coefficients.get(index) * (index as Double))
            index = index + 1
        }
        return new Polynomial(values)
    }

    Polynomial integral(Double constantTerm) {
        List<Double> values = []
        values.push(constantTerm)
        Int index = 0
        while index < self._coefficients.length() {
            values.push(self._coefficients.get(index) / ((index + 1) as Double))
            index = index + 1
        }
        return new Polynomial(values)
    }

    Result<Pair<Polynomial, Polynomial>, Error> divMod(Polynomial divisor) {
        if divisor == null { throw "Polynomial.divMod: null" }
        if divisor.isZero() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "Polynomial.divMod: zero divisor"))
        }
        List<Double> remainder = self._coefficients.copy()
        List<Double> quotient = []
        Int quotientCount = self.degree() - divisor.degree() + 1
        if quotientCount > 0 {
            Int index = 0
            while index < quotientCount {
                quotient.push(0.0)
                index = index + 1
            }
        }
        Int degree = self.degree() - divisor.degree()
        while degree >= 0 && remainder.length() > 0 {
            Int remainderDegree = remainder.length() - 1
            Double factor = remainder.get(remainderDegree) /
                divisor.coefficient(divisor.degree())
            quotient.set(degree, factor)
            Int index = 0
            while index <= divisor.degree() {
                Int target = degree + index
                if target < remainder.length() {
                    remainder.set(target, remainder.get(target) -
                        factor * divisor.coefficient(index))
                }
                index = index + 1
            }
            while remainder.length() > 0 &&
                remainder.get(remainder.length() - 1) == 0.0 {
                remainder.remove(remainder.length() - 1)
            }
            degree = remainder.length() - 1 - divisor.degree()
        }
        Polynomial q = new Polynomial(quotient)
        Polynomial r = new Polynomial(remainder)
        return Ok(new Pair<Polynomial, Polynomial>(q, r))
    }

    List<Double> roots() {
        if self.degree() < 1 {
            List<Double> empty = []
            return empty
        }
        if self._coefficients.length() == 2 {
            List<Double> one = []
            one.push((0.0 - self._coefficients.get(0)) / self._coefficients.get(1))
            return one
        }
        if self._coefficients.length() == 3 {
            return self.quadraticRoots()
        }
        return self.numericRoots()
    }

    private List<Double> quadraticRoots() {
        Double a = self._coefficients.get(2)
        Double b = self._coefficients.get(1)
        Double c = self._coefficients.get(0)
        Double discriminant = b * b - 4.0 * a * c
        List<Double> result = []
        if discriminant < 0.0 { return result }
        Double root = sqrt(discriminant)
        result.push((0.0 - b - root) / (2.0 * a))
        if root != 0.0 { result.push((0.0 - b + root) / (2.0 * a)) }
        return Numerics.sortDoubles(result)
    }

    private List<Double> numericRoots() {
        List<Double> result = []
        Double previousX = -100.0
        Double previousValue = self.at(previousX)
        if abs(previousValue) <= 0.0000000001 { result.push(previousX) }
        Double step = 0.5
        Double x = previousX + step
        while x <= 100.0 {
            Double value = self.at(x)
            if abs(value) <= 0.0000000001 {
                Numerics.addUnique(result, x)
            } else if previousValue * value < 0.0 {
                Result<Double, Error> root = RootFinder.bisect(
                    (Double probe) -> self.at(probe), previousX, x, 0.0000000001, 200)
                if root.isOk() { Numerics.addUnique(result, root.value()) }
            }
            previousX = x
            previousValue = value
            x = x + step
        }
        return Numerics.sortDoubles(result)
    }

    Bool equals(Polynomial other) {
        if other == null { return false }
        if self._coefficients.length() != other.coefficientCount() { return false }
        Int index = 0
        while index < self._coefficients.length() {
            if self._coefficients.get(index) != other.coefficient(index) { return false }
            index = index + 1
        }
        return true
    }

    String toString() {
        if self.isZero() { return "0" }
        String result = ""
        Int index = self.degree()
        while index >= 0 {
            Double value = self._coefficients.get(index)
            if value != 0.0 {
                if result != "" { result = result + " + " }
                result = result + str(value)
                if index > 0 { result = result + "x^" + str(index) }
            }
            index = index - 1
        }
        return result
    }
}

// ---------- RootFinder ----------
class RootFinder {
    private RootFinder() { }

    static Result<Double, Error> bisect(Double(Double) function, Double lower,
            Double upper, Double tolerance, Int maximumIterations) {
        if !isFinite(lower) || !isFinite(upper) || lower >= upper {
            return Err(new BasicError(ErrorKind.InvalidArgument, "bisect: invalid interval"))
        }
        if tolerance <= 0.0 || maximumIterations < 1 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "bisect: invalid settings"))
        }
        Double lowerValue = function(lower)
        Double upperValue = function(upper)
        if !isFinite(lowerValue) || !isFinite(upperValue) {
            return Err(new BasicError(ErrorKind.Internal, "bisect: non-finite function value"))
        }
        if lowerValue == 0.0 { return Ok(lower) }
        if upperValue == 0.0 { return Ok(upper) }
        if lowerValue * upperValue > 0.0 {
            return Err(new BasicError(ErrorKind.Unsupported, "bisect: interval does not bracket"))
        }
        Double left = lower
        Double right = upper
        Int iteration = 0
        while iteration < maximumIterations {
            Double middle = (left + right) * 0.5
            Double middleValue = function(middle)
            if !isFinite(middleValue) {
                return Err(new BasicError(ErrorKind.Internal, "bisect: non-finite value"))
            }
            if abs(middleValue) <= tolerance || (right - left) * 0.5 <= tolerance {
                return Ok(middle)
            }
            if lowerValue * middleValue < 0.0 {
                right = middle
                upperValue = middleValue
            } else {
                left = middle
                lowerValue = middleValue
            }
            iteration = iteration + 1
        }
        return Err(new BasicError(ErrorKind.Internal, "bisect: did not converge"))
    }

    static Result<Double, Error> brent(Double(Double) function, Double lower,
            Double upper, Double tolerance, Int maximumIterations) {
        return RootFinder.bisect(function, lower, upper, tolerance, maximumIterations)
    }

    static Result<Double, Error> newton(Double(Double) function, Double(Double) derivative,
            Double initialPoint, Double tolerance, Int maximumIterations) {
        if !isFinite(initialPoint) || tolerance <= 0.0 || maximumIterations < 1 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "newton: invalid settings"))
        }
        Double x = initialPoint
        Int iteration = 0
        while iteration < maximumIterations {
            Double value = function(x)
            Double slope = derivative(x)
            if !isFinite(value) || !isFinite(slope) {
                return Err(new BasicError(ErrorKind.Internal, "newton: non-finite value"))
            }
            if abs(value) <= tolerance { return Ok(x) }
            if abs(slope) < 0.00000000000001 {
                return Err(new BasicError(ErrorKind.Unsupported, "newton: zero derivative"))
            }
            x = x - value / slope
            if !isFinite(x) {
                return Err(new BasicError(ErrorKind.Internal, "newton: non-finite step"))
            }
            iteration = iteration + 1
        }
        return Err(new BasicError(ErrorKind.Internal, "newton: did not converge"))
    }

    static Result<Double, Error> secant(Double(Double) function, Double firstPoint,
            Double secondPoint, Double tolerance, Int maximumIterations) {
        if !isFinite(firstPoint) || !isFinite(secondPoint) ||
            firstPoint == secondPoint || tolerance <= 0.0 || maximumIterations < 1 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "secant: invalid settings"))
        }
        Double previous = firstPoint
        Double current = secondPoint
        Double previousValue = function(previous)
        Double currentValue = function(current)
        Int iteration = 0
        while iteration < maximumIterations {
            if !isFinite(previousValue) || !isFinite(currentValue) {
                return Err(new BasicError(ErrorKind.Internal, "secant: non-finite value"))
            }
            if abs(currentValue) <= tolerance { return Ok(current) }
            Double denominator = currentValue - previousValue
            if abs(denominator) < 0.00000000000001 {
                return Err(new BasicError(ErrorKind.Unsupported, "secant: zero slope"))
            }
            Double next = current - currentValue * (current - previous) / denominator
            if !isFinite(next) {
                return Err(new BasicError(ErrorKind.Internal, "secant: non-finite step"))
            }
            if abs(next - current) <= tolerance { return Ok(next) }
            previous = current
            previousValue = currentValue
            current = next
            currentValue = function(current)
            iteration = iteration + 1
        }
        return Err(new BasicError(ErrorKind.Internal, "secant: did not converge"))
    }
}

// ---------- Interpolation ----------
class Interpolation {
    final List<Double> _xs
    final List<Double> _ys
    final Int _kind
    final List<Double> _b
    final List<Double> _c
    final List<Double> _d

    private Interpolation(List<Double> xs, List<Double> ys, Int kind,
                          List<Double> b, List<Double> c, List<Double> d) {
        self._xs = xs
        self._ys = ys
        self._kind = kind
        self._b = b
        self._c = c
        self._d = d
    }

    static Result<Interpolation, Error> linear(List<Double> xs, List<Double> ys) {
        Result<Unit, Error> valid = Interpolation.validate(xs, ys)
        if valid.isErr() { return Err(valid.error()) }
        List<Double> b = []
        List<Double> c = []
        List<Double> d = []
        Int index = 0
        while index < xs.length() - 1 {
            b.push((ys.get(index + 1) - ys.get(index)) /
                (xs.get(index + 1) - xs.get(index)))
            c.push(0.0)
            d.push(0.0)
            index = index + 1
        }
        return Ok(new Interpolation(xs.copy(), ys.copy(), 0, b, c, d))
    }

    static Result<Interpolation, Error> cubicSpline(List<Double> xs, List<Double> ys) {
        Result<Unit, Error> valid = Interpolation.validate(xs, ys)
        if valid.isErr() { return Err(valid.error()) }
        Int n = xs.length()
        List<Double> h = []
        Int index = 0
        while index < n - 1 {
            h.push(xs.get(index + 1) - xs.get(index))
            index = index + 1
        }
        List<Double> alpha = []
        index = 1
        while index < n - 1 {
            alpha.push(3.0 / h.get(index) * (ys.get(index + 1) - ys.get(index)) -
                3.0 / h.get(index - 1) * (ys.get(index) - ys.get(index - 1)))
            index = index + 1
        }
        List<Double> l = []
        List<Double> mu = []
        List<Double> z = []
        index = 0
        while index < n {
            l.push(0.0)
            mu.push(0.0)
            z.push(0.0)
            index = index + 1
        }
        l.set(0, 1.0)
        index = 1
        while index < n - 1 {
            l.set(index, 2.0 * (xs.get(index + 1) - xs.get(index - 1)) -
                h.get(index - 1) * mu.get(index - 1))
            mu.set(index, h.get(index) / l.get(index))
            z.set(index, (alpha.get(index - 1) - h.get(index - 1) * z.get(index - 1)) /
                l.get(index))
            index = index + 1
        }
        l.set(n - 1, 1.0)
        List<Double> c = []
        List<Double> b = []
        List<Double> d = []
        index = 0
        while index < n {
            c.push(0.0)
            b.push(0.0)
            d.push(0.0)
            index = index + 1
        }
        index = n - 2
        while index >= 0 {
            c.set(index, z.get(index) - mu.get(index) * c.get(index + 1))
            b.set(index, (ys.get(index + 1) - ys.get(index)) / h.get(index) -
                h.get(index) * (c.get(index + 1) + 2.0 * c.get(index)) / 3.0)
            d.set(index, (c.get(index + 1) - c.get(index)) / (3.0 * h.get(index)))
            index = index - 1
        }
        return Ok(new Interpolation(xs.copy(), ys.copy(), 1, b, c, d))
    }

    static Result<Interpolation, Error> pchip(List<Double> xs, List<Double> ys) {
        Result<Unit, Error> valid = Interpolation.validate(xs, ys)
        if valid.isErr() { return Err(valid.error()) }
        Int n = xs.length()
        List<Double> h = []
        List<Double> delta = []
        Int index = 0
        while index < n - 1 {
            Double width = xs.get(index + 1) - xs.get(index)
            h.push(width)
            delta.push((ys.get(index + 1) - ys.get(index)) / width)
            index = index + 1
        }
        List<Double> slopes = []
        index = 0
        while index < n {
            slopes.push(0.0)
            index = index + 1
        }
        slopes.set(0, delta.get(0))
        slopes.set(n - 1, delta.get(n - 2))
        index = 1
        while index < n - 1 {
            if delta.get(index - 1) * delta.get(index) > 0.0 {
                Double w1 = 2.0 * h.get(index) + h.get(index - 1)
                Double w2 = h.get(index) + 2.0 * h.get(index - 1)
                slopes.set(index, (w1 + w2) / (w1 / delta.get(index - 1) +
                    w2 / delta.get(index)))
            } else {
                slopes.set(index, 0.0)
            }
            index = index + 1
        }
        List<Double> b = []
        List<Double> c = []
        List<Double> d = []
        index = 0
        while index < n - 1 {
            b.push(slopes.get(index))
            c.push((3.0 * delta.get(index) - 2.0 * slopes.get(index) -
                slopes.get(index + 1)) / h.get(index))
            d.push((slopes.get(index) + slopes.get(index + 1) -
                2.0 * delta.get(index)) / (h.get(index) * h.get(index)))
            index = index + 1
        }
        return Ok(new Interpolation(xs.copy(), ys.copy(), 2, b, c, d))
    }

    Result<Double, Error> at(Double value) {
        if !isFinite(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "interpolation: non-finite x"))
        }
        if value < self._xs.get(0) {
            if self._kind == 0 {
                return Ok(self._ys.get(0) + self._b.get(0) * (value - self._xs.get(0)))
            }
            return Ok(self._ys.get(0))
        }
        if value > self._xs.get(self._xs.length() - 1) {
            if self._kind == 0 {
                Int last = self._b.length() - 1
                return Ok(self._ys.get(self._ys.length() - 1) +
                    self._b.get(last) * (value - self._xs.get(self._xs.length() - 1)))
            }
            return Ok(self._ys.get(self._ys.length() - 1))
        }
        Int segment = 0
        while segment < self._xs.length() - 2 && value > self._xs.get(segment + 1) {
            segment = segment + 1
        }
        Double dx = value - self._xs.get(segment)
        if self._kind == 0 {
            return Ok(self._ys.get(segment) + self._b.get(segment) * dx)
        }
        return Ok(self._ys.get(segment) + self._b.get(segment) * dx +
            self._c.get(segment) * dx * dx + self._d.get(segment) * dx * dx * dx)
    }

    private static Result<Unit, Error> validate(List<Double> xs, List<Double> ys) {
        if xs == null || ys == null {
            throw "Interpolation: null data"
        }
        if xs.length() < 2 || xs.length() != ys.length() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "interpolation: invalid length"))
        }
        Int index = 0
        while index < xs.length() {
            if !isFinite(xs.get(index)) || !isFinite(ys.get(index)) {
                return Err(new BasicError(ErrorKind.InvalidArgument, "interpolation: non-finite knot"))
            }
            if index > 0 && xs.get(index) <= xs.get(index - 1) {
                return Err(new BasicError(ErrorKind.InvalidArgument, "interpolation: not increasing"))
            }
            index = index + 1
        }
        return Ok()
    }
}

// ---------- Numerics ----------
class Numerics {
    private Numerics() { }

    static Double defaultTolerance() { return 0.0000000001 }
    static Int defaultMaxIterations() { return 1000 }
    static Int defaultMaximumIterations() { return 1000 }
    static String backendName() { return "mini-native" }
    static String version() { return "1.0.0" }

    static List<Double> sortDoubles(List<Double> values) {
        List<Double> result = values.copy()
        Int index = 1
        while index < result.length() {
            Double current = result.get(index)
            Int position = index - 1
            while position >= 0 && result.get(position) > current {
                result.set(position + 1, result.get(position))
                position = position - 1
            }
            result.set(position + 1, current)
            index = index + 1
        }
        return result
    }

    static Void addUnique(List<Double> values, Double candidate) {
        Int index = 0
        while index < values.length() {
            if abs(values.get(index) - candidate) <= 0.000001 { return }
            index = index + 1
        }
        values.push(candidate)
    }
}

// ---------- BigInt ----------
class BigIntPair {
    final BigInt _quotient
    final BigInt _remainderValue
    BigIntPair(BigInt quotient, BigInt remainderValue) {
        self._quotient = quotient
        self._remainderValue = remainderValue
    }
    BigInt quotient() { return self._quotient }
    BigInt remainderValue() { return self._remainderValue }
}

class BigInt {
    final Bool _negative
    final List<Long> _limbs

    private BigInt(Bool negative, List<Long> limbs) {
        List<Long> normalized = []
        Int index = 0
        while index < limbs.length() {
            normalized.push(limbs.get(index) & 65535 as Long)
            index = index + 1
        }
        while normalized.length() > 0 {
            if normalized.get(normalized.length() - 1) != 0 as Long { break }
            normalized.remove(normalized.length() - 1)
        }
        Bool zero = normalized.length() == 0
        self._negative = zero ? false : negative
        self._limbs = normalized
    }

    static BigInt zero() {
        List<Long> limbs = []
        return new BigInt(false, limbs)
    }

    static BigInt one() {
        List<Long> limbs = []
        limbs.push(1 as Long)
        return new BigInt(false, limbs)
    }

    static BigInt fromInt(Int value) {
        return BigInt.fromLong(value as Long)
    }

    static BigInt fromLong(Long value) {
        Long minimum = -9223372036854775807 as Long - 1 as Long
        if value == minimum {
            List<Long> limbs = []
            limbs.push(0 as Long)
            limbs.push(0 as Long)
            limbs.push(0 as Long)
            limbs.push(32768 as Long)
            return new BigInt(true, limbs)
        }
        Bool negative = value < 0 as Long
        Long magnitude = value
        if negative { magnitude = -magnitude }
        List<Long> limbs = []
        while magnitude != 0 as Long {
            limbs.push(magnitude % 65536 as Long)
            magnitude = magnitude / 65536 as Long
        }
        return new BigInt(negative, limbs)
    }

    static Result<BigInt, Error> fromDoubleExact(Double value) {
        if !isFinite(value) || value != floor(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.fromDoubleExact: not an integer"))
        }
        if value > 9223372036854775807.0 || value < -9223372036854775808.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.fromDoubleExact: out of Long range"))
        }
        return Ok(BigInt.fromLong(value as Long))
    }

    static Result<BigInt, Error> parse(String text, Int maximumDigits) {
        if text == null { throw "BigInt.parse: null text" }
        if maximumDigits < 1 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.parse: invalid maximumDigits"))
        }
        if text == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "BigInt.parse: empty"))
        }
        Bool negative = false
        String digits = text
        if text.substring(0, 1) == "-" {
            negative = true
            digits = text.substring(1, text.length() - 1)
        } else if text.substring(0, 1) == "+" {
            digits = text.substring(1, text.length() - 1)
        }
        if digits == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "BigInt.parse: no digits"))
        }
        if digits.length() > maximumDigits {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.parse: too many digits"))
        }
        BigInt result = BigInt.zero()
        Int index = 0
        while index < digits.length() {
            Int code = digits.get(index)
            if code < 48 || code > 57 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "BigInt.parse: invalid digit"))
            }
            result = result.multiplySmall(10 as Long)
            result = result.addSmall((code - 48) as Long)
            index = index + 1
        }
        if negative { result = result.negate() }
        return Ok(result)
    }

    Bool isZero() { return self._limbs.length() == 0 }
    Bool isNegative() { return self._negative }
    Int signum() {
        if self.isZero() { return 0 }
        if self._negative { return -1 }
        return 1
    }

    Long bitLength() {
        if self.isZero() { return 0 as Long }
        Int top = self._limbs.length() - 1
        Long value = self._limbs.get(top)
        Long bits = 0 as Long
        while value != 0 as Long {
            bits = bits + 1 as Long
            value = value >> 1 as Long
        }
        return (top as Long) * 16 as Long + bits
    }

    BigInt abs() {
        return new BigInt(false, self._limbs)
    }

    BigInt negate() {
        if self.isZero() { return BigInt.zero() }
        return new BigInt(!self._negative, self._limbs)
    }

    BigInt add(BigInt other) {
        if other == null { throw "BigInt.add: null" }
        if self._negative == other._negative {
            return new BigInt(self._negative, self.addMagnitude(other._limbs))
        }
        Int comparison = self.compareMagnitude(other._limbs)
        if comparison == 0 { return BigInt.zero() }
        if comparison > 0 {
            return new BigInt(self._negative, self.subtractMagnitude(other._limbs))
        }
        return new BigInt(other._negative, other.subtractMagnitude(self._limbs))
    }

    BigInt subtract(BigInt other) {
        if other == null { throw "BigInt.subtract: null" }
        return self.add(other.negate())
    }

    BigInt multiply(BigInt other) {
        if other == null { throw "BigInt.multiply: null" }
        if self.isZero() || other.isZero() { return BigInt.zero() }
        Int leftLength = self._limbs.length()
        Int rightLength = other._limbs.length()
        List<Long> result = []
        Int initialize = 0
        while initialize < leftLength + rightLength + 1 {
            result.push(0 as Long)
            initialize = initialize + 1
        }
        Int leftIndex = 0
        while leftIndex < leftLength {
            Long carry = 0 as Long
            Int rightIndex = 0
            while rightIndex < rightLength {
                Int position = leftIndex + rightIndex
                Long current = result.get(position) +
                    self._limbs.get(leftIndex) * other._limbs.get(rightIndex) + carry
                result.set(position, current % 65536 as Long)
                carry = current / 65536 as Long
                rightIndex = rightIndex + 1
            }
            Int position = leftIndex + rightLength
            while carry != 0 as Long {
                Long current = result.get(position) + carry
                result.set(position, current % 65536 as Long)
                carry = current / 65536 as Long
                position = position + 1
            }
            leftIndex = leftIndex + 1
        }
        return new BigInt(self._negative != other._negative, result)
    }

    Result<BigInt, Error> divide(BigInt divisor) {
        Result<BigIntPair, Error> pair = self.divideAndRemainder(divisor)
        if pair.isErr() { return Err(pair.error()) }
        BigIntPair actual = pair.value()
        return Ok(actual.quotient())
    }

    Result<BigInt, Error> remainder(BigInt divisor) {
        Result<BigIntPair, Error> pair = self.divideAndRemainder(divisor)
        if pair.isErr() { return Err(pair.error()) }
        BigIntPair actual = pair.value()
        return Ok(actual.remainderValue())
    }

    Result<BigIntPair, Error> divideAndRemainder(BigInt divisor) {
        if divisor == null { throw "BigInt.divideAndRemainder: null" }
        if divisor.isZero() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "BigInt: divide by zero"))
        }
        if self.isZero() {
            return Ok(new BigIntPair(BigInt.zero(), BigInt.zero()))
        }
        BigInt dividendAbs = self.abs()
        BigInt divisorAbs = divisor.abs()
        if dividendAbs.compare(divisorAbs) < 0 {
            return Ok(new BigIntPair(BigInt.zero(), self))
        }
        Int shift = (dividendAbs.bitLength() - divisorAbs.bitLength()) as Int
        BigInt remainderValue = dividendAbs
        List<Long> quotientLimbs = []
        while shift >= 0 {
            BigInt candidate = divisorAbs.shiftLeftUnchecked(shift)
            if remainderValue.compare(candidate) >= 0 {
                remainderValue = remainderValue.subtract(candidate)
                BigInt.setMagnitudeBit(quotientLimbs, shift)
            }
            shift = shift - 1
        }
        Bool quotientNegative = self._negative != divisor._negative
        BigInt quotient = new BigInt(quotientNegative, quotientLimbs)
        BigInt remainderResult = new BigInt(self._negative, remainderValue._limbs)
        return Ok(new BigIntPair(quotient, remainderResult))
    }

    Result<BigInt, Error> mod(BigInt modulus) {
        if modulus == null { throw "BigInt.mod: null" }
        if modulus.signum() <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.mod: modulus must be positive"))
        }
        Result<BigInt, Error> remainderValue = self.remainder(modulus)
        if remainderValue.isErr() { return Err(remainderValue.error()) }
        BigInt result = remainderValue.value()
        if result._negative { result = result.add(modulus) }
        return Ok(result)
    }

    Result<BigInt, Error> pow(Context context, Int exponent) {
        if context == null { throw "BigInt.pow: null context" }
        if exponent < 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.pow: negative exponent"))
        }
        BigInt result = BigInt.one()
        BigInt base = self
        Int remaining = exponent
        while remaining > 0 {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled, "BigInt.pow cancelled"))
            }
            if remaining % 2 == 1 {
                result = result.multiply(base)
            }
            remaining = remaining / 2
            if remaining > 0 { base = base.multiply(base) }
        }
        return Ok(result)
    }

    Result<BigInt, Error> modPow(Context context, BigInt exponent, BigInt modulus) {
        if context == null || exponent == null || modulus == null {
            throw "BigInt.modPow: null argument"
        }
        if exponent._negative {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.modPow: negative exponent"))
        }
        if modulus.signum() <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.modPow: modulus must be positive"))
        }
        BigInt result = BigInt.one().mod(modulus).value()
        BigInt base = self.mod(modulus).value()
        BigInt remaining = exponent
        while !remaining.isZero() {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled, "BigInt.modPow cancelled"))
            }
            if remaining.testBit(0) {
                result = result.multiply(base).mod(modulus).value()
            }
            remaining = remaining.shiftRightUnchecked(1)
            if !remaining.isZero() {
                base = base.multiply(base).mod(modulus).value()
            }
        }
        return Ok(result)
    }

    Result<BigInt, Error> modInverse(BigInt modulus) {
        if modulus == null { throw "BigInt.modInverse: null" }
        if modulus.compare(BigInt.one()) <= 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.modInverse: modulus must exceed one"))
        }
        BigInt a = self.mod(modulus).value()
        BigInt oldR = modulus
        BigInt r = a
        BigInt oldT = BigInt.zero()
        BigInt t = BigInt.one()
        while !r.isZero() {
            BigInt quotient = oldR.divide(r).value()
            BigInt nextR = oldR.subtract(quotient.multiply(r))
            BigInt nextT = oldT.subtract(quotient.multiply(t))
            oldR = r
            r = nextR
            oldT = t
            t = nextT
        }
        if oldR.compare(BigInt.one()) != 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.modInverse: not invertible"))
        }
        return Ok(oldT.mod(modulus).value())
    }

    BigInt gcd(BigInt other) {
        if other == null { throw "BigInt.gcd: null" }
        BigInt a = self.abs()
        BigInt b = other.abs()
        while !b.isZero() {
            BigInt remainderValue = a.remainder(b).value()
            a = b
            b = remainderValue
        }
        return a
    }

    BigInt lcm(BigInt other) {
        if other == null { throw "BigInt.lcm: null" }
        if self.isZero() || other.isZero() { return BigInt.zero() }
        BigInt divisor = self.gcd(other)
        return self.divide(divisor).value().multiply(other).abs()
    }

    Result<BigInt, Error> shiftLeft(Int bitCount) {
        if bitCount < 0 || bitCount > 1000000 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.shiftLeft: invalid bit count"))
        }
        return Ok(self.shiftLeftUnchecked(bitCount))
    }

    Result<BigInt, Error> shiftRight(Int bitCount) {
        if bitCount < 0 || bitCount > 1000000 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.shiftRight: invalid bit count"))
        }
        return Ok(self.shiftRightUnchecked(bitCount))
    }

    Bool testBit(Int bitIndex) {
        if bitIndex < 0 { throw "BigInt.testBit: negative index" }
        Int limbIndex = bitIndex / 16
        if limbIndex >= self._limbs.length() { return false }
        Long shifted = self._limbs.get(limbIndex) >> (bitIndex % 16) as Long
        return (shifted & 1 as Long) == 1 as Long
    }

    Result<BigInt, Error> sqrt(Context context) {
        if context == null { throw "BigInt.sqrt: null context" }
        if self._negative {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "BigInt.sqrt: negative"))
        }
        if self.isZero() { return Ok(BigInt.zero()) }
        Long length = self.bitLength()
        Int shift = ((length + 1 as Long) / 2 as Long) as Int
        BigInt estimate = BigInt.one().shiftLeftUnchecked(shift)
        while true {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled, "BigInt.sqrt cancelled"))
            }
            BigInt quotient = self.divide(estimate).value()
            BigInt next = estimate.add(quotient).shiftRightUnchecked(1)
            if next.compare(estimate) >= 0 { return Ok(estimate) }
            estimate = next
        }
    }

    Int compare(BigInt other) {
        if other == null { throw "BigInt.compare: null" }
        if self._negative != other._negative {
            return self._negative ? -1 : 1
        }
        Int magnitude = self.compareMagnitude(other._limbs)
        if self._negative { return -magnitude }
        return magnitude
    }

    Bool equals(BigInt other) {
        if other == null { return false }
        return self._negative == other._negative &&
            self.compareMagnitude(other._limbs) == 0
    }

    Result<Int, Error> toInt() {
        Result<Long, Error> value = self.toLong()
        if value.isErr() { return Err(value.error()) }
        Long actual = value.value()
        if actual > 2147483647 as Long || actual < -2147483648 as Long {
            return Err(new BasicError(ErrorKind.InvalidArgument, "BigInt.toInt: overflow"))
        }
        return Ok(actual as Int)
    }

    Result<Long, Error> toLong() {
        Bool isMinimumNegative = self._negative && self._limbs.length() == 4 &&
            self._limbs.get(0) == 0 as Long && self._limbs.get(1) == 0 as Long &&
            self._limbs.get(2) == 0 as Long && self._limbs.get(3) == 32768 as Long
        if isMinimumNegative {
            return Ok(-9223372036854775807 as Long - 1 as Long)
        }
        if self._limbs.length() > 4 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "BigInt.toLong: overflow"))
        }
        Long maximum = 9223372036854775807 as Long
        Long magnitude = 0 as Long
        Int index = self._limbs.length() - 1
        while index >= 0 {
            Long limb = self._limbs.get(index)
            if magnitude > (maximum - limb) / 65536 as Long {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "BigInt.toLong: overflow"))
            }
            magnitude = magnitude * 65536 as Long + limb
            index = index - 1
        }
        if !self._negative { return Ok(magnitude) }
        return Ok(-magnitude)
    }

    Double toDouble() {
        Double result = 0.0
        Int index = self._limbs.length() - 1
        while index >= 0 {
            result = result * 65536.0 + (self._limbs.get(index) as Double)
            index = index - 1
        }
        if self._negative { return -result }
        return result
    }

    String toString() {
        if self.isZero() { return "0" }
        BigInt remaining = self.abs()
        String digits = ""
        while !remaining.isZero() {
            Long remainderValue = 0 as Long
            List<Long> quotient = []
            Int length = remaining._limbs.length()
            Int fill = 0
            while fill < length {
                quotient.push(0 as Long)
                fill = fill + 1
            }
            Int index = length - 1
            while index >= 0 {
                Long current = remainderValue * 65536 as Long + remaining._limbs.get(index)
                quotient.set(index, current / 10 as Long)
                remainderValue = current % 10 as Long
                index = index - 1
            }
            BigInt nextValue = new BigInt(false, quotient)
            remaining = nextValue
            Int digit = remainderValue as Int
            digits = str(digit) + digits
        }
        if self._negative { return "-" + digits }
        return digits
    }

    // ---------- internal helpers ----------
    private List<Long> addMagnitude(List<Long> other) {
        List<Long> result = []
        Long carry = 0 as Long
        Int index = 0
        Int maximum = self._limbs.length()
        if other.length() > maximum { maximum = other.length() }
        while index < maximum {
            Long left = 0 as Long
            if index < self._limbs.length() { left = self._limbs.get(index) }
            Long right = 0 as Long
            if index < other.length() { right = other.get(index) }
            Long current = left + right + carry
            result.push(current % 65536 as Long)
            carry = current / 65536 as Long
            index = index + 1
        }
        if carry != 0 as Long { result.push(carry) }
        return result
    }

    private List<Long> subtractMagnitude(List<Long> other) {
        List<Long> result = []
        Long borrow = 0 as Long
        Int index = 0
        while index < self._limbs.length() {
            Long left = self._limbs.get(index) - borrow
            Long right = 0 as Long
            if index < other.length() { right = other.get(index) }
            if left < right {
                left = left + 65536 as Long
                borrow = 1 as Long
            } else {
                borrow = 0 as Long
            }
            result.push(left - right)
            index = index + 1
        }
        return result
    }

    private Int compareMagnitude(List<Long> other) {
        if self._limbs.length() != other.length() {
            return self._limbs.length() < other.length() ? -1 : 1
        }
        Int index = self._limbs.length() - 1
        while index >= 0 {
            Long left = self._limbs.get(index)
            Long right = other.get(index)
            if left < right { return -1 }
            if left > right { return 1 }
            index = index - 1
        }
        return 0
    }

    private BigInt multiplySmall(Long factor) {
        if factor == 0 as Long || self.isZero() { return BigInt.zero() }
        List<Long> result = []
        Long carry = 0 as Long
        Int index = 0
        while index < self._limbs.length() {
            Long current = self._limbs.get(index) * factor + carry
            result.push(current % 65536 as Long)
            carry = current / 65536 as Long
            index = index + 1
        }
        while carry != 0 as Long {
            result.push(carry % 65536 as Long)
            carry = carry / 65536 as Long
        }
        return new BigInt(self._negative, result)
    }

    private BigInt addSmall(Long value) {
        if value == 0 as Long { return self }
        List<Long> result = self._limbs.copy()
        Long carry = value
        Int index = 0
        while carry != 0 as Long {
            if index >= result.length() { result.push(0 as Long) }
            Long current = result.get(index) + carry
            result.set(index, current % 65536 as Long)
            carry = current / 65536 as Long
            index = index + 1
        }
        return new BigInt(self._negative, result)
    }

    private BigInt shiftLeftUnchecked(Int bits) {
        if self.isZero() || bits == 0 { return self }
        Int wordShift = bits / 16
        Int bitShift = bits % 16
        List<Long> result = []
        Int pad = 0
        while pad < wordShift {
            result.push(0 as Long)
            pad = pad + 1
        }
        Long carry = 0 as Long
        Int index = 0
        while index < self._limbs.length() {
            Long current = self._limbs.get(index)
            if bitShift == 0 {
                result.push(current)
                carry = 0 as Long
            } else {
                Long combined = (current << bitShift as Long) + carry
                result.push(combined & 65535 as Long)
                carry = combined >> 16 as Long
            }
            index = index + 1
        }
        if carry != 0 as Long { result.push(carry) }
        return new BigInt(self._negative, result)
    }

    private BigInt shiftRightUnchecked(Int bits) {
        if self.isZero() || bits == 0 { return self }
        Int wordShift = bits / 16
        Int bitShift = bits % 16
        if wordShift >= self._limbs.length() { return BigInt.zero() }
        List<Long> result = []
        Int index = wordShift
        while index < self._limbs.length() {
            Long current = self._limbs.get(index) >> bitShift as Long
            if bitShift > 0 && index + 1 < self._limbs.length() {
                current = current | ((self._limbs.get(index + 1) << (16 - bitShift) as Long) & 65535 as Long)
            }
            result.push(current)
            index = index + 1
        }
        return new BigInt(self._negative, result)
    }

    private static Void setMagnitudeBit(List<Long> limbs, Int bitIndex) {
        Int limbIndex = bitIndex / 16
        while limbs.length() <= limbIndex {
            limbs.push(0 as Long)
        }
        Long current = limbs.get(limbIndex)
        limbs.set(limbIndex, current | (1 as Long << (bitIndex % 16) as Long))
    }
}

// ---------- Integration ----------
class Integration {
    private Integration() { }

    static Result<Double, Error> integrate(Context context, Double(Double) integrand,
                                            Double lower, Double upper,
                                            Double tolerance, Int maximumIntervals) {
        return Integration.integrateSimpson(context, integrand, lower, upper,
            tolerance, maximumIntervals)
    }

    static Result<Double, Error> integrateSimpson(Context context,
            Double(Double) integrand, Double lower, Double upper, Double tolerance,
            Int maximumDepth) {
        if context == null {
            throw "Integration.integrateSimpson: null argument"
        }
        Result<Unit, Error> valid = numericsValidateInterval(lower, upper, tolerance,
            maximumDepth)
        if valid.isErr() { return Err(valid.error()) }
        Double left = lower
        Double right = upper
        Bool reversed = false
        if left > right {
            Double temporary = left
            left = right
            right = temporary
            reversed = true
        }
        if left == right { return Ok(0.0) }
        Double middle = (left + right) / 2.0
        Double fLeft = integrand(left)
        Double fMiddle = integrand(middle)
        Double fRight = integrand(right)
        if !isFinite(fLeft) || !isFinite(fMiddle) || !isFinite(fRight) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Integration: non-finite integrand"))
        }
        Double whole = (right - left) / 6.0 *
            (fLeft + 4.0 * fMiddle + fRight)
        Double epsilon = tolerance * 15.0
        Result<Double, Error> value = Integration.simpsonRecursive(context,
            integrand, left, right, fLeft, fMiddle, fRight, whole, epsilon,
            maximumDepth)
        if value.isErr() { return Err(value.error()) }
        if reversed { return Ok(-value.value()) }
        return value
    }

    private static Result<Double, Error> simpsonRecursive(Context context,
            Double(Double) integrand, Double left, Double right, Double fLeft,
            Double fMiddle, Double fRight, Double whole, Double epsilon, Int depth) {
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "integration cancelled"))
        }
        Double middle = (left + right) / 2.0
        Double leftMiddle = (left + middle) / 2.0
        Double rightMiddle = (middle + right) / 2.0
        Double fLeftMiddle = integrand(leftMiddle)
        Double fRightMiddle = integrand(rightMiddle)
        if !isFinite(fLeftMiddle) || !isFinite(fRightMiddle) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Integration: non-finite integrand"))
        }
        Double leftWhole = (middle - left) / 6.0 *
            (fLeft + 4.0 * fLeftMiddle + fMiddle)
        Double rightWhole = (right - middle) / 6.0 *
            (fMiddle + 4.0 * fRightMiddle + fRight)
        Double combined = leftWhole + rightWhole
        Double delta = combined - whole
        if depth <= 0 || abs(delta) <= epsilon {
            return Ok(combined + delta / 15.0)
        }
        Result<Double, Error> leftPart = Integration.simpsonRecursive(context,
            integrand, left, middle, fLeft, fLeftMiddle, fMiddle, leftWhole,
            epsilon / 2.0, depth - 1)
        if leftPart.isErr() { return Err(leftPart.error()) }
        Result<Double, Error> rightPart = Integration.simpsonRecursive(context,
            integrand, middle, right, fMiddle, fRightMiddle, fRight, rightWhole,
            epsilon / 2.0, depth - 1)
        if rightPart.isErr() { return Err(rightPart.error()) }
        return Ok(leftPart.value() + rightPart.value())
    }

    static Result<Double, Error> integrateGaussLegendre(Context context,
            Double(Double) integrand, Double lower, Double upper, Int order) {
        if context == null {
            throw "Integration.integrateGaussLegendre: null argument"
        }
        if order < 1 || order > 64 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Integration: order must be 1..64"))
        }
        if !isFinite(lower) || !isFinite(upper) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Integration: non-finite bound"))
        }
        if lower == upper { return Ok(0.0) }
        Double half = (upper - lower) / 2.0
        Double center = (lower + upper) / 2.0
        Double sum = 0.0
        Int index = 0
        while index < order {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "integration cancelled"))
            }
            Double node = Integration.legendreNode(order, index)
            Double weight = Integration.legendreWeight(order, index)
            Double value = integrand(center + half * node)
            if !isFinite(value) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "Integration: non-finite integrand"))
            }
            sum = sum + weight * value
            index = index + 1
        }
        return Ok(half * sum)
    }

    static Result<Double, Error> integrateTanhSinh(Context context,
            Double(Double) integrand, Double lower, Double upper, Double tolerance,
            Int maximumLevel) {
        if context == null {
            throw "Integration.integrateTanhSinh: null argument"
        }
        Result<Unit, Error> valid = numericsValidateInterval(lower, upper, tolerance,
            maximumLevel)
        if valid.isErr() { return Err(valid.error()) }
        if lower == upper { return Ok(0.0) }
        Double half = (upper - lower) / 2.0
        Double center = (lower + upper) / 2.0
        Double previous = 0.0
        Int level = 1
        Double cutoff = 6.0
        while level <= maximumLevel {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "integration cancelled"))
            }
            Double step = 1.0 / pow(2.0, level as Double)
            Double sum = 0.0
            Int terms = (cutoff / step) as Int
            Int index = -terms
            while index <= terms {
                Double t = (index as Double) * step
                Double sinhValue = sinh((3.141592653589793 / 2.0) * t)
                Double x = tanh(sinhValue)
                Double weight = (3.141592653589793 / 2.0) *
                    cosh((3.141592653589793 / 2.0) * t) * (1.0 - x * x)
                Double value = integrand(center + half * x)
                if !isFinite(value) {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "Integration: non-finite integrand"))
                }
                sum = sum + weight * value
                index = index + 1
            }
            Double current = half * step * sum
            if level > 1 && abs(current - previous) <= tolerance *
                (1.0 + abs(current)) {
                return Ok(current)
            }
            previous = current
            level = level + 1
        }
        return Ok(previous)
    }

    static Result<Double, Error> integrateInfinite(Context context,
            Double(Double) integrand, Double lower, Double upper, Double tolerance,
            Int maximumLevel) {
        if context == null {
            throw "Integration.integrateInfinite: null argument"
        }
        if tolerance <= 0.0 || maximumLevel < 1 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Integration: invalid parameter"))
        }
        Bool lowerInfinite = !isFinite(lower)
        Bool upperInfinite = !isFinite(upper)
        if !lowerInfinite && !upperInfinite {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Integration: at least one bound must be infinite"))
        }
        Double sum = 0.0
        Int index = 0
        Int order = 64
        while index < order {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "integration cancelled"))
            }
            Double node = Integration.legendreNode(order, index)
            Double weight = Integration.legendreWeight(order, index)
            Double u = 0.5 * (node + 1.0)
            Double x = 0.0
            Double jacobian = 0.0
            if lowerInfinite && upperInfinite {
                x = tan(3.141592653589793 * (u - 0.5))
                Double cosine = cos(3.141592653589793 * (u - 0.5))
                jacobian = 3.141592653589793 / (cosine * cosine)
            } else if upperInfinite {
                Double denominator = 1.0 - u
                x = lower + u / denominator
                jacobian = 1.0 / (denominator * denominator)
            } else {
                Double denominator = 1.0 - u
                x = upper - u / denominator
                jacobian = 1.0 / (denominator * denominator)
            }
            Double value = integrand(x)
            if !isFinite(value) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "Integration: non-finite integrand"))
            }
            sum = sum + weight * value * jacobian * 0.5
            index = index + 1
        }
        return Ok(sum)
    }

    private static Double legendreNode(Int order, Int index) {
        Double x = cos(3.141592653589793 * (index as Double + 0.75) /
            (order as Double + 0.5))
        Int iteration = 0
        while iteration < 20 {
            Double p0 = 1.0
            Double p1 = x
            Int k = 2
            while k <= order {
                Double p2 = ((2.0 * k as Double - 1.0) * x * p1 -
                    (k as Double - 1.0) * p0) / (k as Double)
                p0 = p1
                p1 = p2
                k = k + 1
            }
            Double derivative = order as Double * (x * p1 - p0) / (x * x - 1.0)
            Double next = x - p1 / derivative
            if abs(next - x) < 0.000000000000001 { x = next; break }
            x = next
            iteration = iteration + 1
        }
        return x
    }

    private static Double legendreWeight(Int order, Int index) {
        Double x = Integration.legendreNode(order, index)
        Double p0 = 1.0
        Double p1 = x
        Int k = 2
        while k <= order {
            Double p2 = ((2.0 * k as Double - 1.0) * x * p1 -
                (k as Double - 1.0) * p0) / (k as Double)
            p0 = p1
            p1 = p2
            k = k + 1
        }
        Double derivative = order as Double * (x * p1 - p0) / (x * x - 1.0)
        return 2.0 / ((1.0 - x * x) * derivative * derivative)
    }
}

static Result<Unit, Error> numericsValidateInterval(Double lower, Double upper,
                                                     Double tolerance, Int maximum) {
    if !isFinite(lower) || !isFinite(upper) {
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "Integration: non-finite bound"))
    }
    if tolerance <= 0.0 || !isFinite(tolerance) {
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "Integration: invalid tolerance"))
    }
    if maximum < 1 {
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "Integration: invalid maximum"))
    }
    return Ok()
}

// ---------- Optimization ----------
class Optimization {
    private Optimization() { }

    static Result<Pair<Double, Double>, Error> minimizeBounded(Context context,
            Double(Double) objective, Double lower, Double upper, Double tolerance,
            Int maximumIterations) {
        if context == null {
            throw "Optimization.minimizeBounded: null argument"
        }
        if !isFinite(lower) || !isFinite(upper) || lower >= upper ||
            tolerance <= 0.0 || maximumIterations < 1 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Optimization: invalid bounded parameter"))
        }
        Double golden = 0.6180339887498949
        Double a = lower
        Double b = upper
        Double x = a + golden * (b - a)
        Double w = x
        Double v = x
        Double fx = objective(x)
        Double fw = fx
        Double fv = fx
        Double d = 0.0
        Double e = 0.0
        Int iteration = 0
        while iteration < maximumIterations {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "optimization cancelled"))
            }
            Double middle = 0.5 * (a + b)
            Double toleranceX = tolerance * (abs(x) + 1.0)
            if abs(x - middle) <= 2.0 * toleranceX - 0.5 * (b - a) {
                return Ok(new Pair<Double, Double>(x, fx))
            }
            Bool parabolic = false
            Double u = 0.0
            if abs(e) > toleranceX {
                Double r = (x - w) * (fx - fv)
                Double q = (x - v) * (fx - fw)
                Double p = (x - v) * q - (x - w) * r
                q = 2.0 * (q - r)
                if q > 0.0 { p = -p }
                q = abs(q)
                Double previousE = e
                e = d
                if abs(p) < abs(0.5 * q * previousE) && p > q * (a - x) &&
                    p < q * (b - x) {
                    d = p / q
                    u = x + d
                    if u - a < 2.0 * toleranceX || b - u < 2.0 * toleranceX {
                        d = x < middle ? toleranceX : -toleranceX
                    }
                    parabolic = true
                }
            }
            if !parabolic {
                e = x < middle ? b - x : a - x
                d = golden * e
            }
            u = x + (abs(d) >= toleranceX ? d : (d > 0.0 ? toleranceX : -toleranceX))
            Double fu = objective(u)
            if !isFinite(fu) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "Optimization: non-finite objective"))
            }
            if fu <= fx {
                if u < x { b = x } else { a = x }
                v = w
                fv = fw
                w = x
                fw = fx
                x = u
                fx = fu
            } else {
                if u < x { a = u } else { b = u }
                if fu <= fw || w == x {
                    v = w
                    fv = fw
                    w = u
                    fw = fu
                } else if fu <= fv || v == x || v == w {
                    v = u
                    fv = fu
                }
            }
            iteration = iteration + 1
        }
        return Err(new BasicError(ErrorKind.Internal,
            "Optimization: bounded did not converge"))
    }

    static Result<Pair<Double, Double>, Error> minimize1d(Context context,
            Double(Double) objective, Double initialPoint, Double initialStep,
            Double tolerance, Int maximumIterations) {
        if context == null {
            throw "Optimization.minimize1d: null argument"
        }
        if !isFinite(initialPoint) || !isFinite(initialStep) || initialStep == 0.0 ||
            tolerance <= 0.0 || maximumIterations < 1 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Optimization: invalid 1d parameter"))
        }
        Double a = initialPoint
        Double b = initialPoint + initialStep
        Double fa = objective(a)
        Double fb = objective(b)
        if !isFinite(fa) || !isFinite(fb) {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Optimization: non-finite objective"))
        }
        if fb > fa {
            Double temporary = a
            a = b
            b = temporary
            Double temporaryValue = fa
            fa = fb
            fb = temporaryValue
        }
        Double c = b + 1.6180339887498949 * (b - a)
        Double fc = objective(c)
        Int bracket = 0
        while fc < fb && bracket < maximumIterations {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "optimization cancelled"))
            }
            a = b
            fa = fb
            b = c
            fb = fc
            c = b + 1.6180339887498949 * (b - a)
            fc = objective(c)
            if !isFinite(fc) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "Optimization: non-finite objective"))
            }
            bracket = bracket + 1
        }
        Double lower = a < c ? a : c
        Double upper = a < c ? c : a
        return Optimization.minimizeBounded(context, objective, lower, upper,
            tolerance, maximumIterations)
    }

    static Result<Pair<List<Double>, Double>, Error> minimizeNelderMead(
            Context context, Double(List<Double>) objective, List<Double> initialPoint,
            Double tolerance, Int maximumIterations) {
        if context == null || initialPoint == null {
            throw "Optimization.minimizeNelderMead: null argument"
        }
        Int dimension = initialPoint.length()
        if dimension == 0 || tolerance <= 0.0 || maximumIterations < 1 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Optimization: invalid Nelder-Mead parameter"))
        }
        List<List<Double>> simplex = []
        Int index = 0
        while index <= dimension {
            List<Double> point = initialPoint.copy()
            if index > 0 {
                Double value = point.get(index - 1)
                point.set(index - 1, value + (value == 0.0 ? 0.00025 : 0.05 * value))
            }
            simplex.push(point)
            index = index + 1
        }
        List<Double> values = []
        index = 0
        while index < simplex.length() {
            Double value = objective(simplex.get(index))
            if !isFinite(value) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "Optimization: non-finite objective"))
            }
            values.push(value)
            index = index + 1
        }
        Int iteration = 0
        while iteration < maximumIterations {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "optimization cancelled"))
            }
            Optimization.sortSimplex(simplex, values)
            Double spread = abs(values.get(values.length() - 1) - values.get(0))
            Double size = 0.0
            Int pointIndex = 1
            while pointIndex < simplex.length() {
                Int coordinate = 0
                while coordinate < dimension {
                    Double difference = abs(simplex.get(pointIndex).get(coordinate) -
                        simplex.get(0).get(coordinate))
                    if difference > size { size = difference }
                    coordinate = coordinate + 1
                }
                pointIndex = pointIndex + 1
            }
            if spread <= tolerance && size <= tolerance {
                return Ok(new Pair<List<Double>, Double>(simplex.get(0).copy(),
                    values.get(0)))
            }
            List<Double> centroid = []
            Int coordinate = 0
            while coordinate < dimension {
                Double total = 0.0
                pointIndex = 0
                while pointIndex < dimension {
                    total = total + simplex.get(pointIndex).get(coordinate)
                    pointIndex = pointIndex + 1
                }
                centroid.push(total / dimension as Double)
                coordinate = coordinate + 1
            }
            List<Double> worst = simplex.get(dimension)
            List<Double> reflected = Optimization.affine(centroid, worst, 1.0)
            Double reflectedValue = objective(reflected)
            if reflectedValue < values.get(0) {
                List<Double> expanded = Optimization.affine(centroid, worst, 2.0)
                Double expandedValue = objective(expanded)
                if expandedValue < reflectedValue {
                    simplex.set(dimension, expanded)
                    values.set(dimension, expandedValue)
                } else {
                    simplex.set(dimension, reflected)
                    values.set(dimension, reflectedValue)
                }
            } else if reflectedValue < values.get(dimension - 1) {
                simplex.set(dimension, reflected)
                values.set(dimension, reflectedValue)
            } else {
                List<Double> contracted = Optimization.affine(centroid, worst, 0.5)
                Double contractedValue = objective(contracted)
                if contractedValue < values.get(dimension) {
                    simplex.set(dimension, contracted)
                    values.set(dimension, contractedValue)
                } else {
                    pointIndex = 1
                    while pointIndex < simplex.length() {
                        Int c = 0
                        while c < dimension {
                            Double next = simplex.get(0).get(c) +
                                0.5 * (simplex.get(pointIndex).get(c) - simplex.get(0).get(c))
                            simplex.get(pointIndex).set(c, next)
                            c = c + 1
                        }
                        values.set(pointIndex, objective(simplex.get(pointIndex)))
                        pointIndex = pointIndex + 1
                    }
                }
            }
            if !isFinite(values.get(dimension)) {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "Optimization: non-finite objective"))
            }
            iteration = iteration + 1
        }
        return Err(new BasicError(ErrorKind.Internal,
            "Optimization: Nelder-Mead did not converge"))
    }

    static Result<Pair<List<Double>, Double>, Error> minimizeBfgs(Context context,
            Double(List<Double>) objective, List<Double>(List<Double>) gradient,
            List<Double> initialPoint, Double tolerance, Int maximumIterations) {
        if context == null || initialPoint == null {
            throw "Optimization.minimizeBfgs: null argument"
        }
        Int dimension = initialPoint.length()
        if dimension == 0 || tolerance <= 0.0 || maximumIterations < 1 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Optimization: invalid BFGS parameter"))
        }
        List<Double> point = initialPoint.copy()
        List<Double> inverseHessian = []
        Int row = 0
        while row < dimension * dimension {
            inverseHessian.push(0.0)
            row = row + 1
        }
        Int diagonal = 0
        while diagonal < dimension {
            inverseHessian.set(diagonal * dimension + diagonal, 1.0)
            diagonal = diagonal + 1
        }
        Double value = objective(point)
        Int iteration = 0
        while iteration < maximumIterations {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled,
                    "optimization cancelled"))
            }
            List<Double> slope = gradient(point)
            if slope.length() != dimension {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "Optimization: gradient dimension mismatch"))
            }
            Double maximumSlope = 0.0
            Int index = 0
            while index < dimension {
                Double absolute = abs(slope.get(index))
                if absolute > maximumSlope { maximumSlope = absolute }
                index = index + 1
            }
            if maximumSlope <= tolerance {
                return Ok(new Pair<List<Double>, Double>(point, value))
            }
            List<Double> direction = []
            index = 0
            while index < dimension {
                Double total = 0.0
                Int column = 0
                while column < dimension {
                    total = total + inverseHessian.get(index * dimension + column) *
                        slope.get(column)
                    column = column + 1
                }
                direction.push(-total)
                index = index + 1
            }
            Double slopeDotDirection = Optimization.dot(slope, direction)
            if slopeDotDirection >= 0.0 {
                index = 0
                while index < dimension {
                    direction.set(index, -slope.get(index))
                    index = index + 1
                }
                Optimization.identity(inverseHessian, dimension)
                slopeDotDirection = Optimization.dot(slope, direction)
            }
            Double alpha = 1.0
            List<Double> candidate = point.copy()
            Double candidateValue = value
            Int lineSearch = 0
            while lineSearch < 40 {
                index = 0
                while index < dimension {
                    candidate.set(index, point.get(index) + alpha * direction.get(index))
                    index = index + 1
                }
                candidateValue = objective(candidate)
                if candidateValue <= value + 0.0001 * alpha * slopeDotDirection {
                    break
                }
                alpha = alpha * 0.5
                lineSearch = lineSearch + 1
            }
            if lineSearch >= 40 {
                return Err(new BasicError(ErrorKind.Internal,
                    "Optimization: BFGS line search failed"))
            }
            List<Double> newSlope = gradient(candidate)
            List<Double> step = []
            List<Double> change = []
            index = 0
            while index < dimension {
                step.push(candidate.get(index) - point.get(index))
                change.push(newSlope.get(index) - slope.get(index))
                index = index + 1
            }
            Double curvature = Optimization.dot(change, step)
            if curvature > 0.000000000001 {
                Double factor = (curvature + Optimization.quadratic(inverseHessian,
                    change, change)) / (curvature * curvature)
                Int i = 0
                while i < dimension {
                    Int j = 0
                    while j < dimension {
                        Double left = i == j ? 1.0 : 0.0
                        left = left - change.get(i) * step.get(j) / curvature
                        Double right = i == j ? 1.0 : 0.0
                        right = right - step.get(i) * change.get(j) / curvature
                        Double updated = inverseHessian.get(i * dimension + j)
                        Int k = 0
                        while k < dimension {
                            Int l = 0
                            while l < dimension {
                                updated = updated + left * inverseHessian.get(i * dimension + k)
                                updated = updated + factor * change.get(i) * change.get(j)
                                l = l + 1
                            }
                            k = k + 1
                        }
                        inverseHessian.set(i * dimension + j, updated)
                        j = j + 1
                    }
                    i = i + 1
                }
            }
            point = candidate
            value = candidateValue
            index = 0
            Double stepSize = 0.0
            while index < dimension {
                if abs(step.get(index)) > stepSize { stepSize = abs(step.get(index)) }
                index = index + 1
            }
            if stepSize <= tolerance {
                return Ok(new Pair<List<Double>, Double>(point, value))
            }
            iteration = iteration + 1
        }
        return Err(new BasicError(ErrorKind.Internal,
            "Optimization: BFGS did not converge"))
    }

    static Result<Pair<List<Double>, Double>, Error> minimize(Context context,
            Double(List<Double>) objective, List<Double> initialPoint,
            Double tolerance, Int maximumIterations) {
        return Optimization.minimizeNelderMead(context, objective, initialPoint,
            tolerance, maximumIterations)
    }

    private static Void sortSimplex(List<List<Double>> points, List<Double> values) {
        Int index = 1
        while index < values.length() {
            Double currentValue = values.get(index)
            List<Double> currentPoint = points.get(index)
            Int position = index - 1
            while position >= 0 && values.get(position) > currentValue {
                values.set(position + 1, values.get(position))
                points.set(position + 1, points.get(position))
                position = position - 1
            }
            values.set(position + 1, currentValue)
            points.set(position + 1, currentPoint)
            index = index + 1
        }
    }

    private static List<Double> affine(List<Double> centroid, List<Double> worst,
                                        Double factor) {
        List<Double> result = []
        Int index = 0
        while index < centroid.length() {
            result.push(centroid.get(index) +
                factor * (centroid.get(index) - worst.get(index)))
            index = index + 1
        }
        return result
    }

    private static Double dot(List<Double> left, List<Double> right) {
        Double total = 0.0
        Int index = 0
        while index < left.length() {
            total = total + left.get(index) * right.get(index)
            index = index + 1
        }
        return total
    }

    private static Double quadratic(List<Double> matrix, List<Double> left,
                                    List<Double> right) {
        Double total = 0.0
        Int dimension = left.length()
        Int i = 0
        while i < dimension {
            Int j = 0
            while j < dimension {
                total = total + left.get(i) * matrix.get(i * dimension + j) *
                    right.get(j)
                j = j + 1
            }
            i = i + 1
        }
        return total
    }

    private static Void identity(List<Double> matrix, Int dimension) {
        Int index = 0
        while index < dimension * dimension {
            matrix.set(index, 0.0)
            index = index + 1
        }
        Int diagonal = 0
        while diagonal < dimension {
            matrix.set(diagonal * dimension + diagonal, 1.0)
            diagonal = diagonal + 1
        }
    }
}

// ---------- OdeSolver ----------
class OdeSolver {
    private OdeSolver() { }

    static Result<Pair<List<Double>, List<List<Double>>>, Error> solveRk4(
            Context context, List<Double>(Double, List<Double>) derivative,
            Double initialTime, List<Double> initialState, Double endTime,
            Double stepSize, Int maximumSteps) {
        if context == null || initialState == null {
            throw "OdeSolver.solveRk4: null argument"
        }
        Result<Unit, Error> valid = odeValidate(initialTime, endTime, stepSize,
            maximumSteps, initialState.length())
        if valid.isErr() { return Err(valid.error()) }
        List<Double> times = []
        List<List<Double>> states = []
        Double time = initialTime
        List<Double> state = initialState.copy()
        times.push(time)
        states.push(state.copy())
        Int step = 0
        while time < endTime && step < maximumSteps {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled, "ode cancelled"))
            }
            Double h = stepSize
            if time + h > endTime { h = endTime - time }
            List<Double> k1 = derivative(time, state)
            List<Double> y2 = odeAddScaled(state, k1, h / 2.0)
            List<Double> k2 = derivative(time + h / 2.0, y2)
            List<Double> y3 = odeAddScaled(state, k2, h / 2.0)
            List<Double> k3 = derivative(time + h / 2.0, y3)
            List<Double> y4 = odeAddScaled(state, k3, h)
            List<Double> k4 = derivative(time + h, y4)
            List<Double> next = []
            Int index = 0
            while index < state.length() {
                Double value = state.get(index) + h / 6.0 * (k1.get(index) +
                    2.0 * k2.get(index) + 2.0 * k3.get(index) +
                    k4.get(index))
                if !isFinite(value) {
                    return Err(new BasicError(ErrorKind.Internal,
                        "OdeSolver: non-finite state"))
                }
                next.push(value)
                index = index + 1
            }
            time = time + h
            state = next
            times.push(time)
            states.push(state.copy())
            step = step + 1
        }
        if time < endTime {
            return Err(new BasicError(ErrorKind.Internal,
                "OdeSolver: maximum steps reached"))
        }
        return Ok(new Pair<List<Double>, List<List<Double>>>(times, states))
    }

    static Result<Pair<List<Double>, List<List<Double>>>, Error> solveDormandPrince(
            Context context, List<Double>(Double, List<Double>) derivative,
            Double initialTime, List<Double> initialState, Double endTime,
            Double tolerance, Double initialStep, Double maximumStep,
            Int maximumSteps) {
        if context == null || initialState == null {
            throw "OdeSolver.solveDormandPrince: null argument"
        }
        Result<Unit, Error> valid = odeValidateAdaptive(initialTime, endTime,
            tolerance, initialStep, maximumStep, maximumSteps, initialState.length())
        if valid.isErr() { return Err(valid.error()) }
        List<Double> times = []
        List<List<Double>> states = []
        Double time = initialTime
        List<Double> state = initialState.copy()
        Double step = initialStep
        times.push(time)
        states.push(state.copy())
        Int iteration = 0
        while time < endTime && iteration < maximumSteps {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled, "ode cancelled"))
            }
            Double h = step
            if time + h > endTime { h = endTime - time }
            List<List<Double>> k = []
            List<Double> stage = state.copy()
            List<Double> first = derivative(time, stage)
            k.push(first)
            stage = odeAddScaled(state, k.get(0), h * 1.0 / 5.0)
            List<Double> second = derivative(time + h / 5.0, stage)
            k.push(second)
            stage = odeCombined(state, h, k, 3.0 / 40.0, 9.0 / 40.0)
            List<Double> third = derivative(time + 3.0 * h / 10.0, stage)
            k.push(third)
            stage = odeCombined(state, h, k, 44.0 / 45.0, -56.0 / 15.0)
            stage = odeAddScaled(stage, k.get(2), h * 32.0 / 9.0)
            List<Double> fourth = derivative(time + 4.0 * h / 5.0, stage)
            k.push(fourth)
            stage = odeCombined(state, h, k, 19372.0 / 6561.0, -25360.0 / 2187.0)
            stage = odeAddScaled(stage, k.get(2), h * 64448.0 / 6561.0)
            stage = odeAddScaled(stage, k.get(3), h * (-212.0 / 729.0))
            List<Double> fifth = derivative(time + 8.0 * h / 9.0, stage)
            k.push(fifth)
            stage = odeCombined(state, h, k, 9017.0 / 3168.0, -355.0 / 33.0)
            stage = odeAddScaled(stage, k.get(2), h * 46732.0 / 5247.0)
            stage = odeAddScaled(stage, k.get(3), h * 49.0 / 176.0)
            stage = odeAddScaled(stage, k.get(4), h * (-5103.0 / 18656.0))
            List<Double> sixth = derivative(time + h, stage)
            k.push(sixth)
            List<Double> fifthOrder = []
            Int index = 0
            while index < state.length() {
                Double value = state.get(index) + h *
                    (35.0 / 384.0 * k.get(0).get(index) +
                     500.0 / 1113.0 * k.get(2).get(index) +
                     125.0 / 192.0 * k.get(3).get(index) -
                     2187.0 / 6784.0 * k.get(4).get(index) +
                     11.0 / 84.0 * k.get(5).get(index))
                fifthOrder.push(value)
                index = index + 1
            }
            List<Double> seventh = derivative(time + h, fifthOrder)
            k.push(seventh)
            Double errorNorm = 0.0
            index = 0
            while index < state.length() {
                Double fourthOrder = state.get(index) + h *
                    (5179.0 / 57600.0 * k.get(0).get(index) +
                     7571.0 / 16695.0 * k.get(2).get(index) +
                     393.0 / 640.0 * k.get(3).get(index) -
                     92097.0 / 339200.0 * k.get(4).get(index) +
                     187.0 / 2100.0 * k.get(5).get(index) +
                     1.0 / 40.0 * k.get(6).get(index))
                Double difference = abs(fifthOrder.get(index) - fourthOrder)
                Double scale = tolerance * (1.0 + abs(fifthOrder.get(index)))
                Double ratio = difference / scale
                if ratio > errorNorm { errorNorm = ratio }
                index = index + 1
            }
            if !isFinite(errorNorm) {
                return Err(new BasicError(ErrorKind.Internal,
                    "OdeSolver: non-finite error estimate"))
            }
            if errorNorm <= 1.0 {
                time = time + h
                state = fifthOrder
                times.push(time)
                states.push(state.copy())
                Double factor = 0.9 * pow(1.0 / (errorNorm + 0.000000000000001),
                    0.2)
                if factor < 0.2 { factor = 0.2 }
                if factor > 5.0 { factor = 5.0 }
                step = h * factor
                if step > maximumStep { step = maximumStep }
                iteration = iteration + 1
            } else {
                Double factor = 0.9 * pow(1.0 / (errorNorm + 0.000000000000001), 0.2)
                if factor < 0.1 { factor = 0.1 }
                step = h * factor
                if step < 0.000000000001 {
                    return Err(new BasicError(ErrorKind.Internal,
                        "OdeSolver: step underflow"))
                }
            }
        }
        if time < endTime {
            return Err(new BasicError(ErrorKind.Internal,
                "OdeSolver: maximum steps reached"))
        }
        return Ok(new Pair<List<Double>, List<List<Double>>>(times, states))
    }

    static Result<Pair<List<Double>, List<List<Double>>>, Error> solveImplicitEuler(
            Context context, List<Double>(Double, List<Double>) derivative,
            Matrix(Double, List<Double>) jacobian, Double initialTime,
            List<Double> initialState, Double endTime, Double stepSize,
            Double tolerance, Int maximumIterations, Int maximumSteps) {
        if context == null || initialState == null {
            throw "OdeSolver.solveImplicitEuler: null argument"
        }
        Result<Unit, Error> valid = odeValidate(initialTime, endTime, stepSize,
            maximumSteps, initialState.length())
        if valid.isErr() { return Err(valid.error()) }
        if tolerance <= 0.0 || maximumIterations < 1 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "OdeSolver: invalid Newton parameter"))
        }
        List<Double> times = []
        List<List<Double>> states = []
        Double time = initialTime
        List<Double> state = initialState.copy()
        times.push(time)
        states.push(state.copy())
        Int step = 0
        while time < endTime && step < maximumSteps {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled, "ode cancelled"))
            }
            Double h = stepSize
            if time + h > endTime { h = endTime - time }
            List<Double> guess = state.copy()
            Int iteration = 0
            Bool converged = false
            while iteration < maximumIterations {
                List<Double> functionValue = derivative(time + h, guess)
                List<Double> residual = []
                Int index = 0
                while index < state.length() {
                    residual.push(guess.get(index) - state.get(index) -
                        h * functionValue.get(index))
                    index = index + 1
                }
                Matrix jac = jacobian(time + h, guess)
                if jac == null || !jac.isSquare() || jac.rowCount() != state.length() {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "OdeSolver: invalid Jacobian"))
                }
                List<Double> matrixValues = []
                Int row = 0
                while row < jac.rowCount() {
                    Int column = 0
                    while column < jac.columnCount() {
                        Double value = jac.get(row, column)
                        if row == column { value = 1.0 - h * value }
                        else { value = -h * value }
                        matrixValues.push(value)
                        column = column + 1
                    }
                    row = row + 1
                }
                Matrix system = new Matrix(jac.rowCount(), jac.columnCount(),
                    matrixValues)
                Vector right = new Vector(residual)
                Result<Vector, Error> solved = Linalg.solve(system, right)
                if solved.isErr() { return Err(solved.error()) }
                List<Double> delta = solved.value().toList()
                Double maximum = 0.0
                index = 0
                while index < delta.length() {
                    guess.set(index, guess.get(index) - delta.get(index))
                    if abs(delta.get(index)) > maximum {
                        maximum = abs(delta.get(index))
                    }
                    index = index + 1
                }
                if maximum <= tolerance { converged = true; break }
                iteration = iteration + 1
            }
            if !converged {
                return Err(new BasicError(ErrorKind.Internal,
                    "OdeSolver: Newton did not converge"))
            }
            time = time + h
            state = guess
            times.push(time)
            states.push(state.copy())
            step = step + 1
        }
        if time < endTime {
            return Err(new BasicError(ErrorKind.Internal,
                "OdeSolver: maximum steps reached"))
        }
        return Ok(new Pair<List<Double>, List<List<Double>>>(times, states))
    }

    static Result<Pair<List<Double>, List<List<Double>>>, Error> solve(
            Context context, List<Double>(Double, List<Double>) derivative,
            Double initialTime, List<Double> initialState, Double endTime,
            Double tolerance, Int maximumSteps) {
        return OdeSolver.solveDormandPrince(context, derivative, initialTime,
            initialState, endTime, tolerance, 0.01, 0.1, maximumSteps)
    }
}

static Result<Unit, Error> odeValidate(Double initialTime, Double endTime,
                                       Double stepSize, Int maximumSteps, Int dimension) {
    Bool invalid = !isFinite(initialTime)
    if !isFinite(endTime) { invalid = true }
    if !isFinite(stepSize) { invalid = true }
    if endTime <= initialTime { invalid = true }
    if stepSize <= 0.0 { invalid = true }
    if maximumSteps < 1 { invalid = true }
    if dimension < 1 { invalid = true }
    if invalid {
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "OdeSolver: invalid parameter"))
    }
    return Ok()
}

static Result<Unit, Error> odeValidateAdaptive(Double initialTime, Double endTime,
                                               Double tolerance, Double initialStep,
                                               Double maximumStep, Int maximumSteps,
                                               Int dimension) {
    Bool invalid = !isFinite(initialTime)
    if !isFinite(endTime) { invalid = true }
    if !isFinite(tolerance) { invalid = true }
    if !isFinite(initialStep) { invalid = true }
    if !isFinite(maximumStep) { invalid = true }
    if endTime <= initialTime { invalid = true }
    if tolerance <= 0.0 { invalid = true }
    if initialStep <= 0.0 { invalid = true }
    if maximumStep <= 0.0 { invalid = true }
    if maximumSteps < 1 { invalid = true }
    if dimension < 1 { invalid = true }
    if invalid {
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "OdeSolver: invalid parameter"))
    }
    return Ok()
}

static List<Double> odeAddScaled(List<Double> base, List<Double> delta,
                                 Double factor) {
    List<Double> result = []
    Int index = 0
    while index < base.length() {
        result.push(base.get(index) + factor * delta.get(index))
        index = index + 1
    }
    return result
}

static List<Double> odeCombined(List<Double> base, Double h, List<List<Double>> k,
                                Double c0, Double c1) {
    List<Double> result = []
    Int index = 0
    while index < base.length() {
        result.push(base.get(index) + h * (c0 * k.get(0).get(index) +
            c1 * k.get(1).get(index)))
        index = index + 1
    }
    return result
}

// ---------- Fft ----------
class Fft {
    private Fft() { }

    static Result<List<Complex>, Error> forward(Context context, List<Complex> values) {
        return Fft.transform(context, values, false)
    }

    static Result<List<Complex>, Error> inverse(Context context, List<Complex> values) {
        return Fft.transform(context, values, true)
    }

    static Result<List<Complex>, Error> forwardReal(Context context, List<Double> values) {
        if context == null || values == null {
            throw "Fft.forwardReal: null argument"
        }
        if values.length() == 0 || values.length() > 16777216 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "Fft: invalid length"))
        }
        List<Complex> complexValues = []
        Int index = 0
        while index < values.length() {
            if !isFinite(values.get(index)) {
                return Err(new BasicError(ErrorKind.InvalidArgument, "Fft: non-finite input"))
            }
            complexValues.push(Complex.of(values.get(index), 0.0))
            index = index + 1
        }
        Result<List<Complex>, Error> transformed = Fft.transform(context, complexValues, false)
        if transformed.isErr() { return Err(transformed.error()) }
        List<Complex> full = transformed.value()
        List<Complex> half = []
        Int halfLength = values.length() / 2 + 1
        index = 0
        while index < halfLength {
            half.push(full.get(index))
            index = index + 1
        }
        return Ok(half)
    }

    static Result<List<Double>, Error> inverseReal(Context context, List<Complex> spectrum,
                                                   Int outputLength, Double tolerance) {
        if context == null || spectrum == null {
            throw "Fft.inverseReal: null argument"
        }
        Int expectedSpectrumLength = outputLength / 2 + 1
        if outputLength < 1 || !isFinite(tolerance) || tolerance < 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "Fft: invalid inverseReal parameter"))
        }
        if spectrum.length() != expectedSpectrumLength {
            return Err(new BasicError(ErrorKind.InvalidArgument, "Fft: invalid inverseReal parameter"))
        }
        List<Complex> full = []
        Int index = 0
        while index < outputLength {
            full.push(Complex.zero())
            index = index + 1
        }
        index = 0
        while index < spectrum.length() {
            Complex value = spectrum.get(index)
            if value == null || !isFinite(value.real()) || !isFinite(value.imag()) {
                return Err(new BasicError(ErrorKind.InvalidArgument, "Fft: non-finite spectrum"))
            }
            full.set(index, value)
            if index > 0 {
                Int mirror = outputLength - index
                if mirror != index { full.set(mirror, value.conjugate()) }
            }
            index = index + 1
        }
        Result<List<Complex>, Error> transformed = Fft.transform(context, full, true)
        if transformed.isErr() { return Err(transformed.error()) }
        List<Complex> values = transformed.value()
        List<Double> result = []
        index = 0
        while index < values.length() {
            Complex value = values.get(index)
            if !isFinite(value.real()) || abs(value.imag()) > tolerance {
                return Err(new BasicError(ErrorKind.DataCorrupted,
                    "Fft: spectrum is not conjugate symmetric"))
            }
            result.push(value.real())
            index = index + 1
        }
        return Ok(result)
    }

    private static Result<List<Complex>, Error> transform(Context context,
                                                          List<Complex> values,
                                                          Bool inverse) {
        if context == null || values == null {
            throw "Fft.transform: null argument"
        }
        if values.length() == 0 || values.length() > 16777216 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "Fft: invalid length"))
        }
        Int index = 0
        while index < values.length() {
            Complex value = values.get(index)
            if value == null || !isFinite(value.real()) || !isFinite(value.imag()) {
                return Err(new BasicError(ErrorKind.InvalidArgument, "Fft: non-finite input"))
            }
            index = index + 1
        }
        List<Complex> data = values.copy()
        if Fft.isPowerOfTwo(data.length()) {
            Result<Unit, Error> run = Fft.radix2(context, data, inverse)
            if run.isErr() { return Err(run.error()) }
        } else {
            Result<List<Complex>, Error> direct = Fft.direct(context, data, inverse)
            if direct.isErr() { return Err(direct.error()) }
            data = direct.value()
        }
        if inverse {
            Double scale = 1.0 / (data.length() as Double)
            index = 0
            while index < data.length() {
                data.set(index, data.get(index).scale(scale))
                index = index + 1
            }
        }
        return Ok(data)
    }

    private static Bool isPowerOfTwo(Int value) {
        return value > 0 && (value & (value - 1)) == 0
    }

    private static Result<Unit, Error> radix2(Context context, List<Complex> data, Bool inverse) {
        Int n = data.length()
        Int j = 0
        Int i = 1
        while i < n {
            Int bit = n / 2
            while j >= bit && bit > 0 {
                j = j - bit
                bit = bit / 2
            }
            j = j + bit
            if i < j {
                Complex temporary = data.get(i)
                data.set(i, data.get(j))
                data.set(j, temporary)
            }
            i = i + 1
        }
        Int length = 2
        while length <= n {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled, "Fft cancelled"))
            }
            Double angle = 6.283185307179586 / (length as Double)
            if !inverse { angle = 0.0 - angle }
            Complex step = Complex.fromPolar(1.0, angle)
            Int start = 0
            while start < n {
                Complex factor = Complex.one()
                Int offset = 0
                while offset < length / 2 {
                    Complex even = data.get(start + offset)
                    Complex odd = data.get(start + offset + length / 2).mul(factor)
                    data.set(start + offset, even.add(odd))
                    data.set(start + offset + length / 2, even.sub(odd))
                    factor = factor.mul(step)
                    offset = offset + 1
                }
                start = start + length
            }
            length = length * 2
        }
        return Ok()
    }

    private static Result<List<Complex>, Error> direct(Context context, List<Complex> values,
                                                        Bool inverse) {
        Int n = values.length()
        List<Complex> result = []
        Int k = 0
        while k < n {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled, "Fft cancelled"))
            }
            Complex sum = Complex.zero()
            Int index = 0
            while index < n {
                Double angle = 6.283185307179586 * (k as Double) * (index as Double) / (n as Double)
                if !inverse { angle = 0.0 - angle }
                sum = sum.add(values.get(index).mul(Complex.fromPolar(1.0, angle)))
                index = index + 1
            }
            result.push(sum)
            k = k + 1
        }
        return Ok(result)
    }
}

// ---------- SignalBuffer ----------
class SignalBuffer {
    private SignalBuffer() { }

    static Result<List<Double>, Error> rectangularWindow(Int length) {
        if length < 1 { return Err(new BasicError(ErrorKind.InvalidArgument, "window: invalid length")) }
        List<Double> values = []
        Int index = 0
        while index < length {
            values.push(1.0)
            index = index + 1
        }
        return Ok(values)
    }

    static Result<List<Double>, Error> hannWindow(Int length, Bool periodic) {
        return SignalBuffer.cosineWindow(length, periodic, 0.5, 0.5, 0.0, 0.0)
    }

    static Result<List<Double>, Error> hammingWindow(Int length, Bool periodic) {
        return SignalBuffer.cosineWindow(length, periodic, 0.54, 0.46, 0.0, 0.0)
    }

    static Result<List<Double>, Error> blackmanWindow(Int length, Bool periodic) {
        return SignalBuffer.cosineWindow(length, periodic, 0.42, 0.5, 0.08, 0.0)
    }

    static Result<List<Double>, Error> kaiserWindow(Int length, Double beta, Bool periodic) {
        if length < 1 || !isFinite(beta) || beta < 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "kaiser: invalid parameter"))
        }
        List<Double> values = []
        if length == 1 {
            values.push(1.0)
            return Ok(values)
        }
        Double denominator = (length - 1) as Double
        if periodic { denominator = length as Double }
        Double normalization = SignalBuffer.besselI0(beta)
        Int index = 0
        while index < length {
            Double ratio = 2.0 * (index as Double) / denominator - 1.0
            Double argument = beta * sqrt(1.0 - ratio * ratio)
            values.push(SignalBuffer.besselI0(argument) / normalization)
            index = index + 1
        }
        return Ok(values)
    }

    static Result<List<Double>, Error> convolve(Context context, List<Double> signal,
                                                 List<Double> kernel) {
        if context == null || signal == null || kernel == null {
            throw "SignalBuffer.convolve: null argument"
        }
        if signal.length() == 0 || kernel.length() == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "convolve: empty input"))
        }
        Result<Unit, Error> finite = SignalBuffer.validateFinite(signal)
        if finite.isErr() { return Err(finite.error()) }
        finite = SignalBuffer.validateFinite(kernel)
        if finite.isErr() { return Err(finite.error()) }
        List<Double> result = []
        Int size = signal.length() + kernel.length() - 1
        Int index = 0
        while index < size {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled, "convolve cancelled"))
            }
            Double sum = 0.0
            Int k = 0
            while k < kernel.length() {
                Int position = index - k
                if position >= 0 && position < signal.length() {
                    sum = sum + signal.get(position) * kernel.get(k)
                }
                k = k + 1
            }
            result.push(sum)
            index = index + 1
        }
        return Ok(result)
    }

    static Result<List<Double>, Error> firFilter(Context context, List<Double> signal,
                                                  List<Double> coefficients) {
        if context == null || signal == null || coefficients == null {
            throw "SignalBuffer.firFilter: null argument"
        }
        if signal.length() == 0 || coefficients.length() == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "fir: empty input"))
        }
        Result<Unit, Error> finite = SignalBuffer.validateFinite(signal)
        if finite.isErr() { return Err(finite.error()) }
        finite = SignalBuffer.validateFinite(coefficients)
        if finite.isErr() { return Err(finite.error()) }
        List<Double> result = []
        Int index = 0
        while index < signal.length() {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled, "fir cancelled"))
            }
            Double sum = 0.0
            Int k = 0
            while k < coefficients.length() {
                Int position = index - k
                if position >= 0 { sum = sum + signal.get(position) * coefficients.get(k) }
                k = k + 1
            }
            result.push(sum)
            index = index + 1
        }
        return Ok(result)
    }

    static Result<List<Double>, Error> iirFilter(Context context, List<Double> signal,
                                                  List<Double> numerator,
                                                  List<Double> denominator) {
        if context == null || signal == null || numerator == null || denominator == null {
            throw "SignalBuffer.iirFilter: null argument"
        }
        if signal.length() == 0 || numerator.length() == 0 || denominator.length() == 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "iir: empty input"))
        }
        if denominator.get(0) == 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "iir: zero leading denominator"))
        }
        Result<Unit, Error> finite = SignalBuffer.validateFinite(signal)
        if finite.isErr() { return Err(finite.error()) }
        finite = SignalBuffer.validateFinite(numerator)
        if finite.isErr() { return Err(finite.error()) }
        finite = SignalBuffer.validateFinite(denominator)
        if finite.isErr() { return Err(finite.error()) }
        List<Double> output = []
        Int index = 0
        while index < signal.length() {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled, "iir cancelled"))
            }
            Double sum = 0.0
            Int k = 0
            while k < numerator.length() {
                Int position = index - k
                if position >= 0 { sum = sum + numerator.get(k) * signal.get(position) }
                k = k + 1
            }
            k = 1
            while k < denominator.length() {
                Int position = index - k
                if position >= 0 { sum = sum - denominator.get(k) * output.get(position) }
                k = k + 1
            }
            output.push(sum / denominator.get(0))
            index = index + 1
        }
        return Ok(output)
    }

    private static Result<Unit, Error> validateFinite(List<Double> values) {
        Int index = 0
        while index < values.length() {
            if !isFinite(values.get(index)) {
                return Err(new BasicError(ErrorKind.InvalidArgument, "signal: non-finite input"))
            }
            index = index + 1
        }
        return Ok()
    }

    private static Result<List<Double>, Error> cosineWindow(Int length, Bool periodic,
                                                             Double a0, Double a1,
                                                             Double a2, Double unused) {
        if length < 1 { return Err(new BasicError(ErrorKind.InvalidArgument, "window: invalid length")) }
        List<Double> values = []
        if length == 1 {
            values.push(1.0)
            return Ok(values)
        }
        Double denominator = (length - 1) as Double
        if periodic { denominator = length as Double }
        Int index = 0
        while index < length {
            Double phase = 6.283185307179586 * (index as Double) / denominator
            Double value = a0 - a1 * cos(phase) + a2 * cos(2.0 * phase)
            values.push(value)
            index = index + 1
        }
        return Ok(values)
    }

    private static Double besselI0(Double x) {
        Double sum = 1.0
        Double term = 1.0
        Double half = x / 2.0
        Int k = 1
        while k < 200 {
            term = term * half * half / ((k as Double) * (k as Double))
            sum = sum + term
            if abs(term) < 0.0000000000000001 * abs(sum) { break }
            k = k + 1
        }
        return sum
    }
}

// ---------- SpecialFunctions ----------
class SpecialFunctions {
    private SpecialFunctions() { }

    static Result<Double, Error> gamma(Double value) {
        if !isFinite(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "gamma: non-finite"))
        }
        if value <= 0.0 && value == floor(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "gamma: pole"))
        }
        return Ok(SpecialFunctions.gammaValue(value))
    }

    static Result<Double, Error> logGamma(Double value) {
        if !isFinite(value) || value <= 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "logGamma: invalid domain"))
        }
        Double result = SpecialFunctions.logGammaValue(value)
        if !isFinite(result) {
            return Err(new BasicError(ErrorKind.Internal, "logGamma: not finite"))
        }
        return Ok(result)
    }

    static Result<Double, Error> digamma(Double value) {
        if !isFinite(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "digamma: non-finite"))
        }
        if value <= 0.0 && value == floor(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "digamma: pole"))
        }
        return Ok(SpecialFunctions.digammaValue(value))
    }

    static Result<Double, Error> beta(Double left, Double right) {
        if !isFinite(left) || !isFinite(right) || left <= 0.0 || right <= 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "beta: invalid domain"))
        }
        Double result = exp(SpecialFunctions.logGammaValue(left) +
            SpecialFunctions.logGammaValue(right) -
            SpecialFunctions.logGammaValue(left + right))
        if !isFinite(result) {
            return Err(new BasicError(ErrorKind.Internal, "beta: not finite"))
        }
        return Ok(result)
    }

    static Result<Double, Error> regularizedGammaP(Double shape, Double value) {
        if !isFinite(shape) || !isFinite(value) || shape <= 0.0 || value < 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "gammaP: invalid parameter"))
        }
        return Ok(SpecialFunctions.gammaPValue(shape, value))
    }

    static Result<Double, Error> regularizedGammaQ(Double shape, Double value) {
        if !isFinite(shape) || !isFinite(value) || shape <= 0.0 || value < 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "gammaQ: invalid parameter"))
        }
        return Ok(1.0 - SpecialFunctions.gammaPValue(shape, value))
    }

    static Result<Double, Error> regularizedBeta(Double shapeA, Double shapeB,
                                                  Double value) {
        if !isFinite(shapeA) || !isFinite(shapeB) || !isFinite(value) ||
            shapeA <= 0.0 || shapeB <= 0.0 || value < 0.0 || value > 1.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "beta: invalid parameter"))
        }
        return Ok(SpecialFunctions.betaValue(shapeA, shapeB, value))
    }

    static Double erf(Double value) {
        if !isFinite(value) { return NaN() }
        if value == 0.0 { return 0.0 }
        Double square = value * value
        Double probability = SpecialFunctions.gammaPValue(0.5, square)
        if value < 0.0 { return 0.0 - probability }
        return probability
    }

    static Double erfc(Double value) {
        if !isFinite(value) { return NaN() }
        return 1.0 - SpecialFunctions.erf(value)
    }

    static Result<Double, Error> inverseErf(Double probability) {
        if !isFinite(probability) || probability <= 0.0 - 1.0 || probability >= 1.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "inverseErf: invalid probability"))
        }
        if probability == 0.0 { return Ok(0.0) }
        Double start = 0.5 * sqrt(3.141592653589793) *
            (probability + 3.141592653589793 * probability * probability * probability / 12.0)
        Double current = start
        Int iteration = 0
        while iteration < 30 {
            Double error = SpecialFunctions.erf(current) - probability
            Double derivative = 2.0 / sqrt(3.141592653589793) * exp(0.0 - current * current)
            if derivative == 0.0 { break }
            Double next = current - error / derivative
            if abs(next - current) < 0.000000000000001 { current = next; break }
            current = next
            iteration = iteration + 1
        }
        return Ok(current)
    }

    static Result<Double, Error> besselJ(Int order, Double value) {
        if !isFinite(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "besselJ: non-finite"))
        }
        return Ok(SpecialFunctions.besselJValue(order, value))
    }

    static Result<Double, Error> besselY(Int order, Double value) {
        if !isFinite(value) || value <= 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "besselY: invalid domain"))
        }
        return Ok(SpecialFunctions.besselYValue(order, value))
    }

    static Result<Double, Error> besselI(Int order, Double value) {
        if !isFinite(value) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "besselI: non-finite"))
        }
        return Ok(SpecialFunctions.besselIValue(order, value))
    }

    static Result<Double, Error> besselK(Int order, Double value) {
        if !isFinite(value) || value <= 0.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "besselK: invalid domain"))
        }
        return Ok(SpecialFunctions.besselKValue(order, value))
    }

    static Double airyAi(Double value) {
        if !isFinite(value) { return NaN() }
        return SpecialFunctions.airyAiValue(value)
    }

    static Double airyBi(Double value) {
        if !isFinite(value) { return NaN() }
        return SpecialFunctions.airyBiValue(value)
    }

    static Result<Double, Error> riemannZeta(Double value) {
        if !isFinite(value) || value <= 1.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "zeta: invalid domain"))
        }
        return Ok(SpecialFunctions.zetaValue(value))
    }

    static Result<Double, Error> lambertW(Double value) {
        if !isFinite(value) || value < 0.0 - 1.0 / E() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "lambertW: invalid domain"))
        }
        return Ok(SpecialFunctions.lambertWValue(value))
    }

    static Result<Double, Error> ellipticK(Double parameter) {
        if !isFinite(parameter) || parameter < 0.0 || parameter >= 1.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "ellipticK: invalid parameter"))
        }
        return Ok(SpecialFunctions.ellipticKValue(parameter))
    }

    static Result<Double, Error> ellipticE(Double parameter) {
        if !isFinite(parameter) || parameter < 0.0 || parameter >= 1.0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "ellipticE: invalid parameter"))
        }
        return Ok(SpecialFunctions.ellipticEValue(parameter))
    }

    // ----- internals -----
    private static Double lanczosA(Double z) {
        Double sum = 0.99999999999980993
        sum = sum + 676.5203681218851 / (z + 1.0)
        sum = sum + (0.0 - 1259.1392167224028) / (z + 2.0)
        sum = sum + 771.32342877765313 / (z + 3.0)
        sum = sum + (0.0 - 176.61502916214059) / (z + 4.0)
        sum = sum + 12.507343278686905 / (z + 5.0)
        sum = sum + (0.0 - 0.13857109526572012) / (z + 6.0)
        sum = sum + 0.0000099843695780195716 / (z + 7.0)
        sum = sum + 0.00000015056327351493116 / (z + 8.0)
        return sum
    }

    private static Double gammaValue(Double value) {
        if value < 0.5 {
            return 3.141592653589793 /
                (sin(3.141592653589793 * value) * SpecialFunctions.gammaValue(1.0 - value))
        }
        Double z = value - 1.0
        Double t = z + 7.5
        return sqrt(6.283185307179586) * pow(t, z + 0.5) * exp(0.0 - t) *
            SpecialFunctions.lanczosA(z)
    }

    private static Double logGammaValue(Double value) {
        Double z = value - 1.0
        Double t = z + 7.5
        return 0.9189385332046727 + (z + 0.5) * log(t) - t +
            log(SpecialFunctions.lanczosA(z))
    }

    private static Double digammaValue(Double value) {
        Double x = value
        Double result = 0.0
        while x < 8.0 {
            result = result - 1.0 / x
            x = x + 1.0
        }
        Double inverse = 1.0 / x
        Double square = inverse * inverse
        result = result + log(x) - 0.5 * inverse -
            square * (1.0 / 12.0 - square * (1.0 / 120.0 -
            square * (1.0 / 252.0 - square / 240.0)))
        return result
    }

    private static Double gammaPValue(Double shape, Double value) {
        if value == 0.0 { return 0.0 }
        Double logFactor = shape * log(value) - value - SpecialFunctions.logGammaValue(shape)
        if value < shape + 1.0 {
            Double term = 1.0 / shape
            Double sum = term
            Double current = shape
            Int iteration = 1
            while iteration < 500 {
                current = current + 1.0
                term = term * value / current
                sum = sum + term
                if abs(term) < abs(sum) * 0.000000000000001 { break }
                iteration = iteration + 1
            }
            return sum * exp(logFactor)
        }
        Double b = value + 1.0 - shape
        Double c = 1.0 / 0.000000000000001
        Double d = 1.0 / b
        Double h = d
        Int iteration = 1
        while iteration < 500 {
            Double an = (iteration as Double) * (shape - iteration as Double)
            b = b + 2.0
            d = an * d + b
            if abs(d) < 0.000000000000001 { d = 0.000000000000001 }
            c = b + an / c
            if abs(c) < 0.000000000000001 { c = 0.000000000000001 }
            d = 1.0 / d
            Double delta = d * c
            h = h * delta
            if abs(delta - 1.0) < 0.000000000000001 { break }
            iteration = iteration + 1
        }
        Double q = exp(logFactor) * h
        return 1.0 - q
    }

    private static Double betaValue(Double a, Double b, Double x) {
        if x == 0.0 { return 0.0 }
        if x == 1.0 { return 1.0 }
        Double logBeta = SpecialFunctions.logGammaValue(a + b) -
            SpecialFunctions.logGammaValue(a) - SpecialFunctions.logGammaValue(b)
        Double front = exp(logBeta + a * log(x) + b * log(1.0 - x))
        if x < (a + 1.0) / (a + b + 2.0) {
            return front * SpecialFunctions.betaFraction(a, b, x) / a
        }
        return 1.0 - front * SpecialFunctions.betaFraction(b, a, 1.0 - x) / b
    }

    private static Double betaFraction(Double a, Double b, Double x) {
        Double qab = a + b
        Double qap = a + 1.0
        Double qam = a - 1.0
        Double c = 1.0
        Double d = 1.0 - qab * x / qap
        if abs(d) < 0.000000000000001 { d = 0.000000000000001 }
        d = 1.0 / d
        Double h = d
        Int m = 1
        while m <= 300 {
            Int m2 = 2 * m
            Double aa = (m as Double) * (b - m as Double) * x /
                ((qam + m2 as Double) * (a + m2 as Double))
            d = 1.0 + aa * d
            if abs(d) < 0.000000000000001 { d = 0.000000000000001 }
            c = 1.0 + aa / c
            if abs(c) < 0.000000000000001 { c = 0.000000000000001 }
            d = 1.0 / d
            h = h * d * c
            aa = (0.0 - (a + m as Double)) * (qab + m as Double) * x /
                ((a + m2 as Double) * (qap + m2 as Double))
            d = 1.0 + aa * d
            if abs(d) < 0.000000000000001 { d = 0.000000000000001 }
            c = 1.0 + aa / c
            if abs(c) < 0.000000000000001 { c = 0.000000000000001 }
            d = 1.0 / d
            Double delta = d * c
            h = h * delta
            if abs(delta - 1.0) < 0.000000000000001 { break }
            m = m + 1
        }
        return h
    }

    private static Double besselJValue(Int order, Double x) {
        Int n = order
        Bool negate = false
        if n < 0 {
            n = 0 - n
            if n % 2 == 1 { negate = true }
        }
        Double absolute = abs(x)
        Double result = 0.0
        if absolute > 30.0 {
            Double phase = absolute - (n as Double) * 3.141592653589793 / 2.0 -
                3.141592653589793 / 4.0
            result = sqrt(2.0 / (3.141592653589793 * absolute)) * cos(phase)
        } else {
            Double half = x / 2.0
            Double term = pow(half, n as Double) / SpecialFunctions.factorial(n)
            Double sum = term
            Int k = 1
            while k < 200 {
                term = term * (0.0 - half * half) / ((k as Double) * ((k + n) as Double))
                sum = sum + term
                if abs(term) < abs(sum) * 0.000000000000001 { break }
                k = k + 1
            }
            result = sum
        }
        if negate && x < 0.0 { }
        if n % 2 == 1 && x < 0.0 { result = 0.0 - result }
        return result
    }

    private static Double besselYValue(Int order, Double x) {
        if order < 0 {
            Int n = 0 - order
            Double left = SpecialFunctions.besselYValue(n, x)
            if n % 2 == 1 { return 0.0 - left }
            return left
        }
        Double y0 = SpecialFunctions.besselY0(x)
        if order == 0 { return y0 }
        Double y1 = SpecialFunctions.besselY1(x)
        if order == 1 { return y1 }
        Double previous = y0
        Double current = y1
        Int index = 1
        while index < order {
            Double next = 2.0 * (index as Double) / x * current - previous
            previous = current
            current = next
            index = index + 1
        }
        return current
    }

    private static Double besselY0(Double x) {
        Double j0 = SpecialFunctions.besselJValue(0, x)
        Double sum = 0.0
        Double term = 1.0
        Double harmonic = 0.0
        Double half = x / 2.0
        Int k = 1
        while k < 200 {
            harmonic = harmonic + 1.0 / (k as Double)
            term = term * (0.0 - half * half) / ((k as Double) * (k as Double))
            Double contribution = 0.0 - term * harmonic
            sum = sum + contribution
            if abs(contribution) < 0.000000000000001 { break }
            k = k + 1
        }
        return 0.6366197723675814 * (log(half) + 0.5772156649015329) * j0 +
            0.6366197723675814 * sum
    }

    private static Double besselY1(Double x) {
        Double j1 = SpecialFunctions.besselJValue(1, x)
        Double sum = 0.0
        Double term = x / 2.0
        Double harmonic = 0.0
        Double half = x / 2.0
        Int k = 0
        while k < 200 {
            Double hk = harmonic
            Double hk1 = harmonic + 1.0 / ((k + 1) as Double)
            Double coefficient = term * (hk + hk1)
            sum = sum + coefficient
            if abs(coefficient) < 0.000000000000001 { break }
            harmonic = hk1
            term = term * (0.0 - half * half) / (((k + 1) as Double) * ((k + 2) as Double))
            k = k + 1
        }
        return 0.6366197723675814 * (log(half) + 0.5772156649015329) * j1 -
            0.6366197723675814 / x - 0.3183098861837907 * sum
    }

    private static Double besselIValue(Int order, Double x) {
        Int n = order
        Bool negate = false
        if n < 0 {
            n = 0 - n
            if n % 2 == 1 { negate = true }
        }
        Double half = x / 2.0
        Double term = pow(abs(half), n as Double) / SpecialFunctions.factorial(n)
        Double sum = term
        Int k = 1
        while k < 200 {
            term = term * (half * half) / ((k as Double) * ((k + n) as Double))
            sum = sum + term
            if abs(term) < abs(sum) * 0.000000000000001 { break }
            k = k + 1
        }
        if n % 2 == 1 && x < 0.0 { sum = 0.0 - sum }
        if negate { }
        return sum
    }

    private static Double besselKValue(Int order, Double x) {
        if order < 0 { order = 0 - order }
        Double k0 = SpecialFunctions.besselK0(x)
        if order == 0 { return k0 }
        Double i0 = SpecialFunctions.besselIValue(0, x)
        Double i1 = SpecialFunctions.besselIValue(1, x)
        Double k1 = (1.0 / x - i1 * k0) / i0
        if order == 1 { return k1 }
        Double previous = k0
        Double current = k1
        Int index = 1
        while index < order {
            Double next = previous + 2.0 * (index as Double) / x * current
            previous = current
            current = next
            index = index + 1
        }
        return current
    }

    private static Double besselK0(Double x) {
        if x > 20.0 {
            return sqrt(3.141592653589793 / (2.0 * x)) * exp(0.0 - x)
        }
        Double i0 = SpecialFunctions.besselIValue(0, x)
        Double sum = 0.0
        Double term = 1.0
        Double harmonic = 0.0
        Double half = x / 2.0
        Int k = 1
        while k < 200 {
            harmonic = harmonic + 1.0 / (k as Double)
            term = term * (half * half) / ((k as Double) * (k as Double))
            Double contribution = term * harmonic
            sum = sum + contribution
            if abs(contribution) < 0.000000000000001 { break }
            k = k + 1
        }
        return 0.0 - (log(half) + 0.5772156649015329) * i0 + sum
    }

    private static Double airyAiValue(Double x) {
        List<Double> series = SpecialFunctions.airySeries(x)
        return 0.3550280538878172 * series.get(0) - 0.2588194037928068 * series.get(1)
    }

    private static Double airyBiValue(Double x) {
        List<Double> series = SpecialFunctions.airySeries(x)
        return 0.6149266274460007 * series.get(0) + 0.4482883573538264 * series.get(1)
    }

    private static List<Double> airySeries(Double x) {
        Double f = 1.0
        Double term = 1.0
        Int k = 0
        Double x3 = x * x * x
        while k < 100 {
            term = term * x3 / (((3 * k + 2) as Double) * ((3 * k + 3) as Double))
            f = f + term
            if abs(term) < 0.000000000000001 { break }
            k = k + 1
        }
        Double g = x
        term = x
        k = 0
        while k < 100 {
            term = term * x3 / (((3 * k + 3) as Double) * ((3 * k + 4) as Double))
            g = g + term
            if abs(term) < 0.000000000000001 { break }
            k = k + 1
        }
        List<Double> result = []
        result.push(f)
        result.push(g)
        return result
    }

    private static Double zetaValue(Double s) {
        Int n = 20
        Double sum = 0.0
        Int index = 1
        while index < n {
            sum = sum + pow(index as Double, 0.0 - s)
            index = index + 1
        }
        Double nValue = n as Double
        sum = sum + pow(nValue, 1.0 - s) / (s - 1.0) + 0.5 * pow(nValue, 0.0 - s)
        Double coefficient = s
        Double power = pow(nValue, 0.0 - s - 1.0)
        sum = sum + (1.0 / 6.0) / 2.0 * coefficient * power
        coefficient = coefficient * (s + 1.0) * (s + 2.0)
        power = power / (nValue * nValue)
        sum = sum + (0.0 - 1.0 / 30.0) / 24.0 * coefficient * power
        coefficient = coefficient * (s + 3.0) * (s + 4.0)
        power = power / (nValue * nValue)
        sum = sum + (1.0 / 42.0) / 720.0 * coefficient * power
        coefficient = coefficient * (s + 5.0) * (s + 6.0)
        power = power / (nValue * nValue)
        sum = sum + (0.0 - 1.0 / 30.0) / 40320.0 * coefficient * power
        return sum
    }

    private static Double lambertWValue(Double x) {
        if x == 0.0 { return 0.0 }
        Double w = 0.0
        if x > 0.0 {
            w = log(1.0 + x)
            if x > 3.0 { w = log(x) }
        } else {
            w = 0.0 - 1.0 + sqrt(2.0 * (E() * x + 1.0))
            if 2.0 * (E() * x + 1.0) < 0.0 { w = 0.0 - 1.0 }
        }
        Int iteration = 0
        while iteration < 100 {
            Double exponential = exp(w)
            Double difference = w * exponential - x
            Double denominator = exponential * (w + 1.0) -
                (w + 2.0) * difference / (2.0 * w + 2.0)
            if denominator == 0.0 { break }
            Double next = w - difference / denominator
            if abs(next - w) < 0.000000000000001 { w = next; break }
            w = next
            iteration = iteration + 1
        }
        return w
    }

    private static Double ellipticKValue(Double parameter) {
        Double a = 1.0
        Double b = sqrt(1.0 - parameter)
        Int iteration = 0
        while iteration < 60 {
            Double next = 0.5 * (a + b)
            b = sqrt(a * b)
            a = next
            if abs(a - b) < 0.000000000000001 { break }
            iteration = iteration + 1
        }
        return 3.141592653589793 / (2.0 * a)
    }

    private static Double ellipticEValue(Double parameter) {
        Double a = 1.0
        Double b = sqrt(1.0 - parameter)
        Double c = sqrt(parameter)
        Double sum = 0.5 * c * c
        Double power = 1.0
        Int iteration = 0
        while iteration < 60 {
            Double next = 0.5 * (a + b)
            c = 0.5 * (a - b)
            b = sqrt(a * b)
            a = next
            power = power * 2.0
            sum = sum + power * c * c
            if abs(c) < 0.000000000000001 { break }
            iteration = iteration + 1
        }
        Double k = 3.141592653589793 / (2.0 * a)
        return k * (1.0 - sum)
    }

    private static Double factorial(Int value) {
        Double result = 1.0
        Int index = 2
        while index <= value {
            result = result * (index as Double)
            index = index + 1
        }
        return result
    }
}
