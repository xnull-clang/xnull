enum Status {
    Ready(0);
    final Int code;
    Status(Int c) { self.code = c }
    void bump() { self.code = 9 }
}
static Int main() { return 0 }
