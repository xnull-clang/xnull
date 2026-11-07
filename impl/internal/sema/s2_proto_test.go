package sema

import (
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// PROTO-01 sema：实现检查/协议变量限制/协议引用。
func TestS2PROTO01(t *testing.T) {
	// 协议变量可 null、类可赋给已实现协议、协议可赋父协议。
	expectNone(t, `
protocol Base { void base(); }
protocol P : Base { void go(); }
class C implements P {
    void base() { }
    void go() { }
}
static Int use() {
    P p = null
    C c = new C()
    p = c
    Base b = p
    return 0
}
static Int main() { return 0 }`)

	// 实现缺父协议方法。
	expectCode(t, `
protocol Base { void base(); }
protocol P : Base { void go(); }
class C implements P { void go() { } }
static Int main() { return 0 }`, TyProtoImpl)

	// 协议变量只能调用协议方法。
	expectCode(t, `
protocol P { void go(); }
class C implements P {
    void go() { }
    void extra() { }
}
static Int use(P p) {
    p.extra()
    return 0
}
static Int main() { return 0 }`, TyProtoMember)

	// 协议字段强持有：类字段为协议类型时按 GC 判定。
	src := `
protocol P { void go(); }
class Holder { P p; }
static Int main() { return 0 }`
	u, ds := xfront.ParseUnit("p.x", src)
	if len(ds) != 0 {
		t.Fatalf("解析诊断：%v", ds)
	}
	res, sd := AnalyzeWith("p.x", u)
	if len(sd) != 0 {
		t.Fatalf("语义诊断：%v", sd)
	}
	for _, st := range res.Strategies(u) {
		if st.Decl == "Holder" {
			if st.Policy != "gc" || st.Rule != 5 {
				t.Fatalf("协议字段应触发 GC（rule 5），实际 %+v", st)
			}
			return
		}
	}
	t.Fatalf("未找到 Holder 策略")
}
