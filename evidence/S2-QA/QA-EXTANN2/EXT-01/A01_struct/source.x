struct P { Int x; }
extension P {
    Int twice() { return self.x * 2 }
}
static Int main() {
    P p = new P()
    p.x = 3
    print(p.twice())
    return 0
}
