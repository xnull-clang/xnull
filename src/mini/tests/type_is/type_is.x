package type_is

protocol P {
    Int x();
}

protocol ChildP : P {
    Int y();
}

protocol Unused {
    Int unused();
}

class A implements P {
    Int x() { return 1 }
}

class B implements P {
    Int x() { return 2 }
}

class Base {
    Int v() { return 3 }
}

class Sub : Base {
}

class HolderBase implements P {
    Int x() { return 4 }
}

class HolderSub : HolderBase {
}

class C implements ChildP {
    Int x() { return 5 }
    Int y() { return 6 }
}

static Int main() {
    P a = new A()
    P b = new B()
    print("p-a-a=" + str(a is A))
    print("p-a-b=" + str(a is B))
    print("p-b-a=" + str(b is A))
    print("p-b-b=" + str(b is B))

    Base plain = new Base()
    Base sub = new Sub()
    print("base-sub=" + str(sub is Sub))
    print("base-base=" + str(sub is Base))
    print("plain-sub=" + str(plain is Sub))

    HolderSub holder = new HolderSub()
    print("holder-p=" + str(holder is P))
    print("holder-base=" + str(holder is HolderBase))
    print("holder-sub=" + str(holder is HolderSub))
    print("holder-a=" + str(holder is A))

    ChildP childProtocol = new C()
    print("child-p=" + str(childProtocol is P))
    print("child-child-p=" + str(childProtocol is ChildP))
    print("child-a=" + str(childProtocol is A))

    P? maybe = null
    print("null-a=" + str(maybe is A))

    Int number = 1
    Long wide = 2
    String text = "x"
    print("int-int=" + str(number is Int))
    print("int-long=" + str(number is Long))
    print("long-long=" + str(wide is Long))
    print("string-string=" + str(text is String))
    print("string-int=" + str(text is Int))

    print("unused=" + str(a is Unused))
    A direct = new A()
    print("direct-a=" + str(direct is A))
    print("qualified-a=" + str(direct is type_is.A))
    return 0
}
