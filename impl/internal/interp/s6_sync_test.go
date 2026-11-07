package interp

import "testing"

// S6-XDK05：解释器侧 Mutex/Channel/Atomic 基础语义。
func TestS6SyncPrimitives(t *testing.T) {
	t.Run("Channel", func(t *testing.T) {
		out, err := runSrc(t, `
static Int main() {
    Channel<Int> ch = Channel<Int>(2)
    print(ch.send(1).isOk())
    print(ch.send(2).isOk())
    print(ch.send(3).isErr())
    print(ch.receive().value())
    print(ch.receive().value())
    print(ch.receive().isErr())
    ch.close()
    print(ch.send(4).isErr())
    return 0
}`)
		want := "true\ntrue\ntrue\n1\n2\ntrue\ntrue\n"
		if err != nil || out != want {
			t.Fatalf("out=%q want=%q err=%v", out, want, err)
		}
	})
	t.Run("AtomicIntAndBool", func(t *testing.T) {
		out, err := runSrc(t, `
static Int main() {
    AtomicInt a = AtomicInt(0)
    print(a.load())
    a.store(5)
    print(a.compareExchange(5, 7))
    print(a.load())
    print(a.compareExchange(0, 9))
    AtomicBool b = AtomicBool(false)
    print(b.load())
    b.store(true)
    print(b.compareExchange(true, false))
    print(b.load())
    return 0
}`)
		want := "0\ntrue\n7\nfalse\nfalse\ntrue\nfalse\n"
		if err != nil || out != want {
			t.Fatalf("out=%q want=%q err=%v", out, want, err)
		}
	})
	t.Run("AtomicRefAndMutex", func(t *testing.T) {
		out, err := runSrc(t, `
class C { Int v = 1; }
static Int main() {
    C x = new C()
    AtomicRef<C> a = AtomicRef<C>(null)
    print(a.load() == null)
    a.store(x)
    print(a.load().v)
    print(a.compareExchange(x, x))
    Mutex<Int> m = Mutex<Int>(3)
    Result<Int, String> r = m.withLock((Int n) -> Ok(n + 1))
    print(r.unwrapOr(0))
    return 0
}`)
		want := "true\n1\ntrue\n4\n"
		if err != nil || out != want {
			t.Fatalf("out=%q want=%q err=%v", out, want, err)
		}
	})
}
