package app.random
import xdk.random
import xdk.errors
import xdk.math

static Int main() {
    Random first = new Random(42 as Long)
    Random second = new Random(42 as Long)
    Random other = new Random(43 as Long)
    Long firstOne = first.nextLong()
    Long firstTwo = first.nextLong()
    Long secondOne = second.nextLong()
    Long secondTwo = second.nextLong()
    print("same=" + str(firstOne == secondOne) + "," + str(firstTwo == secondTwo) +
        "," + str(firstOne != other.nextLong()))

    Bool doubleOk = true
    Int index = 0
    while index < 20 {
        Double value = first.nextDouble()
        if value < 0.0 || value >= 1.0 { doubleOk = false }
        index = index + 1
    }
    print("double=" + str(doubleOk))

    Bool rangeOk = true
    index = 0
    while index < 100 {
        Int below = first.nextIntBelow(10)
        Int ranged = first.nextIntRange(-5, 5)
        Long longRanged = first.nextLongRange(100 as Long, 110 as Long)
        if below < 0 || below >= 10 { rangeOk = false }
        if ranged < -5 || ranged >= 5 { rangeOk = false }
        if longRanged < 100 as Long || longRanged >= 110 as Long { rangeOk = false }
        index = index + 1
    }
    print("range=" + str(rangeOk))

    Bytes bytes = first.nextBytes(7)
    print("bytes=" + str(bytes.length()))

    List<Int> values = [1, 2, 3, 4, 5]
    first.shuffle(values)
    Int sum = 0
    index = 0
    while index < values.length() {
        sum = sum + values.get(index)
        index = index + 1
    }
    print("shuffle=" + str(values.length()) + "," + str(sum))

    Bool gaussianOk = true
    index = 0
    while index < 20 {
        Double value = first.nextGaussian()
        if mathIsNanRaw(value) != 0 || mathIsInfRaw(value) != 0 { gaussianOk = false }
        index = index + 1
    }
    print("gaussian=" + str(gaussianOk))

    WeightedChoice<String> choice = new WeightedChoice<String>()
    choice.add("a", 1.0)
    choice.add("b", 3.0)
    Int countA = 0
    Int countB = 0
    Random sampler = new Random(7 as Long)
    index = 0
    while index < 1000 {
        String picked = choice.pick(sampler)
        if picked == "a" { countA = countA + 1 }
        if picked == "b" { countB = countB + 1 }
        index = index + 1
    }
    print("weight=" + str(choice.length()) + "," + str(choice.totalWeight()) + "," +
        str(countA > 100 && countA < 500) + "," + str(countA + countB == 1000))
    choice.clear()
    print("weight-clear=" + str(choice.length()) + "," + str(choice.totalWeight()))

    WeightedChoice<Int> single = new WeightedChoice<Int>()
    single.add(9, 2.0)
    print("weight-single=" + str(single.pick(sampler)))

    SecureRandom secure = new SecureRandom()
    Bytes secret = secure.nextBytes(16)
    Int nonZero = 0
    index = 0
    while index < secret.length() {
        if secret.get(index) != 0 { nonZero = nonZero + 1 }
        index = index + 1
    }
    Double secureDouble = secure.nextDouble()
    Int secureBelow = secure.nextIntBelow(10)
    Int secureRange = secure.nextIntRange(5, 8)
    print("secure=" + str(secret.length()) + "," + str(nonZero > 0) + "," +
        str(secureDouble >= 0.0 && secureDouble < 1.0) + "," +
        str(secureBelow >= 0 && secureBelow < 10) + "," +
        str(secureRange >= 5 && secureRange < 8))
    return 0
}
