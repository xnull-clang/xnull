class S { Int n = 0; void inc() { self.n = self.n + 1 } void dec() { self.n = self.n - 1 } }
static Result<Int, String> tx(S s) {
    s.inc()
    errdefer s.dec()
    s.inc()
    errdefer s.dec()
    return Err("fail")
}
static Int main() { S s = new S(); Result<Int,String> r = tx(s); print(s.n); print(r.error()); return 0 }
