// app-main：唯一入口（aggregator 的最小 app）。
static Int sumTo(Int n) {
    Int i = 1
    Int s = 0
    while i <= n {
        s = s + i
        i = i + 1
    }
    return s
}

static Int main() {
    print("proj02: app-main")
    print(sumTo(10))
    return 0
}
