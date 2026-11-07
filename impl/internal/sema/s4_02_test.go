package sema

import "testing"

// S4-02：xdk.errors wrap/mapErr/report 与 Result 观测成员。
func TestS4XdkErrorsFunctions(t *testing.T) {
	expectNone(t, `import xdk.errors
static Int main() {
    Result<Int, String> r = Err("e")
    Result<Int, String> a = wrap(r, "f")
    Result<Int, Int> b = mapErr(r, (String e) -> 1)
    report(r)
    return 0
}`)

	expectCode(t, `import xdk.errors
static Int main() {
    Result<Int, String> r = Err("e")
    Result<Int, String> a = wrap(r, 1)
    return 0
}`, ErXdkErrors)

	expectCode(t, `import xdk.errors
static Int main() {
    Result<Int, String> r = Err("e")
    Result<Int, Int> b = mapErr(r, 1)
    return 0
}`, ErXdkErrors)

	expectCode(t, `import xdk.errors
static Int main() {
    report(1)
    return 0
}`, ErXdkErrors)
}

func TestS4ResultMembersContract(t *testing.T) {
	expectNone(t, `
static Int main() {
    Result<Int, String> r = Ok(1)
    Bool ok = r.isOk()
    Bool ne = r.isErr()
    Int v = r.value()
    String e = r.error()
    Int d = r.unwrapOr(0)
    return 0
}`)

	expectCode(t, `
static Int main() {
    Result<Int, String> r = Ok(1)
    Int v = r.unwrapOr("x")
    return 0
}`, ErResultMember)

	expectCode(t, `
static Int main() {
    Result<Int, String> r = Ok(1)
    Int v = r.value(1)
    return 0
}`, ErResultMember)
}
