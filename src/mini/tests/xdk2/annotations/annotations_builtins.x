protocol Shown {
    String show();
}

class Impl implements Shown {
    @ReadOnly Int value = 0

    @Override String show() {
        return "shown"
    }

    Void set(Int v) {
        self.value = v
    }
}

@Deprecated Int old() {
    return 1
}

@SuppressWarnings("AN0014")
static Int callOld() {
    return old()
}

static Int main() {
    Impl x = new Impl()
    x.set(7)
    print(x.show())
    print(x.value)
    print(callOld())
    return 0
}
