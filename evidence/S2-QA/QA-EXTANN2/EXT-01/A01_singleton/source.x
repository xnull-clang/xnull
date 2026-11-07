singleton S { Int n = 2; }
extension S {
    Int twice() { return self.n * 2 }
}
static Int main() {
    print(S.instance.twice())
    return 0
}
