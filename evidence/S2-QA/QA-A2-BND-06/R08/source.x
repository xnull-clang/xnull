enum Status {
    Ready(0);
    final Int code;
    Status(Int c) { self.code = c }
}
static Int main() {
    Status s = new Status.Ready()
    return 0
}
