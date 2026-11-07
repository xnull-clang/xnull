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
static Int main() {
    print(Status.Ready)
    print(Status.Ready.code)
    return 0
}
