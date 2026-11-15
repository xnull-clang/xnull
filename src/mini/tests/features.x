class InheritBase {
    Int x = 2
    Int getX() { return self.x }
}

class InheritChild : InheritBase {
    Int y = 3
    Int sum() { return self.getX() + self.y }
}

enum SwColor { Red, Blue }

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
    Int sb = 1
    switch sb {
        case 1:
            print("switch-break")
            break
            print("switch-unreachable")
        default:
            print("switch-bad")
    }
    Int di = 0
    do {
        print("do " + str(di))
        di = di + 1
    } while di < 2
    for j in 0..<2 {
        print("range " + str(j))
    }
    for k in 1...2 {
        print("closed " + str(k))
    }
    InheritChild ic = new InheritChild()
    print("inherit " + str(ic.sum()))
    SwColor sc = SwColor.Blue
    switch sc {
        case SwColor.Red:
            print("enum-red")
        case SwColor.Blue:
            print("enum-blue")
    }
    Int gi = 0
again:
    gi = gi + 1
    if gi < 2 {
        goto again
    }
    print("goto " + str(gi))
    empty: ;
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
