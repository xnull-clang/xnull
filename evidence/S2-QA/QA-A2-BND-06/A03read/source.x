enum Status {
    Ready(0);
    final Int code;
    Status(Int c) { self.code = c }
}
static Int main() {
    Int c = Status.Ready.code
    print(c)
    return c
}
