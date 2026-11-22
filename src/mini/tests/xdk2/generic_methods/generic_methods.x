import xdk.text
class Box<T> {
    final T value
    Box(T v) { self.value = v }
    Box<R> map<R>(R(T) transform) { return new Box<R>(transform(self.value)) }
    R get<R>(R(T) transform) { return transform(self.value) }
}
class Tools {
    static R apply<T, R>(T value, R(T) transform) { return transform(value) }
}
static Int main() {
    Box<Int> box = new Box<Int>(7)
    String(Int) asText = (Int value) -> str(value)
    Box<String> text = box.map(asText)
    print(text.value)
    Int(String) asNumber = (String value) -> parseInt(value).value()
    Box<Int> number = text.map(asNumber)
    print(number.value)
    Box<String> explicit = box.map<String>(asText)
    print(explicit.value)
    Int(Int) doubleValue = (Int value) -> value * 2
    print(box.get(doubleValue))
    Int(Int) increment = (Int value) -> value + 1
    print(Tools.apply(3, increment))
    Box<String> inlineText = box.map((Int value) -> str(value))
    print(inlineText.value)
    return 0
}
