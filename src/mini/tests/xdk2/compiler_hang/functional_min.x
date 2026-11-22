import xdk.functional

static Int main() {
    List<Int> items = [1, 2, 3, 4]
    Seq<Int> seq = new Seq<Int>(items)
    List<String> words = ["a", "b", "c", "d"]
    Seq<String> wordSeq = new Seq<String>(words)
    print(wordSeq.length())
    print(wordSeq.get(0))
    print(seq.length())
    print(seq.chunk(2).length())
    print(seq.window(2).length())
    Seq<Pair<Int, String>> zipped = seq.zip(wordSeq)
    print(zipped.length())
    print(zipped.get(0).first())
    print(seq.reversed().get(0))
    print(seq.take(2).length())
    return 0
}
