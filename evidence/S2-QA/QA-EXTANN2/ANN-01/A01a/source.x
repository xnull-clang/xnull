@annotation Marker {
    final String tag = "default";
    final Int level = 1;
}
@Marker("cls", 2)
class Device {
    @Marker
    String name;
    Device(String n) { self.name = n }
    @Marker("m", 3)
    String label() { return self.name }
}
enum Color { @Marker("e", 4) Red, Green }
static Int helper(@Marker("p", 5) Int x) { return x }
static Int main() {
    Device d = new Device("x")
    print(d.label())
    print(helper(7))
    return 0
}
