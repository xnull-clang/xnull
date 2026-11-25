// xdk.random —— L4 可种子 PRNG、安全随机、加权选择（M18.1）
//
// 无全局随机状态：Random 自带 64 位状态；SecureRandom 每次调用走 OS CSPRNG。
// 稳定性：preview。合同见 docs/design/utils/random/。
package xdk.random
import xdk.errors
import xdk.bytes
import xdk.math

// ---------- RandomSource ----------
protocol RandomSource {
    Long nextLong();
    Double nextDouble();
    Bytes nextBytes(Int count);
}

// ---------- Random ----------
class Random implements RandomSource {
    Long _state
    Double _spare
    Bool _hasSpare

    Random() {
        self._state = nowMicrosRaw()
        if self._state == 0 { self._state = 88172645463325252 as Long }
        self._spare = 0.0
        self._hasSpare = false
    }

    Random(Long seed) {
        self._state = seed
        if self._state == 0 { self._state = 88172645463325252 as Long }
        self._spare = 0.0
        self._hasSpare = false
    }

    Void seed(Long value) {
        self._state = value
        if self._state == 0 { self._state = 88172645463325252 as Long }
        self._spare = 0.0
        self._hasSpare = false
    }

    private Long nextRaw() {
        Long x = self._state
        x = x ^ (x >> 12)
        x = x ^ (x << 25)
        x = x ^ (x >> 27)
        self._state = x
        return x * (2685821657736338717 as Long)
    }

    Long nextLong() {
        // 高位清零，保证非负；范围方法使用同一序列。
        return (self.nextRaw() >> 1) & (9223372036854775807 as Long)
    }

    Double nextDouble() {
        Long bits = (self.nextRaw() >> 11) & (9007199254740991 as Long)
        return (bits as Double) * (1.0 / 9007199254740992.0)
    }

    Bool nextBool() {
        return (self.nextRaw() & 1 as Long) == 1 as Long
    }

    Int nextInt() {
        return (self.nextLong() % 2147483647 as Long) as Int
    }

    Int nextIntBelow(Int max) {
        if max <= 0 { throw "Random.nextIntBelow: max <= 0" }
        Long span = max as Long
        return (self.nextLong() % span) as Int
    }

    Int nextIntRange(Int min, Int max) {
        if min >= max { throw "Random.nextIntRange: empty range" }
        Long span = (max as Long) - (min as Long)
        return ((min as Long) + (self.nextLong() % span)) as Int
    }

    Long nextLongRange(Long min, Long max) {
        if min >= max { throw "Random.nextLongRange: empty range" }
        Long span = max - min
        return min + (self.nextLong() % span)
    }

    Double nextGaussian() {
        if self._hasSpare {
            self._hasSpare = false
            return self._spare
        }
        Double u1 = 1.0 - self.nextDouble()
        Double u2 = self.nextDouble()
        Double radius = sqrt(-2.0 * log(u1))
        Double angle = 2.0 * 3.141592653589793 * u2
        self._spare = radius * sin(angle)
        self._hasSpare = true
        return radius * cos(angle)
    }

    Bytes nextBytes(Int count) {
        if count < 0 { throw "Random.nextBytes: negative count" }
        Bytes result = Bytes.fromString("")
        Int index = 0
        Long bits = 0
        while index < count {
            if index % 8 == 0 { bits = self.nextRaw() }
            Int shift = (index % 8) * 8
            Int value = ((bits >> (shift as Long)) & 255 as Long) as Int
            result.push(value)
            index = index + 1
        }
        return result
    }

    Void shuffle<T>(List<T> values) {
        if values == null { throw "Random.shuffle: null list" }
        Int index = values.length() - 1
        while index > 0 {
            Int other = self.nextIntBelow(index + 1)
            T temporary = values.get(index)
            values.set(index, values.get(other))
            values.set(other, temporary)
            index = index - 1
        }
    }
}

// ---------- SecureRandom ----------
class SecureRandom implements RandomSource {
    SecureRandom() { }

    Long nextLong() {
        String hex = secureRandomHexRaw(8)
        if hex.length() != 16 { return 0 }
        Bytes bytes = fromHex(hex)
        Long value = 0 as Long
        Int index = 0
        while index < 8 {
            value = (value << 8) | (bytes.get(index) as Long)
            index = index + 1
        }
        return value & (9223372036854775807 as Long)
    }

    Double nextDouble() {
        Long bits = self.nextLong() >> 11
        return (bits as Double) * (1.0 / 9007199254740992.0)
    }

    Bytes nextBytes(Int count) {
        if count < 0 { throw "SecureRandom.nextBytes: negative count" }
        if count == 0 { return Bytes.fromString("") }
        String hex = secureRandomHexRaw(count)
        if hex.length() != count * 2 {
            throw "SecureRandom.nextBytes: random source unavailable"
        }
        return fromHex(hex)
    }

    Int nextIntBelow(Int max) {
        if max <= 0 { throw "SecureRandom.nextIntBelow: max <= 0" }
        return (self.nextLong() % (max as Long)) as Int
    }

    Int nextIntRange(Int min, Int max) {
        if min >= max { throw "SecureRandom.nextIntRange: empty range" }
        Long span = (max as Long) - (min as Long)
        return ((min as Long) + (self.nextLong() % span)) as Int
    }

    Void shuffle<T>(List<T> values) {
        if values == null { throw "SecureRandom.shuffle: null list" }
        Int index = values.length() - 1
        while index > 0 {
            Int other = self.nextIntBelow(index + 1)
            T temporary = values.get(index)
            values.set(index, values.get(other))
            values.set(other, temporary)
            index = index - 1
        }
    }

    Void reseed() {
        // OS CSPRNG 不需要显式重播种；保留接口。
    }
}

// ---------- WeightedChoice ----------
class WeightedChoice<T> {
    final List<T> _values
    final List<Double> _weights
    Double _total

    WeightedChoice() {
        self._values = []
        self._weights = []
        self._total = 0.0
    }

    Void add(T value, Double weight) {
        if weight <= 0.0 { throw "WeightedChoice.add: invalid weight" }
        if mathIsNanRaw(weight) != 0 { throw "WeightedChoice.add: non-finite weight" }
        if mathIsInfRaw(weight) != 0 { throw "WeightedChoice.add: non-finite weight" }
        self._values.push(value)
        self._weights.push(weight)
        self._total = self._total + weight
    }

    T pick(RandomSource random) {
        if random == null { throw "WeightedChoice.pick: null random" }
        if self._values.length() == 0 { throw "WeightedChoice.pick: empty" }
        Double target = random.nextDouble() * self._total
        Double cumulative = 0.0
        Int index = 0
        while index < self._values.length() {
            cumulative = cumulative + self._weights.get(index)
            if target < cumulative { return self._values.get(index) }
            index = index + 1
        }
        return self._values.get(self._values.length() - 1)
    }

    Double totalWeight() {
        return self._total
    }

    Int length() {
        return self._values.length()
    }

    Void clear() {
        self._values.clear()
        self._weights.clear()
        self._total = 0.0
    }
}
