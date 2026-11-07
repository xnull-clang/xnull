package sema

import "testing"

// S7-01：FFI 调用点类型（Text/layout/数组/Float/Char/UInt/句柄 out/Bytes transfer）
// 与 layout(c) 尺寸校验。发射由 E4 接；本卡只做 sema 面。

func TestS701LayoutSize(t *testing.T) {
	if err := RegisterExternalLayout("Stat", []FFIField{
		{Name: "size", Type: "Int64"},
		{Name: "mode", Type: "Int32"},
	}, 16); err != nil {
		t.Fatalf("合法 layout 被拒：%v", err)
	}
	if n, ok := LayoutSize("Stat"); !ok || n != 16 {
		t.Fatalf("Stat size=%d ok=%v，期望 16", n, ok)
	}

	if err := RegisterExternalLayout("BadStat", []FFIField{
		{Name: "size", Type: "Int64"},
		{Name: "mode", Type: "Int32"},
	}, 12); err == nil {
		t.Fatal("尺寸不符的 layout 应被拒")
	}

	if err := RegisterExternalLayout("Pair", []FFIField{
		{Name: "stat", Type: "Stat"},
		{Name: "x", Type: "Int64"},
	}, 24); err != nil {
		t.Fatalf("嵌套 layout 被拒：%v", err)
	}

	if err := RegisterExternalLayout("BadPair", []FFIField{
		{Name: "stat", Type: "Stat"},
		{Name: "x", Type: "Int64"},
	}, 16); err == nil {
		t.Fatal("嵌套 layout 尺寸不符应被拒")
	}

	if err := RegisterExternalLayout("BadField", []FFIField{{Name: "s", Type: "String"}}, 8); err == nil {
		t.Fatal("非标量 layout 字段应被拒")
	}

	// Int64/Int32 是 S7 标量，必须能作为值结构体字段（§3.3）。
	expectNone(t, `struct Stat {
    Int64 size;
    Int32 mode;
}

static Int main() {
    Stat s = Stat()
    return 0
}`)
}

func TestS701FFICallTypes(t *testing.T) {
	if err := RegisterExternalLayout("Stat", []FFIField{
		{Name: "size", Type: "Int64"},
		{Name: "mode", Type: "Int32"},
	}, 16); err != nil {
		t.Fatal(err)
	}
	RegisterExternalTypes("File")
	if err := RegisterFFIEntries(
		FFIEntry{Name: "ffiText", Params: []FFIParam{{Name: "t", Type: "Text"}}, Ret: "Text"},
		FFIEntry{Name: "ffiLayout", Params: []FFIParam{{Name: "s", Type: "Stat"}}, Ret: "Int"},
		FFIEntry{Name: "ffiArr", Params: []FFIParam{{Name: "a", Type: "Int[]"}}, Ret: "Int"},
		FFIEntry{Name: "ffiFloat", Params: []FFIParam{{Name: "f", Type: "Float"}}, Ret: "Float"},
		FFIEntry{Name: "ffiChar", Params: []FFIParam{{Name: "c", Type: "Char"}}, Ret: "Char"},
		FFIEntry{Name: "ffiUInt", Params: []FFIParam{{Name: "u", Type: "UInt"}}, Ret: "UInt"},
		FFIEntry{Name: "ffiOpen", Params: []FFIParam{{Name: "p", Type: "String"}}, Ret: "File?"},
		FFIEntry{Name: "ffiFill", Params: []FFIParam{{Name: "b", Type: "Bytes", Lease: "transfer"}}, Ret: "Int"},
		FFIEntry{Name: "ffiReclaim", Params: []FFIParam{{Name: "b", Type: "Bytes", Lease: "reclaim"}}, Ret: "Int"},
		FFIEntry{Name: "ffiOut", Params: []FFIParam{{Name: "p", Type: "String"}, {Name: "h", Type: "File?", Out: true}}, Ret: "Int"},
	); err != nil {
		t.Fatal(err)
	}

	expectNone(t, `import xdk.sys

struct Stat {
    Int64 size;
    Int32 mode;
}

static Int main() {
    Text t = ffiText(Text.fromString("x"))
    Stat s = Stat()
    Int n = ffiLayout(s)
    Int m = ffiArr([1, 2])
    Float f = ffiFloat(1.5)
    Char c = ffiChar('a')
    UInt u = ffiUInt(1)
    File? h = ffiOpen("p")
    Bytes b = Bytes.fromString("x")
    Int x = ffiFill(b)
    Int y = ffiReclaim(b)
    File? g = null
    Int z = ffiOut("p", g)
    return n + m + x + y + z
}`)

	expectCode(t, `import xdk.sys
static Int main() { Text t = ffiText(1); return 0 }`, TyAssignability)
	expectCode(t, `static Int main() { Int n = ffiArr(["x"]); return 0 }`, TyAssignability)
	expectCode(t, `static Int main() { Float f = ffiFloat("x"); return 0 }`, TyAssignability)
	expectCode(t, `static Int main() { Char c = ffiChar(1); return 0 }`, TyAssignability)
	expectCode(t, `static Int main() { UInt u = ffiUInt("x"); return 0 }`, TyAssignability)
	expectCode(t, `import xdk.sys
static Int main() { File? h = ffiOpen(1); return 0 }`, TyAssignability)

	// Bytes transfer/reclaim 必须是变量（所有权明确，不能传临时值）。
	expectCode(t, `static Int main() { Int n = ffiFill(Bytes.fromString("x")); return 0 }`, TyBadOperand)
	expectCode(t, `static Int main() { Int n = ffiReclaim(Bytes.fromString("x")); return 0 }`, TyBadOperand)

	// out 句柄形参必须是变量。
	expectCode(t, `import xdk.sys
static Int main() { Int n = ffiOut("p", null); return 0 }`, TyBadOperand)
}
