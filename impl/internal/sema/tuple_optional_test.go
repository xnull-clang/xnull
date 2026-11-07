package sema

import "testing"

// TUPLE 剩余项：可空元组声明 `(T1,T2)?` 与 `?.N`。
func TestTupleOptionalDeclaration(t *testing.T) {
	expectNone(t, `
static Int main() {
    (Int, String)? p = null
    Int? x = p?.0
    String? y = p?.1
    return 0
}`)
}
