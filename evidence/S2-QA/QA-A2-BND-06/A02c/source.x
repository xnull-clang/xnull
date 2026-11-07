enum Status {
    Ready(0), Failed(1);
    final Int code;
    Status(Int c) { self.code = c }
}
static Int main() {
    print(Status.Ready === Status.Ready)
    print(Status.Ready === Status.Failed)
    print(Status.Ready == Status.Ready)
    return 0
}
