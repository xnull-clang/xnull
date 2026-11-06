package ffi

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

const positiveSrc = `ffi sqlite {
  layout(c) struct Stat {
    Int64 size
    Int32 mode
  }

  handle Db { close = ffiSqliteClose }

  errorMap {
    5  = NotFound
    14 = Cancelled
  }

  @ffiEntry(cName = "sqlite3_open")
  @lease(path = .borrow, db = .transfer)
  @errorCode(codeParam = .result)
  @blocking(.unaware)
  Int32 ffiSqliteOpen(Bytes path, Db db);

  @ffiEntry(cName = "sqlite3_close")
  @lease(db = .borrow)
  @errorCode(codeParam = .result)
  @blocking(.aware)
  Int32 ffiSqliteClose(Db db);

  @ffiEntry(cName = "sqlite3_exec")
  @lease(db = .borrow, sql = .borrow, out = .transfer)
  @blocking(.unaware)
  @longRunning
  Int32 ffiSqliteExec(Db db, String sql, Bytes out);

  @ffiEntry(cName = "sqlite3_exec_submit")
  @lease(db = .borrow, sql = .borrow, out = .reclaim)
  @blocking(.unaware)
  Int32 submitffiSqliteExec(Db db, String sql, Bytes out);
}
`

func writeXfb(t *testing.T, root, rel, src string) {
	t.Helper()
	p := filepath.Join(root, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	if err := os.WriteFile(p, []byte(src), 0o644); err != nil {
		t.Fatalf("write: %v", err)
	}
}

func loadSrc(t *testing.T, rel, src string) (*Registry, []Diagnostic) {
	t.Helper()
	root := t.TempDir()
	writeXfb(t, root, rel, src)
	reg, diags, err := Load(root)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	return reg, diags
}

func hasCode(ds []Diagnostic, code string) bool {
	for _, d := range ds {
		if d.Code == code {
			return true
		}
	}
	return false
}

func codeList(ds []Diagnostic) []string {
	out := make([]string, 0, len(ds))
	for _, d := range ds {
		out = append(out, d.Code)
	}
	return out
}

func TestLoadNoBindings(t *testing.T) {
	reg, diags, err := Load(t.TempDir())
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if len(diags) != 0 {
		t.Fatalf("空路径应无诊断，得到 %v", codeList(diags))
	}
	if reg == nil || !reg.Empty() {
		t.Fatalf("空路径应返回空注册表")
	}
	if _, ok := reg.Entry("nope"); ok {
		t.Fatalf("空注册表不应命中入口")
	}
	if reg.EmitSupport().Text != "" {
		t.Fatalf("空注册表支撑代码应为空片段")
	}
}

func TestLoadPositiveAndDeterministic(t *testing.T) {
	root := t.TempDir()
	writeXfb(t, root, "bindings/sqlite.xfb", positiveSrc)

	reg, diags, err := Load(root)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if len(diags) != 0 {
		t.Fatalf("正例不应有诊断，得到 %v", codeList(diags))
	}
	if len(reg.Entries) != 4 {
		t.Fatalf("入口数 = %d，want 4", len(reg.Entries))
	}
	// 确定性：按名称排序
	wantOrder := []string{"ffiSqliteClose", "ffiSqliteExec", "ffiSqliteOpen", "submitffiSqliteExec"}
	for i, want := range wantOrder {
		if reg.Entries[i].Name != want {
			t.Fatalf("排序后第 %d 项 = %s，want %s", i, reg.Entries[i].Name, want)
		}
	}

	open, ok := reg.Entry("ffiSqliteOpen")
	if !ok {
		t.Fatalf("缺少 ffiSqliteOpen")
	}
	if open.CName != "sqlite3_open" || open.Region != "sqlite" {
		t.Fatalf("ffiSqliteOpen 元数据错误：%+v", open)
	}
	if !open.ErrorCodeRet || open.ErrorCode != "" {
		t.Fatalf("错误码通道应为返回值形态：%+v", open)
	}
	if open.Blocking != BlockingUnaware {
		t.Fatalf("阻塞分类 = %v，want .unaware", open.Blocking)
	}
	if len(open.Lease) != 2 || open.Lease[0] != LeaseBorrow || open.Lease[1] != LeaseTransfer {
		t.Fatalf("租约解析错误：%v", open.Lease)
	}
	if len(open.ErrorMap) != 2 || open.ErrorMap[0].Code != 5 || open.ErrorMap[1].Kind != "Cancelled" {
		t.Fatalf("错误映射排序/解析错误：%+v", open.ErrorMap)
	}

	closeEntry, _ := reg.Entry("ffiSqliteClose")
	if closeEntry.CloseOf != "Db" {
		t.Fatalf("close 入口归属错误：%+v", closeEntry)
	}
	execEntry, _ := reg.Entry("ffiSqliteExec")
	if !execEntry.LongRunning || execEntry.Blocking != BlockingUnaware {
		t.Fatalf("长阻塞标记错误：%+v", execEntry)
	}

	if len(reg.Layouts) != 1 || reg.Layouts[0].Name != "Stat" || len(reg.Layouts[0].Fields) != 2 {
		t.Fatalf("layout 声明输出错误：%+v", reg.Layouts)
	}
	if len(reg.Handles) != 1 || reg.Handles[0].Close != "ffiSqliteClose" {
		t.Fatalf("句柄声明输出错误：%+v", reg.Handles)
	}

	// 同一输入两次加载逐字段一致（DET-01）
	reg2, diags2, err := Load(root)
	if err != nil || len(diags2) != 0 {
		t.Fatalf("二次加载失败：%v %v", err, codeList(diags2))
	}
	if !reflect.DeepEqual(reg, reg2) {
		t.Fatalf("两次加载结果不一致（确定性违约）")
	}
}

func TestContractNegatives(t *testing.T) {
	cases := []struct {
		name string
		rel  string
		src  string
		code string
	}{
		{
			name: "语法错误",
			rel:  "bindings/a.xfb",
			src:  "ffi x { bogus }",
			code: "FFI-100",
		},
		{
			name: "缺租约",
			rel:  "bindings/a.xfb",
			src: `ffi x {
  @ffiEntry(cName = "f")
  @blocking(.aware)
  Int32 f(Int32 a);
}
`,
			code: "FFI-101",
		},
		{
			name: "移交无归还",
			rel:  "bindings/a.xfb",
			src: `ffi x {
  @ffiEntry(cName = "f")
  @lease(buf = .transfer)
  @blocking(.aware)
  Int32 f(Bytes buf);
}
`,
			code: "FFI-102",
		},
		{
			name: "String 移交",
			rel:  "bindings/a.xfb",
			src: `ffi x {
  @ffiEntry(cName = "f")
  @lease(s = .transfer)
  @blocking(.aware)
  Int32 f(String s);
}
`,
			code: "FFI-103",
		},
		{
			name: "嵌套数组",
			rel:  "bindings/a.xfb",
			src: `ffi x {
  @ffiEntry(cName = "f")
  @lease(a = .borrow)
  @blocking(.aware)
  Int32 f(Int64[][] a);
}
`,
			code: "FFI-104",
		},
		{
			name: "Result 跨界",
			rel:  "bindings/a.xfb",
			src: `ffi x {
  @ffiEntry(cName = "f")
  @lease(r = .borrow)
  @blocking(.aware)
  Int32 f(Result r);
}
`,
			code: "FFI-105",
		},
		{
			name: "错误码形参不存在",
			rel:  "bindings/a.xfb",
			src: `ffi x {
  @ffiEntry(cName = "f")
  @lease(a = .borrow)
  @errorCode(codeParam = .nope)
  @blocking(.aware)
  Int32 f(Int32 a);
}
`,
			code: "FFI-106",
		},
		{
			name: "缺阻塞分类",
			rel:  "bindings/a.xfb",
			src: `ffi x {
  @ffiEntry(cName = "f")
  @lease(a = .borrow)
  Int32 f(Int32 a);
}
`,
			code: "FFI-107",
		},
		{
			name: "裸指针",
			rel:  "bindings/a.xfb",
			src: `ffi x {
  @ffiEntry(cName = "f")
  @lease(buf = .borrow)
  @blocking(.aware)
  Int32 f(void* buf);
}
`,
			code: "FFI-108",
		},
		{
			name: "layout 字段类型非法",
			rel:  "bindings/a.xfb",
			src: `ffi x {
  layout(c) struct S {
    String name
  }
  @ffiEntry(cName = "f")
  @lease(s = .borrow)
  @blocking(.aware)
  Int32 f(S s);
}
`,
			code: "FFI-109",
		},
		{
			name: "unsafe 缺合同文本",
			rel:  "bindings/a.xfb",
			src: `ffi x {
  @ffiEntry(cName = "f")
  @lease(a = .borrow)
  @blocking(.aware)
  @unsafe
  Int32 f(Int32 a);
}
`,
			code: "FFI-110",
		},
		{
			name: "重复入口",
			rel:  "bindings/a.xfb",
			src: `ffi x {
  @ffiEntry(cName = "f")
  @lease(a = .borrow)
  @blocking(.aware)
  Int32 f(Int32 a);
  @ffiEntry(cName = "g")
  @lease(a = .borrow)
  @blocking(.aware)
  Int32 f(Int32 a);
}
`,
			code: "FFI-111",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			reg, diags := loadSrc(t, tc.rel, tc.src)
			if !hasCode(diags, tc.code) {
				t.Fatalf("期望 %s，得到 %v", tc.code, codeList(diags))
			}
			if reg != nil {
				t.Fatalf("有诊断时应返回 nil 注册表")
			}
			for _, d := range diags {
				if d.Snippet == "" || d.Width < 1 {
					t.Fatalf("诊断缺少源码片段：%+v", d)
				}
			}
		})
	}
}

