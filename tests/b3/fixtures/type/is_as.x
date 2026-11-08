static Int main() {
    Any a = 42 as Any
    print(a is Int)
    print(a as? Int)
    print(a is String)
    Any b = "hi" as Any
    print(b is String)
    print(b as? String)
    Any c = true as Any
    print(c is Bool)
    print(c as? Bool)
    return 0
}
