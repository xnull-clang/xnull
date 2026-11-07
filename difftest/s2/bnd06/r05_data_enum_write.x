enum Status {
    Ready(0);
    final Int code;
    Status(Int c) { self.code = c }
}
static Int main() {
    Status.Ready.code = 9
    print(Status.Ready.code)
    return 0
}
