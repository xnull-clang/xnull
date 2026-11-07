package interp

import (
	"strings"
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

func runSrcDiag(t *testing.T, src string) (string, string, int, error) {
	t.Helper()
	u, diags := xfront.ParseUnit("t.x", src)
	if len(diags) != 0 {
		t.Fatalf("解析诊断：%v", diags)
	}
	var out, diag strings.Builder
	code, err := RunWithDiag(u, &out, &diag, nil)
	return out.String(), diag.String(), code, err
}

const s4ErrPrelude = `
enum ErrorKind { InvalidArgument, Io, Internal }
protocol Error {
    ErrorKind kind();
    String describe();
}
class IoError implements Error {
    ErrorKind kind() { return ErrorKind.Io }
    String describe() { return "disk" }
}
`

func TestS4WrapMapErr(t *testing.T) {
	out, err := runSrc(t, `
static Int main() {
    Result<Int, String> ok = Ok(1)
    Result<Int, String> w1 = wrap(ok, "new")
    print(w1.isOk())
    print(w1.value())
    Result<Int, String> bad = Err("old")
    Result<Int, String> w2 = wrap(bad, "new")
    print(w2.isErr())
    print(w2.error())
    Result<Int, Int> m = mapErr(bad, (String s) -> s.length())
    print(m.isErr())
    print(m.error())
    Result<Int, String> ok2 = Ok(9)
    Result<Int, Int> m2 = mapErr(ok2, (String s) -> s.length())
    print(m2.value())
    return 0
}`)
	want := "true\n1\ntrue\nnew\ntrue\n3\n9\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}

func TestS4Report(t *testing.T) {
	out, diag, code, err := runSrcDiag(t, s4ErrPrelude+`
static Int main() {
    Result<Int, Error> ok = Ok(1)
    report(ok)
    Result<Int, Error> bad = Err(new IoError())
    report(bad)
    print(bad.isErr())
    print(bad.error().describe())
    return 0
}`)
	wantOut := "true\ndisk\n"
	wantDiag := "[Io] disk\n"
	if err != nil || code != 0 || out != wantOut || diag != wantDiag {
		t.Fatalf("out=%q wantOut=%q diag=%q wantDiag=%q code=%d err=%v", out, wantOut, diag, wantDiag, code, err)
	}
}

func TestS4ObservationMembers(t *testing.T) {
	out, err := runSrc(t, s4ErrPrelude+`
static Int main() {
    Result<Int, Error> ok = Ok(5)
    Result<Int, Error> bad = Err(new IoError())
    print(ok.isOk())
    print(ok.isErr())
    print(ok.value())
    print(ok.unwrapOr(0))
    print(bad.isErr())
    print(bad.unwrapOr(7))
    print(bad.error().kind())
    return 0
}`)
	want := "true\nfalse\n5\n5\ntrue\n7\nIo\n"
	if err != nil || out != want {
		t.Fatalf("out=%q want=%q err=%v", out, want, err)
	}
}

// S4 §2.2：xdk.errors 预置 ErrorKind/Error 无需源码声明即可执行 report。
func TestS4BuiltinXDKErrors(t *testing.T) {
	out, diag, code, err := runSrcDiag(t, `
class IoError implements Error {
    ErrorKind kind() { return ErrorKind.Io }
    String describe() { return "disk" }
}
static Int main() {
    Result<Int, Error> r = Err(new IoError())
    report(r)
    print(r.isErr())
    return 0
}`)
	if err != nil || code != 0 || out != "true\n" || diag != "[Io] disk\n" {
		t.Fatalf("out=%q diag=%q code=%d err=%v", out, diag, code, err)
	}
}
