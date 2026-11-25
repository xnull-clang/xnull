// xdk.numerics —— 多项式/求根/插值核心（M22.1）
//
// 实现实系数 Polynomial、RootFinder、Interpolation、Numerics 门面。
// BigInt/BigFloat/FFT/ODE/特殊函数/积分/优化留后续。
package xdk.numerics
import xdk.errors
import xdk.math
import xdk.collections

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
