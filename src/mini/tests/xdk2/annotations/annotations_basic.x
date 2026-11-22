@annotation Marker {
    final String name = ""
    final Int level = 0
}

@annotation Label {
    final String text = "default"
}

@Marker("device", 2)
class Device {
    @ReadOnly Int count = 0

    Void bump() {
        self.count = self.count + 1
    }
}

static Int main() {
    Device d = new Device()
    d.bump()
    print("device")
    print(d.count)
    return 0
}
