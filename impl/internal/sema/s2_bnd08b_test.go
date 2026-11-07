package sema

import "testing"

// BND-08 补口：跨包工厂访问/返回类型/self。
func TestS2BND08FactoryRules(t *testing.T) {
	// 跨包 factory 不得调用 Target 私有构造器。
	expectCode(t, `
import lib.device
class Device {
    private Device(String n) { }
}
factory F for Device {
    static Device create(String n) { return new Device(n) }
}
static Int main() { return 0 }`, TyFactoryAccess)

	// 跨包 factory 通过公开静态工厂创建：允许。
	expectNone(t, `
import lib.device
class Device {
    private Device(String n) { }
    public static Device make(String n) { return new Device(n) }
}
factory F for Device {
    static Device create(String n) { return Device.make(n) }
}
static Int main() { return 0 }`)

	// 返回类型必须能归到 Target。
	expectCode(t, `
class Device { Int x = 0; }
factory F for Device {
    static Int make() { return 0 }
}
static Int main() { return 0 }`, TyFactoryRet)

	// 工厂方法禁用 self。
	expectCode(t, `
class Device { Int x = 0; }
factory F for Device {
    static Device make() { return self.instance() }
}
static Int main() { return 0 }`, TyFactorySelf)
}
