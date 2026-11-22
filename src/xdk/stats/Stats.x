// xdk.stats — stateful statistics objects.
// Tier: L4；依赖：xdk.math、xdk.collections；稳定性：preview。
package xdk.stats
import xdk.math
import xdk.collections

class HistogramBucket {
    final Double? _lower
    final Double? _upper
    final Long _count

    HistogramBucket(Double? lower, Double? upper, Long count) {
        if count < 0 { throw "HistogramBucket: negative count" }
        if lower != null && isNaN(lower) { throw "HistogramBucket: NaN lower" }
        if upper != null && isNaN(upper) { throw "HistogramBucket: NaN upper" }
        if lower != null && upper != null && lower >= upper {
            throw "HistogramBucket: lower must be less than upper"
        }
        self._lower = lower
        self._upper = upper
        self._count = count
    }

    Double? lower() { return self._lower }
    Double? upper() { return self._upper }
    Long count() { return self._count }

    Bool contains(Double value) {
        if isNaN(value) { return false }
        if self._lower == null && self._upper == null { return true }
        if self._lower == null { return value <= self._upper as Double }
        if self._upper == null { return value > self._lower as Double }
        return value > self._lower as Double && value <= self._upper as Double
    }

    String toString() {
        String left = "-inf"
        String right = "+inf"
        if self._lower != null { left = str(self._lower as Double) }
        if self._upper != null { right = str(self._upper as Double) }
        return "(" + left + ", " + right + "]=" + str(self._count)
    }
}

class BucketHistogram {
    final List<Double> _boundaries
    final List<Long> _counts
    Long _count
    Double _sum
    Double _sumSquares
    Double _min
    Double _max
    Bool _hasValues

    BucketHistogram(List<Double> boundaries) {
        if boundaries == null { throw "BucketHistogram: null boundaries" }
        List<Double> copy = []
        Int index = 0
        while index < boundaries.length() {
            Double value = boundaries.get(index)
            if isNaN(value) { throw "BucketHistogram: NaN boundary" }
            if index > 0 && value <= copy.get(index - 1) {
                throw "BucketHistogram: boundaries must be strictly increasing"
            }
            copy.push(value)
            index = index + 1
        }
        self._boundaries = copy
        self._counts = []
        index = 0
        while index <= copy.length() {
            self._counts.push(0)
            index = index + 1
        }
        self._count = 0
        self._sum = 0.0
        self._sumSquares = 0.0
        self._min = 0.0
        self._max = 0.0
        self._hasValues = false
    }

    Int bucketIndex(Double value) {
        Int index = 0
        while index < self._boundaries.length() {
            if value <= self._boundaries.get(index) { return index }
            index = index + 1
        }
        return self._boundaries.length()
    }

    Void observe(Double value) {
        if isNaN(value) { throw "BucketHistogram.observe: NaN value" }
        Int index = self.bucketIndex(value)
        self._counts.set(index, self._counts.get(index) + 1)
        self._count = self._count + 1
        self._sum = self._sum + value
        self._sumSquares = self._sumSquares + value * value
        if !self._hasValues {
            self._min = value
            self._max = value
            self._hasValues = true
        } else {
            if value < self._min { self._min = value }
            if value > self._max { self._max = value }
        }
    }

    Long count() { return self._count }
    Double sum() { return self._sum }
    Double min() { if !self._hasValues { return NaN() } return self._min }
    Double max() { if !self._hasValues { return NaN() } return self._max }
    Double mean() { if !self._hasValues { return NaN() } return self._sum / (self._count as Double) }
    Double stddev() {
        if !self._hasValues { return NaN() }
        Double variance = self._sumSquares / (self._count as Double) - self.mean() * self.mean()
        if variance < 0.0 { variance = 0.0 }
        return sqrt(variance)
    }

