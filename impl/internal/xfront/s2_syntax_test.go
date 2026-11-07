package xfront

import "testing"

// ---------- S2 §9 singleton ----------

func TestS2Singleton(t *testing.T) {
	got := unit(t, `singleton AppInfo {
    final String name = "XNull"
    Int count() { return 1 }
}`)
	for _, want := range []string{
		"(singleton", "AppInfo",
		`(field final String name (string "XNull"))`,
		"(method Int count", "(return (int 1))",
	} {
		if !contains(got, want) {
			t.Errorf("singleton AST 缺少 %q：%s", want, got)
		}
	}
	// 头部参数列表由文法拒绝（仅 class 支持主构造器，§6.3）。
	unitFail(t, "singleton X(Int a) { }", synExpect)
}

// ---------- S2 §10 factory ----------

func TestS2Factory(t *testing.T) {
	got := unit(t, `class Device {
    Device() { }
}

factory DeviceFactory for Device {
    static Device create(final String name) {
        return new Device()
    }

    static Box<T> wrap<T>(final T value) {
        return new Box<T>(value)
    }
}`)
	for _, want := range []string{
		"(factory", "DeviceFactory", "(for Device)",
		"(method static Device create", "(param final String name)",
		"(method static Box<T> wrap <T>", "(param final T value)",
	} {
		if !contains(got, want) {
			t.Errorf("factory AST 缺少 %q：%s", want, got)
		}
	}
	// 工厂方法必须写 static（§10.1 文法 FactoryMember）。
	unitFail(t, "factory F for T {\n    Device create() { return new Device() }\n}", synExpect)
	// 工厂方法不能写 final/protected（§10.1「工厂方法必须写 static」、§10.2）。
	unitFail(t, "factory F for T {\n    static final Device create() { return new Device() }\n}", synExpect)
}

// ---------- S2 §11 extension ----------

func TestS2Extension(t *testing.T) {
	got := unit(t, `class Device { }
extension Device {
    String label() { return "d" }
}`)
	for _, want := range []string{"(extension Device", "(method String label", `(string "d")`} {
		if !contains(got, want) {
			t.Errorf("extension AST 缺少 %q：%s", want, got)
		}
	}
	// 扩展成员只能是方法，不能写可见性修饰符（§11.1、附录 A ExtensionMember）。
	unitFail(t, "extension T {\n    public Int f() { return 1 }\n}", synExpect)
}

// ---------- S2 §12 annotation ----------

func TestS2AnnotationDecl(t *testing.T) {
	got := unit(t, `@annotation Marker {
    final String name = ""
    final Int level = 0
}`)
	for _, want := range []string{
		"(annotation Marker",
		`(field final String name (string ""))`,
		"(field final Int level (int 0))",
	} {
		if !contains(got, want) {
			t.Errorf("annotation AST 缺少 %q：%s", want, got)
		}
	}
	// 注解字段必须是 final（§12.1）。
	unitFail(t, "@annotation A {\n    String x = \"\"\n}", synExpect)
	// 注解不能声明方法（§12.1）。
	unitFail(t, "@annotation A {\n    Int f() { return 1 }\n}", synExpect)
}

func TestS2AnnotationUse(t *testing.T) {
	got := unit(t, `@annotation Marker {
    final String name = ""
}

@Marker("x")
class Device {
    @Override
    String toString() { return "d" }

    @Marker("y")
    Int value = 1
}

enum Color {
    @Deprecated Red,
    Green
}`)
	for _, want := range []string{
		`(@Marker (string "x"))`, "Device",
		"(@Override)", "(method (@Override) String toString",
		`(@Marker (string "y"))`, `(field (@Marker (string "y")) Int value (int 1))`,
		"(enum Color", "(@Deprecated)", "Red", "Green",
	} {
		if !contains(got, want) {
			t.Errorf("注解使用 AST 缺少 %q：%s", want, got)
		}
	}
}

// contains 是 strings.Contains 的短别名，避免测试文件再引 strings。
func contains(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
