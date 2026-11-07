package sema

// QA2 集成复核独立探针（B0-07a numeric + TUPLE）。仅存在于 /tmp 导出副本。

import "testing"

func TestQA2NumericVariantBoundaries(t *testing.T) {
	none := []string{
		"static Int main() { Int8 v = 127\n return 0 }",
		"static Int main() { Int8 v = -128\n return 0 }",
		"static Int main() { Int16 v = 32767\n return 0 }",
		"static Int main() { Int16 v = -32768\n return 0 }",
		"static Int main() { UInt8 v = 255\n return 0 }",
		"static Int main() { UInt32 v = 4294967295\n return 0 }",
		"static Int main() { Int64 v = 9223372036854775807\n return 0 }",
		"static Int main() { Int64 v = -9223372036854775808\n return 0 }",
	}
	for _, src := range none {
		expectNone(t, src)
	}
	bad := []string{
		"static Int main() { Int8 v = 128\n return 0 }",
		"static Int main() { Int8 v = -129\n return 0 }",
		"static Int main() { Int16 v = 32768\n return 0 }",
		"static Int main() { UInt8 v = 256\n return 0 }",
		"static Int main() { UInt8 v = -1\n return 0 }",
		"static Int main() { UInt32 v = 4294967296\n return 0 }",
	}
	for _, src := range bad {
		expectCode(t, src, TyAssignability)
	}
}

func TestQA2NumericVariantCompareBoundaries(t *testing.T) {
	ok := []string{
		"static Int main() { Int32 a = 0\n if (a > -2147483648) { return 1 }\n return 0 }",
		"static Int main() { Int32 a = 0\n if (a <= 2147483647) { return 1 }\n return 0 }",
		"static Int main() { Int64 a = 0\n if (a >= -9223372036854775808) { return 1 }\n return 0 }",
		"static Int main() { Int64 a = 0\n if (a != 9223372036854775807) { return 1 }\n return 0 }",
	}
	for _, src := range ok {
		expectNone(t, src)
	}
	bad := []string{
		"static Int main() { Int32 a = 0\n if (a > -2147483649) { return 1 }\n return 0 }",
		"static Int main() { Int32 a = 0\n if (a <= 2147483648) { return 1 }\n return 0 }",
		"static Int main() { Int64 a = 0\n if (a >= -9223372036854775809) { return 1 }\n return 0 }",
	}
	for _, src := range bad {
		expectCode(t, src, TyBadOperand)
	}
}

func TestQA2TupleIndependent(t *testing.T) {
	expectNone(t, `
static Int main() {
    ((Int, String), Bool) nested = ((1, "a"), true)
    ((Int, String), Bool) copy = nested
    (Int, String) inner = copy.0
    return inner.0
}`)
	expectCode(t, `
static Int main() {
    (Int, (Int, String)) p = (1, (2, "x"))
    (Int, (Int, Int)) q = p
    return 0
}`, TyAssignability)
	expectCode(t, `
static Int main() {
    (Int, Int) p = (1, 2)
    (Int, Int) q = (1, 3)
    Bool b = p < q
    return 0
}`, TyBadOperand)
	expectCode(t, `
static Int main() {
    (Int, Int) p = (1, 2)
    p.1 = "x"
    return 0
}`, TyAssignability)
}