    Double percentile(Double percentileValue) {
        if !self._hasValues { return NaN() }
        Double p = percentileValue
        if p < 0.0 { p = 0.0 }
        if p > 100.0 { p = 100.0 }
        Double target = (p / 100.0) * (self._count as Double)
        if target <= 0.0 { return self._min }
        Long cumulative = 0
        Int index = 0
        while index < self._counts.length() {
            cumulative = cumulative + self._counts.get(index)
            if (cumulative as Double) >= target {
                if index < self._boundaries.length() { return self._boundaries.get(index) }
                return self._max
            }
            index = index + 1
        }
        return self._max
    }

    List<HistogramBucket> buckets() {
        List<HistogramBucket> result = []
        Int index = 0
        while index < self._counts.length() {
            Double? lower = null
            Double? upper = null
            if index > 0 { lower = self._boundaries.get(index - 1) }
            if index < self._boundaries.length() { upper = self._boundaries.get(index) }
            result.push(new HistogramBucket(lower, upper, self._counts.get(index)))
            index = index + 1
        }
        return result
    }

    Bool merge(BucketHistogram other) {
        if other == null { throw "BucketHistogram.merge: null other" }
        if other._boundaries.length() != self._boundaries.length() {
            return false
        }
        Int index = 0
        while index < self._boundaries.length() {
            if other._boundaries.get(index) != self._boundaries.get(index) {
                return false
            }
            index = index + 1
        }
        index = 0
        while index < self._counts.length() {
            self._counts.set(index, self._counts.get(index) + other._counts.get(index))
            index = index + 1
        }
        if other._hasValues {
            if !self._hasValues {
                self._min = other._min
                self._max = other._max
                self._hasValues = true
            } else {
                if other._min < self._min { self._min = other._min }
                if other._max > self._max { self._max = other._max }
            }
        }
        self._count = self._count + other._count
        self._sum = self._sum + other._sum
        self._sumSquares = self._sumSquares + other._sumSquares
        return true
    }

    Void reset() {
        Int index = 0
        while index < self._counts.length() {
            self._counts.set(index, 0)
            index = index + 1
        }
        self._count = 0
        self._sum = 0.0
        self._sumSquares = 0.0
        self._min = 0.0
        self._max = 0.0
        self._hasValues = false
    }
}

class Summary {
    final List<Double> _values
    Long _sum
    Double _sumSquares
    Double _min
    Double _max
    Bool _hasValues

    Summary() {
        self._values = []
        self._sum = 0
        self._sumSquares = 0.0
        self._min = 0.0
        self._max = 0.0
        self._hasValues = false
    }

    Void observe(Double value) {
        self._values.push(value)
        self._sum = self._sum + 1
        self._sumSquares = self._sumSquares + value * value
        if !self._hasValues {
            self._min = value
            self._max = value
            self._hasValues = true
        } else {
            if value < self._min { self._min = value }
            if value > self._max { self._max = value }
        }
    }

    Long count() { return self._sum }
    Double sum() {
        Double total = 0.0
        Int index = 0
        while index < self._values.length() {
            total = total + self._values.get(index)
            index = index + 1
        }
        return total
    }
    Double min() { if !self._hasValues { return NaN() } return self._min }
    Double max() { if !self._hasValues { return NaN() } return self._max }
    Double mean() { if !self._hasValues { return NaN() } return self.sum() / (self._sum as Double) }
    Double variance() {
        if !self._hasValues { return NaN() }
        Double meanValue = self.mean()
        Double total = 0.0
        Int index = 0
        while index < self._values.length() {
            Double delta = self._values.get(index) - meanValue
            total = total + delta * delta
            index = index + 1
        }
        return total / (self._sum as Double)
    }
    Double sampleVariance() {
        if self._sum < 2 { return NaN() }
        return self.variance() * (self._sum as Double) / ((self._sum - 1) as Double)
    }
    Double stddev() { return sqrt(self.variance()) }
    Double sampleStddev() { return sqrt(self.sampleVariance()) }

