package interp

import "testing"

// S5-05：解释器侧 xdk.tasks 基础面（TaskGroup.create/spawn/join/close + Context）。
func TestS5TasksBasic(t *testing.T) {
	t.Run("SpawnJoinClose", func(t *testing.T) {
		out, err := runSrc(t, `
@tasks
static Int run() {
    Context ctx = Context.background()
    TaskGroup g = TaskGroup.create(ctx)
    Task<Int> t = g.spawn(() -> { return Ok(7) })
    Result<Int, String> r = t.join()
    Result<void, String> c = g.close()
    print(r.value())
    print(c.isOk())
    return 0
}
static Int main() { print(run()); return 0 }`)
		want := "7\ntrue\n0\n"
		if err != nil || out != want {
			t.Fatalf("out=%q want=%q err=%v", out, want, err)
		}
	})
	t.Run("BusinessErrorPassthrough", func(t *testing.T) {
		out, err := runSrc(t, `
static Int main() {
    Context ctx = Context.background()
    TaskGroup g = TaskGroup.create(ctx)
    Task<Int> t = g.spawn(() -> { return Err("bad") })
    Result<Int, String> r = t.join()
    print(r.isErr())
    print(r.error())
    Result<void, String> c = g.close()
    print(c.isErr())
    print(c.error())
    return 0
}`)
		want := "true\nbad\ntrue\nbad\n"
		if err != nil || out != want {
			t.Fatalf("out=%q want=%q err=%v", out, want, err)
		}
	})
	t.Run("ContextCancel", func(t *testing.T) {
		out, err := runSrc(t, `
static Int main() {
    Context ctx = Context.background()
    Result<void, String> ok = ctx.checkCancel()
    print(ok.isOk())
    ctx.cancel()
    Result<void, String> bad = ctx.checkCancel()
    print(bad.isErr())
    return 0
}`)
		want := "true\ntrue\n"
		if err != nil || out != want {
			t.Fatalf("out=%q want=%q err=%v", out, want, err)
		}
	})
}
