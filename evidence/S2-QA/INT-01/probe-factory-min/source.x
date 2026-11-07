class Device {
    Int v = 1;
    private Device() { }
}
factory DeviceFactory for Device {
    static Device create() { return new Device() }
}
static Int main() {
    Device d = DeviceFactory.create()
    print(d.v)
    return 0
}