    Double quantile(Double quantileValue) {
        if !self._hasValues { return NaN() }
        Double q = quantileValue
        if q < 0.0 { q = 0.0 }
        if q > 1.0 { q = 1.0 }
        List<Double> sorted = sortedBy<Double>(self._values, (Double a, Double b) -> a < b)
        if sorted.length() == 1 { return sorted.get(0) }
        Double position = q * ((sorted.length() - 1) as Double)
        Int left = position as Int
        Int right = left + 1
        if right >= sorted.length() { return sorted.get(sorted.length() - 1) }
        Double fraction = position - (left as Double)
        return sorted.get(left) + (sorted.get(right) - sorted.get(left)) * fraction
    }

    List<Double> quantiles(List<Double> quantileValues) {
        if quantileValues == null { throw "Summary.quantiles: null values" }
        List<Double> result = []
        Int index = 0
        while index < quantileValues.length() {
            result.push(self.quantile(quantileValues.get(index)))
            index = index + 1
        }
        return result
    }

    Summary merge(Summary other) {
        if other == null { throw "Summary.merge: null other" }
        Int index = 0
        while index < other._values.length() {
            self.observe(other._values.get(index))
            index = index + 1
        }
        return self
    }

    Void reset() {
        self._values.clear()
        self._sum = 0
        self._sumSquares = 0.0
        self._min = 0.0
        self._max = 0.0
        self._hasValues = false
    }
}

class RunningStats {
    Long _count
    Double _mean
    Double _m2
    Double _sum
    Double _min
    Double _max
    Bool _hasValues

    RunningStats() {
        self._count = 0
        self._mean = 0.0
        self._m2 = 0.0
        self._sum = 0.0
        self._min = 0.0
        self._max = 0.0
        self._hasValues = false
    }

    Void add(Double value) {
        self._count = self._count + 1
        self._sum = self._sum + value
        Double delta = value - self._mean
        self._mean = self._mean + delta / (self._count as Double)
        self._m2 = self._m2 + delta * (value - self._mean)
        if !self._hasValues {
            self._min = value
            self._max = value
            self._hasValues = true
        } else {
            if value < self._min { self._min = value }
            if value > self._max { self._max = value }
        }
    }

    Long count() { return self._count }
    Double sum() { return self._sum }
    Double mean() { if !self._hasValues { return NaN() } return self._mean }
    Double min() { if !self._hasValues { return NaN() } return self._min }
    Double max() { if !self._hasValues { return NaN() } return self._max }
    Double variance() { if !self._hasValues { return NaN() } return self._m2 / (self._count as Double) }
    Double sampleVariance() { if self._count < 2 { return NaN() } return self._m2 / ((self._count - 1) as Double) }
    Double stddev() { return sqrt(self.variance()) }
    Double sampleStddev() { return sqrt(self.sampleVariance()) }

    RunningStats merge(RunningStats other) {
        if other == null { throw "RunningStats.merge: null other" }
        if other._count == 0 { return self }
        if self._count == 0 {
            self._count = other._count
            self._mean = other._mean
            self._m2 = other._m2
            self._sum = other._sum
            self._min = other._min
            self._max = other._max
            self._hasValues = other._hasValues
            return self
        }
        Long total = self._count + other._count
        Double delta = other._mean - self._mean
        self._m2 = self._m2 + other._m2 + delta * delta * (self._count as Double) * (other._count as Double) / (total as Double)
        self._mean = (self._mean * (self._count as Double) + other._mean * (other._count as Double)) / (total as Double)
        self._sum = self._sum + other._sum
        self._count = total
        if other._min < self._min { self._min = other._min }
        if other._max > self._max { self._max = other._max }
        return self
    }

    Void reset() {
        self._count = 0
        self._mean = 0.0
        self._m2 = 0.0
        self._sum = 0.0
        self._min = 0.0
        self._max = 0.0
        self._hasValues = false
    }
}

