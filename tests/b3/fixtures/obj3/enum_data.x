enum Status {
    Ready(0), Failed(1);
    final Int code;
    Status(Int c) { self.code = c }
    Int get() { return self.code }
}
static Int main() {
    print(Status.Ready)
    print(Status.Ready.code)
    print(Status.Failed.get())
    print(Status.Ready == Status.Ready)
    return 0
}
