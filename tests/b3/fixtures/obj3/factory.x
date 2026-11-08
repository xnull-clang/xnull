class Device {
    String name;
    Device(String n) { self.name = n }
}
factory DeviceFactory for Device {
    static Device create(String name) {
        return new Device(name)
    }
}
static Int main() {
    Device d = DeviceFactory.create("A")
    print(d.name)
    return 0
}
