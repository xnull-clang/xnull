package ffi

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// S6-09：net.xfb（socket plain + HTTP）合同面。
func loadNetXfb(t *testing.T) *Registry {
	t.Helper()
	path, err := filepath.Abs(filepath.Join("..", "..", "..", "..", "bindings", "xdk", "net.xfb"))
	if err != nil {
		t.Fatal(err)
	}
	src, err := os.ReadFile(path)
	if err != nil {
		t.Skipf("net.xfb 不可用：%v", err)
	}
	root := t.TempDir()
	writeXfb(t, root, "bindings/xdk/net.xfb", string(src))
	reg, diags, err := Load(root)
	if err != nil || len(diags) != 0 {
		t.Fatalf("Load: err=%v diags=%v", err, diags)
	}
	return reg
}

func TestS609NetXfbContracts(t *testing.T) {
	reg := loadNetXfb(t)
	for _, h := range []string{"Socket", "Listener"} {
		if _, ok := findHandle(reg, h); !ok {
			t.Fatalf("缺少句柄 %s", h)
		}
	}
	for _, e := range []string{
		"socketConnect", "socketListen", "socketAccept", "socketRead",
		"socketWrite", "socketClose", "listenerClose", "httpGetPlain", "httpPostPlain",
	} {
		if _, ok := reg.Entry(e); !ok {
			t.Fatalf("缺少入口 %s", e)
		}
	}
	// plain socket 必须声明 .unaware（长阻塞分类清单）。
	if e, _ := reg.Entry("socketConnect"); e.Blocking != BlockingUnaware {
		t.Fatalf("socketConnect 应为 .unaware，得到 %v", e.Blocking)
	}
	// close 以 Bool 暴露（幂等关闭兼容面）。
	if e, _ := reg.Entry("socketClose"); !e.ErrorCodeRet || e.CloseOf == "" {
		t.Fatalf("socketClose 合同不符：%+v", e)
	}
	sup := reg.EmitSupport()
	if len(sup.Problems) != 0 {
		t.Fatalf("支撑代码失败：%v", sup.Problems)
	}
	for _, sym := range []string{
		"xn_ffi_socketConnect(", "xn_ffi_socketRead(", "xn_ffi_httpGetPlain(",
		"xrt_bytes_buf * xdkc_http_get(", "xn_ffi_xdkc_net_error_kind_id(",
	} {
		if !strings.Contains(sup.Text, sym) {
			t.Fatalf("支撑代码缺少 %q：\n%s", sym, sup.Text)
		}
	}
}
