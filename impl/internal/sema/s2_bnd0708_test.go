package sema

import "testing"

// BND-07/08：singleton/factory 名称空间与禁止面。
func TestS2BND0708SingletonFactory(t *testing.T) {
	// singleton 注册 + instance 自动 + 字段/方法可读。
	expectNone(t, `
singleton AppInfo {
    String name = "XNull";
    Int count = 3;
    Int twice() { return count * 2 }
}
static Int main() {
    print(AppInfo.instance.name)
    print(AppInfo.instance.twice())
    return 0
}`)

	// new singleton 拒绝。
	expectCode(t, `
singleton AppInfo { Int x = 1; }
static Int main() {
    AppInfo a = new AppInfo()
    return 0
}`, TySingletonNew)

	// 继承 singleton 拒绝（专用单例规则，不是 RES-101）。
	expectCode(t, `
singleton AppInfo { Int x = 1; }
class Sub : AppInfo { }
static Int main() { return 0 }`, TyInherit)

	// instance 只读。
	expectCode(t, `
singleton AppInfo { Int x = 1; }
static Int main() {
    AppInfo.instance = null
    return 0
}`, TySingletonRO)

	// factory 注册 + 同包 Target 私有构造器访问。
	expectNone(t, `
class Device {
    String name;
    private Device(String n) { name = n }
}
factory DeviceFactory for Device {
    static Device create(String n) { return new Device(n) }
}
static Int main() {
    Device d = DeviceFactory.create("cam")
    return 0
}`)

	// Target 未声明。
	expectCode(t, `
factory F for Missing {
    static Int make() { return 0 }
}
static Int main() { return 0 }`, TyFactory)

	// Target 泛型实参拒绝。
	expectCode(t, `
class Box<T> { T v; }
factory BoxFactory for Box<Int> {
    static Int make() { return 0 }
}
static Int main() { return 0 }`, TyFactory)

	// Target 非 class/struct 拒绝。
	expectCode(t, `
factory IntFactory for Int {
    static Int make() { return 0 }
}
static Int main() { return 0 }`, TyFactory)

	// factory 不是类型。
	expectCode(t, `
class Device { Int x = 0; }
factory DeviceFactory for Device {
    static Device create() { return new Device() }
}
static Int main() {
    DeviceFactory f
    return 0
}`, TyFactory)
}
