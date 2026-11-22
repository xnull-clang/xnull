import xdk.functional

class Counter {
    Int calls
    Counter() { self.calls = 0 }
    Void inc() { self.calls = self.calls + 1 }
}

static Int main() {
    List<Int> items = [1, 2, 2, 3, 4]
    Seq<Int> seq = new Seq<Int>(items)
    Seq<Int> made = Seq.of(items)
    print(made.length())
    String(Int) asText = (Int value) -> str(value)
    Seq<String> texts = seq.map(asText)
    print(texts.length())
    print(texts.get(1))
    Seq<String> flat = seq.flatMap((Int value) -> {
        List<String> out = []
        out.push(str(value))
        out.push(str(value))
        return out
    })
    print(flat.length())
    List<String> words = ["a", "b"]
    Seq<String> wordSeq = new Seq<String>(words)
    Seq<Pair<Int, String>> zipped = seq.zip(wordSeq)
    print(zipped.length())
    print(zipped.get(0).first())
    print(zipped.get(0).second())
    Int(Int) parity = (Int value) -> value % 2
    Map<Int, List<Int>> groups = seq.groupBy(parity)
    List<Int> emptyGroup = []
    print(groups.getOr(0, emptyGroup).length())
    print(groups.getOr(1, emptyGroup).length())
    Bool(Int) isEven = (Int value) -> value % 2 == 0
    Int(Int, Int) compareInts = (Int left, Int right) -> left - right
    Bool(Int) lessThanThree = (Int value) -> value < 3
    Int(Int, Int) addInts = (Int left, Int right) -> left + right
    Bool(Int) equalsFour = (Int value) -> value == 4
    print(seq.filter(isEven).length())
    print(seq.distinct().length())
    print(seq.sorted(compareInts).get(0))
    print(seq.take(2).length())
    print(seq.takeWhile(lessThanThree).length())
    print(seq.chunk(2).length())
    print(seq.window(2).length())
    print(seq.reduce(0, addInts))
    print(seq.anyMatch(equalsFour))
    print(seq.join(",", asText))
    Seq<Int> ranged = Sequences.range(1, 4)
    print(ranged.length())
    print(ranged.get(2))
    Seq<Int> stepped = Sequences.rangeStep(0, 10, 3)
    print(stepped.length())
    Seq<Int> repeated = Sequences.repeatValue(7, 3)
    print(repeated.get(1))
    Int() nine = () -> 9
    Seq<Int> generated = Sequences.generate(3, nine)
    print(generated.length())
    Int(Int) twice = (Int value) -> value * 2
    Seq<Int> iterated = Sequences.iterate(1, 4, twice)
    print(iterated.get(3))
    Seq<Int> leftRange = Sequences.range(1, 3)
    Seq<Int> rightRange = Sequences.range(5, 7)
    Seq<Int> concatenated = Sequences.concat(leftRange, rightRange)
    print(concatenated.length())
    List<Int> firstNested = [1, 2]
    List<Int> secondNested = []
    List<Int> thirdNested = [3]
    List<List<Int>> nested = []
    nested.push(firstNested)
    nested.push(secondNested)
    nested.push(thirdNested)
    Seq<Int> flattened = Sequences.flatten(nested)
    print(flattened.length())
    Seq<Int> nullableSeq = Sequences.fromNullable(8)
    print(nullableSeq.length())
    List<Int> emptyItems = []
    Seq<Int> emptySeq = new Seq<Int>(emptyItems)
    Counter counter = new Counter()
    Int() supplier = () -> {
        counter.inc()
        return 7
    }
    Lazy<Int> lazy = new Lazy<Int>(supplier)
    print(lazy.isInitialized())
    print(counter.calls)
    print(lazy.toString())
    print(lazy.get())
    print(counter.calls)
    print(lazy.get())
    print(counter.calls)
    print(lazy.isInitialized())
    Counter mappedCounter = new Counter()
    Lazy<Int> mapped = lazy.map((Int value) -> {
        mappedCounter.inc()
        return value * 2
    })
    print(mappedCounter.calls)
    print(mapped.get())
    print(mappedCounter.calls)
    Lazy<String> mappedText = lazy.map((Int value) -> str(value))
    print(mappedText.get())
    Lazy<Int> ready = Lazy.ready(5)
    print(ready.isInitialized())
    print(ready.get())
    Seq<Int> emptyFromExpected = Seq.empty()
    Seq<Int> emptyExplicit = Seq.empty<Int>()
    print(emptyFromExpected.length())
    print(emptyExplicit.length())
    print(emptyFromExpected.zip(wordSeq).length())
    Seq<String> chained = seq.map(asText).map((String text) -> text + "!")
    print(chained.get(0))
    Seq<List<Int>> chunks = seq.chunk(2)
    print(chunks.get(0).length())
    return 0
}
