package sema

import (
	"strings"
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

// S6-09d：HttpResponse 是 xdk.net 的句柄类型，net.http 子包必须再导出。
func TestS609dHttpResponseImport(t *testing.T) {
	// 包导入：xdk.net / xdk.net.http 都应绑定 HttpResponse。
	expectNone(t, `import xdk.net
import xdk.errors
static Int f(HttpResponse r) { return 0 }
static Int main() { return 0 }`)

	expectNone(t, `import xdk.net.http
import xdk.errors
static Int f(HttpResponse r) { return 0 }
static Int main() { return 0 }`)

	// 显式符号导入：主包与子包两种写法。
	expectNone(t, `import xdk.net.HttpResponse
import xdk.errors
static Int f(HttpResponse r) { return 0 }
static Int main() { return 0 }`)

	expectNone(t, `import xdk.net.http.HttpResponse
import xdk.errors
static Int f(HttpResponse r) { return 0 }
static Int main() { return 0 }`)

	// 未导入：必须给出 RES-105，并提示定义于 xdk.net / xdk.net.http。
	expectCode(t, `static Int main() { HttpResponse r; return 0 }`, ResXdkNotImport)

	expectNone(t, `import xdk.net.http
import xdk.tasks
import xdk.errors
@tasks
static Int main() {
    Context ctx = Context.background()
    Bytes body = Bytes.fromString("")
    Result<HttpResponse, ErrorKind> r = httpRequestAsync(ctx, "GET", "http://127.0.0.1", 80, "/", body)
    return 0
}`)
}

// 未导入提示必须给出正确的显式导入路径（xdk.net / xdk.net.http）。
func TestS609dHttpResponseHint(t *testing.T) {
	u, pdiags := xfront.ParseUnit("t.x", "static Int main() { HttpResponse r; return 0 }\n")
	if len(pdiags) != 0 {
		t.Fatalf("解析诊断：%v", pdiags)
	}
	for _, d := range Analyze("t.x", u) {
		if d.Code != ResXdkNotImport {
			continue
		}
		if !strings.Contains(d.Message, "xdk.net") {
			t.Fatalf("提示缺少 xdk.net：%s", d.Message)
		}
		return
	}
	t.Fatal("未触发 RES-105")
}
