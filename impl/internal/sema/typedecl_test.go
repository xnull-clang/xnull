package sema

import (
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// ---------- M2.5.1：类型声明语义检查（S2） ----------

func TestTypeDeclOK(t *testing.T) {
	// 类：字段/方法/构造器/deinit/单继承/多协议（§2）
	expectNone(t, `
protocol Ready {
    Bool ready();
}

protocol Secure : Ready {
    Bool secure();
}

class Device : Base implements Ready, Secure {
    String name = "device";

    Device(String name) {
        self.name = name;
    }

    Bool ready() {
        return true;
    }

    Bool secure() {
        return true;
    }

    void rename(final String next) {
        self.name = next;
    }

    void deinit() {
        self.name = "";
    }
}

class Base {
    Int id = 0;
}

static Int main() { return 0 }`)
	// 结构体：值字段 + 方法（§3）
	expectNone(t, `
enum Color { Red, Green, Blue }

struct Point {
    Int x = 0;
    Int y = 0;
    Color c = Color.Red;
    (Int, Int) pair = (1, 2);

    Int sum() {
        return self.x + self.y;
    }
}

static Int main() { return 0 }`)
	// 协议：签名 + 多继承（§4）
	expectNone(t, `
protocol A {
    void go();
}

protocol B : A {
    Int size();
}

static Int main() { return 0 }`)
	// 枚举：简单 + 数据（§8）
	expectNone(t, `
enum Color { Red, Green, Blue }
enum Code { A = 1, B = 2, C = 4 }

enum Status {
    Ready(0, "ready"),
    Failed(1, "failed");

    final Int code;
    final String label;

    Status(Int code, String label) {
        self.code = code;
        self.label = label;
    }
}

static Int main() { return 0 }`)
	// 私有字段两种声明写法映射同一字段；类内裸 _name（§7.4）
	expectNone(t, `
class Worker(final Int id) {
    Int _retries = 0;
    private Int attempts = 0;

    Int retries() {
        return _retries + _attempts;
    }
}

static Int main() { return 0 }`)
}

// FIELD-01：私有字段规范名（§7.4）
func TestPrivateFieldRules(t *testing.T) {
	// private 与 _ 前缀同时使用
	expectCode(t, "class W {\n    private Int _name;\n}\n\nstatic Int main() { return 0 }", TyPrivField)
	// public/protected 与 _name 同时出现
	expectCode(t, "class W {\n    public Int _name;\n}\n\nstatic Int main() { return 0 }", TyPrivField)
	// `_`、`__x`、`_1` 非法
	expectCode(t, "class W {\n    Int _;\n}\n\nstatic Int main() { return 0 }", TyPrivField)
	expectCode(t, "class W {\n    Int __x;\n}\n\nstatic Int main() { return 0 }", TyPrivField)
	expectCode(t, "class W {\n    Int _1;\n}\n\nstatic Int main() { return 0 }", TyPrivField)
	// 类内裸 name（private name 的声明名）被拒绝；裸 _name 合法
	expectCode(t, `
class W {
    private Int name = 0;

    Int get() {
        return name;
    }
}

static Int main() { return 0 }`, TyPrivField)
	// self._name 被拒绝
	expectCode(t, `
class W {
    Int _name = 0;

    Int get() {
        return self._name;
    }
}

static Int main() { return 0 }`, TyPrivField)
	// self.name（私有字段声明名）被拒绝
	expectCode(t, `
class W {
    private Int name = 0;

    Int get() {
        return self.name;
    }
}

static Int main() { return 0 }`, TyPrivField)
	// 局部变量/参数使用 _name 被拒绝
	expectCode(t, `
class W {
    Int _name = 0;

    Int get() {
        Int _name = 1;
        return _name;
    }
}

static Int main() { return 0 }`, TyPrivField)
	// 外部访问 name / _name 都拒绝
	expectCode(t, `
class W {
    Int _name = 0;
}

static Int main() {
    W w = new W();
    print(w._name)
    return 0
}`, TyPrivField)
	expectCode(t, `
class W {
    private Int name = 0;
}

static Int main() {
    W w = new W();
    print(w.name)
    return 0
}`, TyPrivField)
}

// INH-01：继承与协议实现（§2.5/§4.1）
func TestInheritanceRules(t *testing.T) {
	// 继承环
	expectCode(t, `
class A : B {
}

class B : A {
}

static Int main() { return 0 }`, TyInherit)
	// 协议继承环
	expectCode(t, `
protocol P : Q {
}

protocol Q : P {
}

static Int main() { return 0 }`, TyInherit)
	// final 父类
	expectCode(t, `
final class Base {
}

class Sub : Base {
}

static Int main() { return 0 }`, TyInherit)
	// 父类种类错误（struct 作父类）
	expectCode(t, `
struct S {
}

class C : S {
}

static Int main() { return 0 }`, TyInherit)
	// 子类同签名方法被拒绝（含祖先 private 方法）
	expectCode(t, `
class Base {
    void run(Int n) {
        print(n)
    }
}

class Sub : Base {
    void run(Int n) {
        print(n)
    }
}

static Int main() { return 0 }`, TyOverride)
	// 字段隐藏被拒绝
	expectCode(t, `
class Base {
    Int id = 0;
}

class Sub : Base {
    Int id = 1;
}

static Int main() { return 0 }`, TyOverride)
	// 重载（不同参数列表）合法
	expectNone(t, `
class Base {
    void run(Int n) {
        print(n)
    }
}

class Sub : Base {
    void run(String s) {
        print(s)
    }
}

static Int main() { return 0 }`)
	// implements 目标必须是 protocol
	expectCode(t, `
class C {
}

class D implements C {
}

static Int main() { return 0 }`, TyInherit)
}

// STRUCT-01：结构体值规则（§3.1/§3.2/§1.5）
func TestStructValueRules(t *testing.T) {
	// 引用字段被拒绝
	expectCode(t, "struct S {\n    String name;\n}\n\nstatic Int main() { return 0 }", TyStructVal)
	// 可空引用字段被拒绝
	expectCode(t, "struct S {\n    String? name;\n}\n\nstatic Int main() { return 0 }", TyStructVal)
	// 容器字段被拒绝
	expectCode(t, "struct S {\n    List<Int> xs;\n}\n\nstatic Int main() { return 0 }", TyStructVal)
	// 数组字段被拒绝
	expectCode(t, "struct S {\n    Int[] xs;\n}\n\nstatic Int main() { return 0 }", TyStructVal)
	// Result 字段被拒绝
	expectCode(t, "struct S {\n    Result<Int, String> r;\n}\n\nstatic Int main() { return 0 }", TyStructVal)
	// deinit 被拒绝
	expectCode(t, `
struct S {
    void deinit() {
    }
}

static Int main() { return 0 }`, TyStructVal)
	// 递归值包含被拒绝（直接 / 可空）
	expectCode(t, "struct S {\n    S value;\n}\n\nstatic Int main() { return 0 }", TyStructVal)
	expectCode(t, "struct S {\n    S? value;\n}\n\nstatic Int main() { return 0 }", TyStructVal)
	// 结构体继承被解析拒绝
	_, pdiags := xfront.ParseUnit("t.xn", "struct S : T {\n}\n\nstatic Int main() { return 0 }")
	if len(pdiags) == 0 {
		t.Fatalf("struct 继承应被拒绝")
	}
	// 嵌套值结构体合法
	expectNone(t, `
struct Inner {
    Int v = 0;
}

struct Outer {
    Inner inner;
    Int? opt;
    (Inner, Int) pair;
}

static Int main() { return 0 }`)
}

// PROTO-01：协议形式（§4）
func TestProtocolRules(t *testing.T) {
	// 字段被拒绝（解析层）
	_, pdiags := xfront.ParseUnit("t.xn", "protocol P {\n    Int count;\n}\n\nstatic Int main() { return 0 }")
	if len(pdiags) == 0 {
		t.Fatalf("协议字段应被拒绝")
	}
	// 方法体被拒绝（解析层）
	_, pdiags = xfront.ParseUnit("t.xn", "protocol P {\n    void go() {\n    }\n}\n\nstatic Int main() { return 0 }")
	if len(pdiags) == 0 {
		t.Fatalf("协议方法体应被拒绝")
	}
	// 泛型协议被拒绝（解析层：协议没有类型参数表）
	_, pdiags = xfront.ParseUnit("t.xn", "protocol P<T> {\n    void go();\n}\n\nstatic Int main() { return 0 }")
	if len(pdiags) == 0 {
		t.Fatalf("泛型协议应被拒绝")
	}
	// private/static 签名被拒绝
	expectCode(t, "protocol P {\n    private void go();\n}\n\nstatic Int main() { return 0 }", TyProtoForm)
	expectCode(t, "protocol P {\n    static void go();\n}\n\nstatic Int main() { return 0 }", TyProtoForm)
}

// ENUM-01：枚举规则（§8）
func TestEnumRules(t *testing.T) {
	// 项重复
	expectCode(t, "enum C { Red, Red }\n\nstatic Int main() { return 0 }", TyEnumRule)
	// 底层值重复
	expectCode(t, "enum C { A = 1, B = 1 }\n\nstatic Int main() { return 0 }", TyEnumRule)
	// 混合形式
	expectCode(t, "enum C { A, B(1) }\n\nstatic Int main() { return 0 }", TyEnumRule)
	// 数据枚举字段非 final
	expectCode(t, `
enum S {
    Ready(0);

    Int code;

    S(Int code) {
        self.code = code;
    }
}

static Int main() { return 0 }`, TyEnumRule)
	// 项参数数量不匹配
	expectCode(t, `
enum S {
    Ready(0, 1);

    final Int code;

    S(Int code) {
        self.code = code;
    }
}

static Int main() { return 0 }`, TyEnumRule)
	// 无构造器的数据枚举
	expectCode(t, `
enum S {
    Ready(0);

    final Int code;
}

static Int main() { return 0 }`, TyEnumRule)
	// 简单枚举带方法
	expectCode(t, `
enum C {
    Red;

    Int x() {
        return 1;
    }
}

static Int main() { return 0 }`, TyEnumRule)
	// 隐式递增值合法
	expectNone(t, "enum C { A, B = 5, C }\n\nstatic Int main() { return 0 }")
}

// §1.1：类型名唯一性与预定义冲突
func TestTypeNameRules(t *testing.T) {
	expectCode(t, "class Int {\n}\n\nstatic Int main() { return 0 }", ResRedecl)
	expectCode(t, "class A {\n}\n\nstruct A {\n}\n\nstatic Int main() { return 0 }", ResRedecl)
	// 修饰符组合
	expectCode(t, "abstract final class A {\n}\n\nstatic Int main() { return 0 }", TyModifier)
	expectCode(t, "abstract struct S {\n}\n\nstatic Int main() { return 0 }", TyModifier)
	expectCode(t, "abstract enum E { A }\n\nstatic Int main() { return 0 }", TyModifier)
}
