package interp

import "testing"

// S4 §8 / CLEAN-01：errdefer 补偿 LIFO、Ok 路径不补偿、原错误不被补偿覆盖、
// 部分完成状态在 errdefer 中回滚；try 逐层传播触发各层 errdefer。
func TestS4CLEAN01ErrdeferCompensation(t *testing.T) {
	out, err := runSrc(t, `
class Res {
    String name;
    Res(String n) { self.name = n }
    void close() { print("close:" + self.name) }
}
class State {
    Int n = 0;
    void inc() { self.n = self.n + 1 }
    void dec() { self.n = self.n - 1 }
}
static Result<Int, String> tx(State s) {
    s.inc()
    errdefer s.dec()
    s.inc()
    errdefer s.dec()
    return Err("fail")
}
static Result<Int, String> inner() {
    errdefer print("inner-e")
    return Err("x")
}
static Result<Int, String> outer() {
    errdefer print("outer-e")
    Int v = try inner()
    return Ok(v)
}
static Result<Int, String> work(Res a, Res b) {
    errdefer a.close()
    print("work")
    errdefer b.close()
    return Err("boom")
}
static Result<Int, String> ok(Res a) {
    errdefer a.close()
    return Ok(1)
}
static Int main() {
    Res a = new Res("a")
    Res b = new Res("b")
    Result<Int, String> r = work(a, b)
    if (r.isErr()) {
        print("err:" + r.error())
    }
    Result<Int, String> s = ok(a)
    print(s.unwrapOr(0))
    State st = new State()
    Result<Int, String> t = tx(st)
    print(st.n)
    print(t.error())
    Result<Int, String> o = outer()
    print(o.isErr())
    return 0
}`)
	want := "work\nclose:b\nclose:a\nerr:boom\n1\n0\nfail\ninner-e\nouter-e\ntrue\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}

// CLEAN-01 补充：补偿自身失败可观测，但不得覆盖原错误；错误路径 deinit 在 errdefer 之后。
func TestS4CLEAN01CompensationFailure(t *testing.T) {
	t.Run("ReportCompensationFailure", func(t *testing.T) {
		out, err := runSrc(t, `
class Comp {
    Result<Int, String> close() { return Err("comp-fail") }
}
class R {
    void deinit() { print("dR") }
}
static Result<Int, String> f(Comp c, R r) {
    errdefer {
        Result<Int, String> cr = c.close()
        if (cr.isErr()) { print("comp:" + cr.error()) }
    }
    return Err("orig")
}
static Int main() {
    Result<Int, String> r = f(new Comp(), new R())
    print("err:" + r.error())
    return 0
}`)
		want := "comp:comp-fail\ndR\nerr:orig\n"
		if err != nil || out != want {
			t.Fatalf("out=%q want=%q err=%v", out, want, err)
		}
	})
	t.Run("MultiStepRollback", func(t *testing.T) {
		out, err := runSrc(t, `
class S {
    Int n = 0;
    void inc() { self.n = self.n + 1 }
    void dec() { self.n = self.n - 1 }
}
static Result<Int, String> tx(S s, Int failAt) {
    Int i = 0
    while i < 3 {
        s.inc()
        errdefer s.dec()
        i = i + 1
    }
    if failAt > 0 { return Err("mid") }
    return Ok(1)
}
static Int main() {
    S s = new S()
    Result<Int, String> r = tx(s, 1)
    print(s.n)
    print(r.error())
    return 0
}`)
		// errdefer 绑定块作用域：while 体内注册的补偿随该次迭代正常结束失效（S1 §10.3），
		// 因此三步都已完成；函数级补偿回滚由主用例 tx 覆盖。
		want := "3\nmid\n"
		if err != nil || out != want {
			t.Fatalf("out=%q want=%q err=%v", out, want, err)
		}
	})
}
