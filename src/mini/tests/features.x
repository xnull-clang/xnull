static Int main() {
    Double x = 1.5
    Int bits = (0x0F << 4) | 3
    print($"x={x} bits={bits}")
    String? missing = null
    if missing == null {
        print("none")
    }
    Int n = 7
    print(n > 3 ? n >> 1 : 0)
    String s = "  AbC  "
    String r = "aXbX"
    String u = "éA"
    String empty = ""
    String abc = "abc"
    Int sw = 2
    switch sw {
        case 1:
            print("sw-one")
        case 2:
            print("sw-two")
        default:
            print("sw-other")
    }
    switch u {
        case "éA":
            print("sw-utf8")
        default:
            print("sw-other-string")
    }
    print("[" + s.trim() + "]")
    print(r.replace("X", "-"))
    print(s.trim().toUpper())
    print(s.trim().toLower())
    print(u.toUpper())
    print(u.toLower())
    print(u.replace("é", "e"))
    print(empty.trim() == "")
    print(abc.replace("", "X"))
    return 0
}