func TestUnsafeOutsideBindings(t *testing.T) {
	src := `ffi x {
  @ffiEntry(cName = "f")
  @lease(a = .borrow)
  @blocking(.aware)
  @unsafe(contract = "调用方必须保证 a 非空")
  Int32 f(Int32 a);
}
`
	_, diags := loadSrc(t, "notbindings/a.xfb", src)
	if !hasCode(diags, "FFI-110") {
		t.Fatalf("bindings/ 之外的 @unsafe 应被拒绝，得到 %v", codeList(diags))
	}
}

func TestUnsafeInBindingsAccepted(t *testing.T) {
	src := `ffi x {
  @ffiEntry(cName = "f")
  @lease(a = .borrow)
  @blocking(.aware)
  @unsafe(contract = "调用方必须保证 a 非空")
  Int32 f(Int32 a);
}
`
	reg, diags := loadSrc(t, "bindings/a.xfb", src)
	if len(diags) != 0 {
		t.Fatalf("合法 @unsafe 不应有诊断：%v", codeList(diags))
	}
	e, ok := reg.Entry("f")
	if !ok || !e.Unsafe || e.ContractText == "" {
		t.Fatalf("@unsafe 入口投影错误：%+v", e)
	}
}

func TestEmitEntryLookup(t *testing.T) {
	root := t.TempDir()
	writeXfb(t, root, "bindings/sqlite.xfb", positiveSrc)
	reg, diags, err := Load(root)
	if err != nil || len(diags) != 0 {
		t.Fatalf("Load 失败：%v %v", err, codeList(diags))
	}
	if _, err := reg.EmitCall("nope", nil, "xn_tmp1"); err == nil {
		t.Fatalf("未声明入口应返回错误")
	}
	sn, err := reg.EmitCall("ffiSqliteOpen", nil, "xn_tmp1")
	if err != nil {
		t.Fatalf("已声明入口应生成包装：%v", err)
	}
	if !strings.Contains(sn.Text, "xn_ffi_ffiSqliteOpen") {
		t.Fatalf("包装函数命名不符：%s", sn.Text)
	}
	if len(sn.Includes) != 1 || sn.Includes[0] != "xrt.h" {
		t.Fatalf("生成代码只应依赖 xrt.h（INV-FFI-7）：%v", sn.Includes)
	}
}
