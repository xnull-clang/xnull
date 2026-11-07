package sema

import "testing"

// S6-05：xdk.text 语言面——Format builder / parse / UTF-8↔UTF-16 / Regex 动态编译。
// 运行时由 E4/E5 接；本卡只做 sema 类型与签名。

func TestS605TextPositive(t *testing.T) {
	expectNone(t, `import xdk.text
import xdk.errors
static Int main() {
    Result<Int, Error> a = parseInt("42")
    Result<Double, Error> b = parseFloat("1.5")

    String s = Format.int(7).width(4).pad('0').build()
    String f = Format.float(1.5).width(8).build()
    String t = Format.string("x").build()
    String u = Format.bool(true).build()

    Result<Regex, Error> re = Regex.compile("a+")
    Bool m = re.value().isMatch("aaa")

    Result<List<UInt16>, Error> u16 = utf8ToUtf16(Bytes.fromString("a"))
    Result<Bytes, Error> u8 = utf16ToUtf8(u16.value())
    Double d = b.value()
    return a.value() + s.length() + f.length() + t.length() + u.length()
}`)
}

func TestS605TextNegative(t *testing.T) {
	// 解析函数实参与返回类型。
	expectCode(t, `import xdk.text
import xdk.errors
static Int main() { Result<Int, Error> a = parseInt(1); return 0 }`, TyAssignability)

	expectCode(t, `import xdk.text
import xdk.errors
static Int main() { Int a = parseInt("42"); return 0 }`, TyAssignability)

	// Format builder：起始/链式/收尾签名。
	expectCode(t, `import xdk.text
static Int main() { Format f = Format.int("x"); return 0 }`, TyAssignability)

	expectCode(t, `import xdk.text
static Int main() { Format f = Format.int(1).width("x"); return 0 }`, TyAssignability)

	expectCode(t, `import xdk.text
static Int main() { Format f = Format.int(1).pad("x"); return 0 }`, TyAssignability)

	expectCode(t, `import xdk.text
static Int main() { String s = Format.int(1).build(1); return 0 }`, TyAssignability)

	// Regex 动态编译必须返回 Result；编译失败是可恢复错误。
	expectCode(t, `import xdk.text
import xdk.errors
static Int main() { Result<Regex, Error> r = Regex.compile(1); return 0 }`, TyAssignability)

	expectCode(t, `import xdk.text
import xdk.errors
static Int main() { Int r = Regex.compile("a"); return 0 }`, TyAssignability)

	// UTF-8↔UTF-16。
	expectCode(t, `import xdk.text
import xdk.errors
static Int main() { Result<List<UInt16>, Error> r = utf8ToUtf16("x"); return 0 }`, TyAssignability)

	expectCode(t, `import xdk.text
import xdk.errors
static Int main() { Result<Bytes, Error> r = utf16ToUtf8("x"); return 0 }`, TyAssignability)
}

// 未登记成员仍显式诊断（不静默放行）。
func TestS605TextUnsupportedMember(t *testing.T) {
	expectCode(t, `import xdk.text
static Int main() { Format.int(1).precision(2); return 0 }`, TyXdkUnsupported)

	expectCode(t, `import xdk.text
static Int main() { Regex.find("a"); return 0 }`, TyXdkUnsupported)
}
