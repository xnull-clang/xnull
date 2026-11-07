package interp

import "testing"

// INT-01：Result/try/defer × 对象/deinit 组合。
func TestS2INT01ResultTryObject(t *testing.T) {
	out, err := runSrc(t, `
class Res {
    Int v;
    Res(Int v) { self.v = v }
    Result<Int, String> get(Bool ok) {
        defer print("m-defer")
        errdefer print("m-err")
        if !ok { return Err("bad") }
        return Ok(self.v)
    }
    void deinit() { print("dR") }
}
static Result<Int, String> run() {
    errdefer print("outer-err")
    defer print("outer-defer")
    if true {
        Res r = new Res(7)
        Int v = try r.get(false)
        print(v)
    }
    return Ok(0)
}
static Int main() {
    Result<Int, String> r = run()
    if r.isErr() { print("caught:" + r.error()) }
    return 0
}`)
	want := "m-err\nm-defer\ndR\nouter-defer\nouter-err\ncaught:bad\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}

// INT-01：工厂创建 + Result 错误路径 + defer/errdefer。
func TestS2INT01FactoryResult(t *testing.T) {
	out, err := runSrc(t, `
class Device {
    String name;
    private Device(String n) { self.name = n }
    String label() { return name }
}
factory DeviceFactory for Device {
    static Device create(String n) { return new Device(n) }
    static Result<Device, String> open(Bool ok) {
        defer print("f-defer")
        errdefer print("f-err")
        if !ok { return Err("boom") }
        return Ok(new Device("ok"))
    }
}
static Int main() {
    Device d = DeviceFactory.create("x")
    print(d.label())
    Result<Device, String> r = DeviceFactory.open(false)
    if r.isErr() { print("f-caught:" + r.error()) }
    return 0
}`)
	want := "x\nf-err\nf-defer\nf-caught:boom\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}

// INT-01：枚举 switch × 类方法 + 枚举字段。
func TestS2INT01EnumSwitchObject(t *testing.T) {
	out, err := runSrc(t, `
enum Color { Red, Green, Blue }
class Holder {
    Color c = Color.Green;
    String name() {
        switch c {
            case Color.Red: return "r"
            case Color.Green: return "g"
            case Color.Blue: return "b"
        }
        return "?"
    }
}
static Int main() {
    Holder h = new Holder()
    print(h.name())
    h.c = Color.Blue
    print(h.name())
    return 0
}`)
	want := "g\nb\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}
