protocol P { Int f(); }
class C implements P { Int f(){ return 7 } void deinit(){ print("dC") } }
static P make() { C c = new C(); return c }
static Int main() { P p = make(); print(p.f()); print("after"); return 0 }
