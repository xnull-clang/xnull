import xdk.sync

class Counter {
    Int value

    Counter(Int value) {
        self.value = value
    }
}

static Int main() {
    Counter c = new Counter(1)
    Mutex<Counter> m = Mutex(c)
    Result<void,TaskError> first = m.withLock((Counter x) -> {
        x.value = x.value + 1
    })
    Result<void,TaskError> second = m.withLock((Counter x) -> {
        x.value = x.value + 1
    })
    print(first.isOk())
    print(second.isOk())
    print(c.value)
    return 0
}
