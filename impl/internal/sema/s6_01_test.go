package sema

import "testing"

// S6-01：XDK 8 包内建签名；check 路径不依赖 .xfb 注入。
// XDK-02 第 1 条：可失败操作返回 Result；第 3 条：默认异步/可阻塞 API 首参 Context。

func TestS601RuntimeSignatures(t *testing.T) {
	expectNone(t, `import xdk.runtime
static Int main() {
    diagnose("x")
    Int a = nowMono()
    Int b = nowWall()
    String? e = env("HOME")
    return a + b
}`)

	// 错误实参必须在 check 路径被拒。
	expectCode(t, `import xdk.runtime
static Int main() { diagnose(1); return 0 }`, TyAssignability)

	expectCode(t, `import xdk.runtime
static Int main() { Int t = nowMono(1); return 0 }`, TyAssignability)

	expectCode(t, `import xdk.runtime
static Int main() { Int e = env("HOME"); return 0 }`, TyAssignability)
}

func TestS601SysSignatures(t *testing.T) {
	expectNone(t, `import xdk.sys
static Int main() {
    File f = fileOpenRead("a")
    File w = fileOpenWrite("b")
    Bool c = fileClose(f)
    Dir d = dirOpen(".")
    String name = dirRead(d)
    Bool dc = dirClose(d)
    Bool p = pathExists("a")
    Int u = utf8Valid("a")
    String t = readFileText("a")
    Int wr = writeFileText("a", t)
    return u + wr
}`)

	expectCode(t, `import xdk.sys
static Int main() { File f = fileOpenRead(1); return 0 }`, TyAssignability)

	expectCode(t, `import xdk.sys
static Int main() { Bool b = fileClose("x"); return 0 }`, TyAssignability)

	expectCode(t, `import xdk.sys
static Int main() { Bool b = pathExists(1); return 0 }`, TyAssignability)

	expectCode(t, `import xdk.sys
static Int main() { Int n = writeFileText(1, "x"); return 0 }`, TyAssignability)
}

// XDK-02 第 1 条：可失败操作返回 Result<T,E>，不能用裸值接收。
func TestS601XDK02Clause1Result(t *testing.T) {
	expectNone(t, `import xdk.sys
import xdk.tasks
import xdk.errors
@tasks
static Int main() {
    Context c = Context.background()
    Result<Bytes, Error> a = readResource(c, "a")
    Result<Text, Error> b = readResourceText(c, "a")
    Result<List<String>, Error> l = listResources(c, "")
    return 0
}`)

	expectNone(t, `import xdk.text
import xdk.errors
static Int main() {
    Result<Int, Error> i = parseInt("42")
    Result<Double, Error> d = parseFloat("1.5")
    return 0
}`)

	expectCode(t, `import xdk.sys
import xdk.tasks
import xdk.errors
@tasks
static Int main() {
    Context c = Context.background()
    Bytes b = readResource(c, "a")
    return 0
}`, TyAssignability)

	expectCode(t, `import xdk.text
import xdk.errors
static Int main() { Int i = parseInt("42"); return 0 }`, TyAssignability)
}

// XDK-02 第 3 条：默认异步/可阻塞 API 首参必须是 Context。
func TestS601XDK02Clause3ContextFirst(t *testing.T) {
	for name, sig := range xdkFuncSigs {
		if !sig.blocking {
			continue
		}
		if len(sig.params) == 0 || sig.params[0] != "Context" {
			t.Errorf("XDK API %s 标记为可阻塞，但首参不是 Context：%v", name, sig.params)
		}
	}

	expectNone(t, `import xdk.sys
import xdk.tasks
import xdk.errors
@tasks
static Int main() {
    Context c = Context.background()
    Result<Bytes, Error> r = readResource(c, "a")
    return 0
}`)

	expectCode(t, `import xdk.sys
import xdk.tasks
import xdk.errors
@tasks
static Int main() {
    Context c = Context.background()
    Result<Bytes, Error> r = readResource("a")
    return 0
}`, TyAssignability)
}

// 未支持入口必须显式诊断，不能静默放行。
func TestS601UnsupportedExplicit(t *testing.T) {
	expectCode(t, `import xdk.collections
static Int main() { sort(1); return 0 }`, TyXdkUnsupported)

	expectCode(t, `import xdk.collections
static Int f(RingBuffer<Int> r) { r.push(1); return 0 }`, TyXdkUnsupported)

	expectCode(t, `import xdk.text
static Int main() { Regex.find("x"); return 0 }`, TyXdkUnsupported)

	expectCode(t, `import xdk.net
static Int f(Socket s) { s.nope(); return 0 }`, TyXdkUnsupported)
}

// 8 个包都必须有内建类型或函数签名面（不允许只登记包名）。
func TestS601PackageSignatureCoverage(t *testing.T) {
	for pkg, syms := range xdkPackages {
		ok := xdkSpecialSigned[pkg]
		for s := range syms {
			if xdkTypeNames[s] {
				ok = true
			}
			if _, isSig := xdkFuncSigs[s]; isSig {
				ok = true
			}
		}
		if !ok {
			t.Errorf("XDK 包 %s 没有内建类型/函数签名面", pkg)
		}
	}
}
