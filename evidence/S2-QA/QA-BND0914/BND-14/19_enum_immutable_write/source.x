enum S { A(0); final Int c; S(Int x) { self.c = x } }
static Int main() { S.A.c = 1; return 0 }
