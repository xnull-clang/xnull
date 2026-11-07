enum Status {
    Ready(0, "ready"),
    Failed(1, "failed");
    final Int code;
    final String label;
    Status(Int code, String label) {
        self.code = code
        self.label = label
    }
}
extension Status {
    Bool isReady() { return self.code == 0 }
}
static Int main() {
    print(Status.Ready.isReady())
    print(Status.Failed.isReady())
    return 0
}
