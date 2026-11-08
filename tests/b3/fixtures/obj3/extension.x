class Device {
    String name;
    Device(String n) { self.name = n }
}
extension Device {
    String label() { return "L:" + self.name }
}
static Int main() {
    Device d = new Device("x")
    print(d.label())
    return 0
}
