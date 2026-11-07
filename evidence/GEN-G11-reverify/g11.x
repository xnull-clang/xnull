static T boxFirst<T>(T v) {
    T local = v
    List<T> box = [local]
    return box.get(0)
}
static Int main() { print(boxFirst<Int>(4)); return 0 }
