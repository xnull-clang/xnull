protocol Greeter {
    String greet();
}

class Hello implements Greeter {
    String greet() { return "hello" }
}

class Bye implements Greeter {
    String greet() { return "bye" }
}

enum DStatus {
    Ready(0, "ready"),
    Failed(1, "failed");

    final Int code;
    final String label;

    DStatus(Int code, String label) {
        self.code = code
        self.label = label
    }

    Int getCode() { return self.code }
    String getLabel() { return self.label }
}

class ClosureBox {
    Int base = 10;
    Int(Int) adder() {
        Int(Int) f = (Int x) -> x + base
        return f
    }
}

class FunctionHolder {
    Int(Int) f
    FunctionHolder(Int(Int) fn) { self.f = fn }
    Int apply(Int x) { return self.f(x) }
}

class InheritBase {
    Int x = 2
    Int getX() { return self.x }
}

class InheritChild : InheritBase {
    Int y = 3
    Int sum() { return self.getX() + self.y }
}

enum SwColor { Red, Blue }

static Int applyOne(Int(Int) fn, Int value) {
    return fn(value)
}

static Int(Int) makeAdder(Int base) {
    return (Int x) -> x + base
}

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
    Int(Int) inc = (Int v) -> v + 1
    print("lambda " + str(inc(4)))
    Int(Int) twice = (Int v) -> { return v * 2 }
    print("lambda-block " + str(twice(3)))
    Int() zero = () -> 42
    print("lambda0 " + str(zero()))
    Int base = 10
    Int(Int) addBase = (Int v) -> v + base
    print("lambda-capture " + str(addBase(5)))
    base = 100
    print("lambda-capture-value " + str(addBase(5)))
    Int(Int) fact = (Int m) -> {
        if m < 2 {
            return 1
        }
        return m * fact(m - 1)
    }
    print("lambda-rec " + str(fact(5)))
    Int offset = 3
    Int(Int) nested = (Int v) -> {
        Int(Int) inner = (Int w) -> w + offset + v
        return inner(1)
    }
    print("lambda-nested " + str(nested(2)))
    InheritChild capObj = new InheritChild()
    Int() objCap = () -> capObj.sum()
    print("lambda-object " + str(objCap()))
    ClosureBox cb = new ClosureBox()
    Int(Int) methodCap = cb.adder()
    print("lambda-method " + str(methodCap(7)))
    Int directBase = 5
    print("lambda-direct " + str(applyOne((Int v) -> v + directBase, 3)))
    Int(Int) returnedCap = makeAdder(30)
    print("lambda-return " + str(returnedCap(2)))
    FunctionHolder fh = new FunctionHolder((Int v) -> v + directBase)
    print("lambda-field " + str(fh.apply(2)))
    Int(Int) fieldCopy = fh.f
    print("lambda-field-copy " + str(fieldCopy(1)))
    Greeter pg = new Hello()
    print("protocol " + pg.greet())
    pg = new Bye()
    print("protocol " + pg.greet())
    DStatus ds = DStatus.Ready
    print("dataenum " + str(ds.getCode()) + " " + ds.getLabel())
    if ds == DStatus.Ready {
        print("dataenum-ready")
    }
    switch ds {
        case DStatus.Ready:
            print("dataenum-switch")
        case DStatus.Failed:
            print("dataenum-failed")
    }
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
    print(abc.endsWith("bc"))
    print(abc.endsWith("x"))
    print(abc.charAt(1))
    print(abc.indexOfByte("b"))
    return 0
}
