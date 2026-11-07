package sema

import "testing"

// S4 OBS-01：mapErr 顶层转换函数实参。
func TestS4MapErrTopLevelFunc(t *testing.T) {
	expectNone(t, `import xdk.errors
static String conv(String e) { return e }
static Int main() {
    Result<Int, String> r = Err("e")
    Result<Int, String> q = mapErr(r, conv)
    return 0
}`)

	expectCode(t, `import xdk.errors
static Int conv(Int e) { return e }
static Int main() {
    Result<Int, String> r = Err("e")
    Result<Int, Int> q = mapErr(r, conv)
    return 0
}`, ErXdkErrors)
}