class Regression {
    final Double _slope
    final Double _intercept
    final Double _r2
    final List<Double> _residuals
    final Int _count

    Regression(List<Double> xValues, List<Double> yValues) {
        if xValues == null || yValues == null { throw "Regression: null input" }
        if xValues.length() != yValues.length() { throw "Regression: length mismatch" }
        if xValues.length() < 2 { throw "Regression: need at least 2 samples" }
        Double meanX = 0.0
        Double meanY = 0.0
        Int index = 0
        while index < xValues.length() {
            if isNaN(xValues.get(index)) || isNaN(yValues.get(index)) {
                throw "Regression: NaN input"
            }
            meanX = meanX + xValues.get(index)
            meanY = meanY + yValues.get(index)
            index = index + 1
        }
        meanX = meanX / (xValues.length() as Double)
        meanY = meanY / (xValues.length() as Double)
        Double numerator = 0.0
        Double denominator = 0.0
        index = 0
        while index < xValues.length() {
            Double dx = xValues.get(index) - meanX
            numerator = numerator + dx * (yValues.get(index) - meanY)
            denominator = denominator + dx * dx
            index = index + 1
        }
        if denominator == 0.0 { throw "Regression: zero x variance" }
        self._slope = numerator / denominator
        self._intercept = meanY - self._slope * meanX
        List<Double> residuals = []
        Double total = 0.0
        Double residualSum = 0.0
        index = 0
        while index < xValues.length() {
            Double predicted = self._slope * xValues.get(index) + self._intercept
            Double residual = yValues.get(index) - predicted
            residuals.push(residual)
            total = total + (yValues.get(index) - meanY) * (yValues.get(index) - meanY)
            residualSum = residualSum + residual * residual
            index = index + 1
        }
        self._residuals = residuals
        self._count = xValues.length()
        if total == 0.0 { self._r2 = 1.0 } else { self._r2 = 1.0 - residualSum / total }
    }

    Double slope() { return self._slope }
    Double intercept() { return self._intercept }
    Double predict(Double x) { return self._slope * x + self._intercept }
    Double r2() { return self._r2 }
    List<Double> residuals() { return self._residuals.copy() }
    Int count() { return self._count }
}

class MovingAverage {
    final Int _window
    final List<Double> _values
    Double _sum
    Int _index

    MovingAverage(Int window) {
        if window < 1 { throw "MovingAverage: window must be positive" }
        self._window = window
        self._values = []
        self._sum = 0.0
        self._index = 0
    }

    Void add(Double value) {
        if self._values.length() < self._window {
            self._values.push(value)
            self._sum = self._sum + value
        } else {
            self._sum = self._sum - self._values.get(self._index) + value
            self._values.set(self._index, value)
        }
        self._index = (self._index + 1) % self._window
    }

    Double average() { if self._values.length() == 0 { return NaN() } return self._sum / (self._values.length() as Double) }
    Int window() { return self._window }
    Int count() { return self._values.length() }
    Bool isFull() { return self._values.length() == self._window }

    Void reset() {
        self._values.clear()
        self._sum = 0.0
        self._index = 0
    }
}

class Ema {
    final Double _alpha
    Double? _value
    Bool _initialized
    Long _count

    Ema(Double alpha) {
        if isNaN(alpha) || alpha < 0.0 || alpha > 1.0 {
            throw "Ema: alpha must be in [0,1]"
        }
        self._alpha = alpha
        self._value = null
        self._initialized = false
        self._count = 0
    }

    Void add(Double value) {
        if !self._initialized {
            self._value = value
            self._initialized = true
        } else {
            self._value = self._alpha * value + (1.0 - self._alpha) * (self._value as Double)
        }
        self._count = self._count + 1
    }

    Double? value() { return self._value }
    Double alpha() { return self._alpha }
    Long count() { return self._count }
    Bool isInitialized() { return self._initialized }

    Void reset() {
        self._value = null
        self._initialized = false
        self._count = 0
    }
}
