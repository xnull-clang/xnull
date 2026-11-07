class Device {
    String name;
    private Device(String n) { self.name = n }
    String label() { return name }
}
factory DeviceFactory for Device {
    static Device create(String n) { return new Device(n) }
    static Result<Int, String> open(Bool ok) {
        defer print("f-defer")
        errdefer print("f-err")
        if !ok { return Err("boom") }
        return Ok(1)
    }
}
static Int main() {
    Device d = DeviceFactory.create("x")
    print(d.label())
    Result<Int, String> r = DeviceFactory.open(false)
    if r.isErr() { print("f-caught:" + r.error()) }
    return 0
}
