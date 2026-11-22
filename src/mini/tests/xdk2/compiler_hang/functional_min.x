import xdk.functional

static Int main() {
    List<Int> items = [1, 2, 3, 4]
    Seq<Int> seq = new Seq<Int>(items)
    print(seq.length())
    print(seq.chunk(2).length())
    print(seq.window(2).length())
    print(seq.zip(seq).length())
    print(seq.zip(seq).get(0).first())
    print(seq.reversed().get(0))
    print(seq.take(2).length())
    return 0
}
