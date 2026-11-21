import xdk.collections
import xdk.text

static Int main() {
    List<Int> xs = [3, 1, 2]
    List<Int> s = sortBy(xs, (Int a, Int b) -> a < b)
    print(s.get(0))
    print(s.get(2))

    List<Int> dup = [1, 1, 2, 3, 3]
    List<Int> d = dedup(dup, (Int a, Int b) -> a == b)
    print(d.length())
    print(d.get(0))
    print(d.get(2))

    List<Int> hay = [4, 5, 6]
    Int? found = find(hay, (Int x) -> x > 4)
    print(found == null)
    print(found)

    List<Int> none = [7, 8]
    Int? missing = find(none, (Int x) -> x == 99)
    print(missing == null)

    List<String> names = ["b", "a", "c"]
    List<String> ns = sortBy(names, (String a, String b) -> compareText(a, b) < 0)
    print(ns.get(0))
    print(ns.get(1))
    print(ns.get(2))

    List<String> nd = dedup(names, (String a, String b) -> a == b)
    print(nd.length())

    List<String> shay = ["x", "y"]
    String? sf = find(shay, (String t) -> t == "y")
    print(sf == null)
    print(sf)

    List<Int> grouped = [1, 2, 3, 4, 5, 6]
    List<Int> empty = []
    Map<Int, List<Int>> byRemainder = groupByInt<Int>(grouped, (Int x) -> x % 2)
    print(byRemainder.length())
    print(byRemainder.getOr(0, empty).length())
    print(byRemainder.getOr(1, empty).length())
    print(byRemainder.getOr(1, empty).get(0))

    Map<String, List<Int>> byParity = groupBy<Int, String>(grouped, (Int x) -> str(x % 2))
    print(byParity.length())
    print(byParity.getOr("0", empty).length())
    print(byParity.getOr("1", empty).get(1))

    print(joinWith<Int>(grouped, "|", (Int x) -> str(x)))
    return 0
}
