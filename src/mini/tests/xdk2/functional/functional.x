import xdk.functional

static Int main() {
    List<Int> items = [1, 2, 2, 3, 4]
    Seq<Int> seq = new Seq<Int>(items)
    Int(Int) doubleValue = (Int value) -> value * 2
    Bool(Int) even = (Int value) -> value % 2 == 0
    Int(Int, Int) compare = (Int left, Int right) -> left - right
    Bool(Int) lessThanThree = (Int value) -> value < 3
    String(Int) asText = (Int value) -> str(value)
    String(Int) parity = (Int value) -> str(value % 2)
    Bool(Int) greaterThanTwo = (Int value) -> value > 2
    Int(Int, Int) add = (Int left, Int right) -> left + right
    Bool(Int) equalFour = (Int value) -> value == 4
    Bool(Int) positive = (Int value) -> value > 0
    Bool(Int) negative = (Int value) -> value < 0
    Bool(Int) equalTwo = (Int value) -> value == 2
    print(seq.length())
    print(seq.isEmpty())
    print(seq.get(0))
    print(seq.map(doubleValue).get(2))
    print(seq.filter(even).length())
    print(seq.distinct().length())
    print(seq.sorted(compare).get(0))
    print(seq.reversed().get(0))
    print(seq.take(2).length())
    print(seq.skip(3).length())
    print(seq.takeWhile(lessThanThree).length())
    print(seq.dropWhile(lessThanThree).length())
    print(seq.chunk(2).length())
    print(seq.window(2).length())
    print(seq.zip(seq).length())
    print(seq.zip(seq).get(0).first())
    List<Int> empty = []
    print(seq.groupBy(parity).getOr("0", empty).length())
    print(seq.partition(greaterThanTwo).first().length())
    print(seq.reduce(0, add))
    print(seq.anyMatch(equalFour))
    print(seq.allMatch(positive))
    print(seq.noneMatch(negative))
    print(seq.firstOrNull())
    print(seq.count(equalTwo))
    print(seq.toList().length())
    print(seq.toSet().has(3))
    print(seq.join(",", asText))
    print(Sequences.range(1, 4).length())
    print(Sequences.rangeStep(0, 10, 3).length())
    print(Sequences.repeatValue(7, 3).length())
    Int() nine = () -> 9
    print(Sequences.generate(3, nine).get(0))
    Int(Int) twice = (Int value) -> value * 2
    print(Sequences.iterate(1, 4, twice).get(3))
    print(Sequences.concat(Sequences.range(1, 3), Sequences.range(5, 7)).length())
    print(Sequences.fromNullable(8).length())
    Int() five = () -> 5
    Lazy<Int> lazy = new Lazy<Int>(five)
    print(lazy.get())
    print(lazy.isInitialized())
    print(lazy.toString())
    return 0
}
