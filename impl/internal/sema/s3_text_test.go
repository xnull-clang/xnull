package sema

import "testing"

// S3-04：Text/Bytes/StringBuilder 内建类型与方法签名。
func TestS3TextTypesMethods(t *testing.T) {
	expectNone(t, `import xdk.text
static Int main() {
    StringBuilder b = StringBuilder()
    b.append("x")
    b.append(1)
    String s = b.toString()
    Int n = b.length()

    Text t = Text.fromString("hello")
    Int tl = t.length()
    Int cp = t.codePointCount()
    String ts = t.toString()

    Bytes by = Bytes.fromString("abc")
    by.set(1, 90)
    Int v = by.get(0)
    by.push(1)
    by.append(by)
    Bytes sl = by.slice(0, 2)
    Int bl = by.length()
    return n + tl + cp + v + bl
}`)

	expectCode(t, `import xdk.text
static Int main() {
    Bytes b = Bytes.fromString("abc")
    b.set("x", 1)
    return 0
}`, TyAssignability)

	expectCode(t, `import xdk.text
static Int main() {
    Bytes b = Bytes.fromString("abc")
    String s = b.get(0)
    return 0
}`, TyAssignability)

	expectCode(t, `import xdk.text
static Int main() {
    Text t = Text.fromString("a")
    t.nope()
    return 0
}`, TyBadOperand)

	expectCode(t, `import xdk.text
static Int main() {
    StringBuilder b = StringBuilder(1)
    return 0
}`, TyAssignability)
}
