protocol P { Int f(); }
class C implements P { }
extension C { Int f() { return 1 } }
static Int main() { return 0 }
