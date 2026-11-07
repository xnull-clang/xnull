package sema

import "testing"

// BND-06 补口：数据枚举项不可变/不可 new。
func TestS2EnumImmutable(t *testing.T) {
	base := `
enum Status {
    Ready(0);
    final Int code;
    Status(Int c) { self.code = c }
}
`
	// 外部写字段拒绝。
	expectCode(t, base+`
static Int main() {
    Status.Ready.code = 9
    return 0
}`, TyEnumImmutable)

	// 数据枚举方法内写字段拒绝（构造器初始化仍允许）。
	expectCode(t, `
enum Status {
    Ready(0);
    final Int code;
    Status(Int c) { self.code = c }
    void touch() { self.code = 1 }
}
static Int main() { return 0 }`, TyEnumImmutable)

	// new 数据枚举项拒绝。
	expectCode(t, base+`
static Int main() {
    Status s = new Status.Ready()
    return 0
}`, TyEnumImmutable)

	// 读取字段允许。
	expectNone(t, base+`
static Int main() {
    Int c = Status.Ready.code
    return c
}`)
}
