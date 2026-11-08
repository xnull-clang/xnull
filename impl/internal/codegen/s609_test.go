package codegen

import (
	"bytes"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// S6-09：net.xfb + Async 内建（socket/http）端到端。
func s609Project(t *testing.T, src string) (string, string) {
	t.Helper()
	root := t.TempDir()
	writeFFIFile(t, filepath.Join(root, "main.x"), src)
	xfb, err := os.ReadFile(filepath.Join("..", "..", "..", "bindings", "xdk", "net.xfb"))
	if err != nil {
		t.Skipf("net.xfb 不可用：%v", err)
	}
	writeFFIFile(t, filepath.Join(root, "bindings", "xdk", "net.xfb"), string(xfb))
	bin := filepath.Join(t.TempDir(), "prog")
	var stderr bytes.Buffer
	code := BuildWithOptions(filepath.Join(root, "main.x"), bin,
		filepath.Join("..", "..", "runtime"), Options{}, &stderr)
	if code != 0 {
		t.Fatalf("构建失败 code=%d\n%s", code, stderr.String())
	}
	csrc, err := os.ReadFile(bin + ".c")
	if err != nil {
		t.Fatalf("读取生成 C：%v", err)
	}
	return bin, string(csrc)
}

func s609Run(t *testing.T, bin string) string {
	t.Helper()
	out, err := exec.Command(bin).CombinedOutput()
	if err != nil {
		t.Fatalf("运行失败：%v\n%s", err, out)
	}
	return strings.TrimSpace(string(out))
}

func TestS609SocketPlainAndAsyncClose(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Skipf("无法监听回环：%v", err)
	}
	defer ln.Close()
	go func() {
		c, err := ln.Accept()
		if err == nil {
			c.Close()
		}
	}()
	port := ln.Addr().(*net.TCPAddr).Port
	src := fmt.Sprintf(`import xdk.errors
import xdk.tasks

@tasks
static Int main() {
    Context ctx = Context.background()
    var r = socketConnectAsync(ctx, "127.0.0.1", %d)
    print(r.isOk())
    if (r.isOk()) {
        var s = r.value()
        print(socketClose(s))
    }
    return 0
}
`, port)
	bin, csrc := s609Project(t, src)
	for _, want := range []string{
		"xn_Result_Socket_ErrorKind", "xdkc_socket_connect_async(",
		"xn_ffi_socketClose(",
	} {
		if !strings.Contains(csrc, want) {
			t.Fatalf("生成 C 缺少 %q", want)
		}
	}
	if got := s609Run(t, bin); got != "true\ntrue" {
		t.Fatalf("stdout=%q，期望 true/true", got)
	}
}

func TestS609HTTPGetAsync(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Skipf("无法监听回环：%v", err)
	}
	defer ln.Close()
	go func() {
		c, err := ln.Accept()
		if err != nil {
			return
		}
		defer c.Close()
		buf := make([]byte, 4096)
		_, _ = c.Read(buf)
		io.WriteString(c, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhello")
	}()
	addr := ln.Addr().(*net.TCPAddr)
	host, port := addr.IP.String(), addr.Port
	src := fmt.Sprintf(`import xdk.net.http
import xdk.errors
import xdk.tasks

@tasks
static Int main() {
    Context ctx = Context.background()
    Bytes empty = Bytes.fromString("")
    Result<HttpResponse, ErrorKind> r = httpRequestAsync(ctx, "GET", "%s", %d, "/", empty)
    print(r.isOk())
    if (r.isOk()) {
        HttpResponse resp = r.value()
        print(str(httpStatus(resp)))
        print(httpBodyText(resp))
        print(httpResponseClose(resp))
    }
    return 0
}
`, host, port)
	bin, csrc := s609Project(t, src)
	for _, want := range []string{
		"xn_Result_HttpResponse_ErrorKind", "xdkc_http_request_async(", "xn_ffi_httpStatus(",
	} {
		if !strings.Contains(csrc, want) {
			t.Fatalf("生成 C 缺少 %q", want)
		}
	}
	if got := s609Run(t, bin); got != "true\n200\nhello\ntrue" {
		t.Fatalf("stdout=%q，期望 true/200/hello/true", got)
	}
}

// XDK-09d：Result<HttpResponse, Error> 成员类型/解包。
func TestS609HttpResponseResultMember(t *testing.T) {
	dir := t.TempDir()
	writeFFIFile(t, filepath.Join(dir, "main.x"), `import xdk.net.http
import xdk.errors

static Int main() {
    Bytes body = Bytes.fromString("")
    Result<HttpResponse, ErrorKind> r = httpRequest("GET", "127.0.0.1", 1, "/", body)
    return 0
}
`)
	xfb, err := os.ReadFile(filepath.Join("..", "..", "..", "bindings", "xdk", "net.xfb"))
	if err != nil {
		t.Skipf("net.xfb 不可用：%v", err)
	}
	writeFFIFile(t, filepath.Join(dir, "bindings", "xdk", "net.xfb"), string(xfb))
	var stderr bytes.Buffer
	bin := filepath.Join(t.TempDir(), "prog")
	code := BuildWithOptions(filepath.Join(dir, "main.x"), bin,
		filepath.Join("..", "..", "runtime"), Options{}, &stderr)
	if code != 0 {
		t.Fatalf("构建失败 code=%d\n%s", code, stderr.String())
	}
	csrc, err := os.ReadFile(bin + ".c")
	if err != nil {
		t.Fatalf("读取生成 C：%v", err)
	}
	if !strings.Contains(string(csrc), "xn_Result_HttpResponse_ErrorKind") {
		t.Fatalf("缺少 Result<HttpResponse, ErrorKind> 实例：\n%s", csrc)
	}
}
