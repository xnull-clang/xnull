package xnfmt

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func mustFormat(t *testing.T, src string) string {
	t.Helper()
	out, diags := Format("t.x", src)
	if len(diags) > 0 {
		t.Fatalf("格式化失败：%v", diags)
	}
	return out
}

func TestFormatRuleTable(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		// R3 编码与文件级
		{"R3.2 BOM", "\ufeffstatic Int main() {\nreturn 0\n}\n", "static Int main() {\n    return 0\n}\n"},
		{"R3.3 CRLF", "static Int main() {\r\n    return 0\r\n}\r\n", "static Int main() {\n    return 0\n}\n"},
		{"R3.3 孤立 CR", "static Int main() {\r    return 0\r}\r", "static Int main() {\n    return 0\n}\n"},
		{"R3.4 行尾空白", "static Int main() {   \n    return 0\t\n}\n", "static Int main() {\n    return 0\n}\n"},
		{"R3.5 无结尾换行", "static Int main() {\n    return 0\n}", "static Int main() {\n    return 0\n}\n"},
		{"R3.6 空文件", "", ""},
		{"R3.6 全空白", "  \n\t\n", ""},

		// R4 缩进
		{"R4.1 普通行", "static Int f() {\nif (true) {\nreturn 1\n}\n}\n",
			"static Int f() {\n    if (true) {\n        return 1\n    }\n}\n"},
		{"R4.2 } 行", "static Int f() {\nreturn 1\n    }\n", "static Int f() {\n    return 1\n}\n"},
		{"R4.4 括号续行", "static Int sum(Int a,\nInt b) {\nInt r = add(a,\nb)\nreturn r\n}\n",
			"static Int sum(Int a,\n    Int b) {\n    Int r = add(a,\n        b)\n    return r\n}\n"},
		{"R4.5 标签", "static Int f() {\nloop:\nreturn 1\n}\n",
			"static Int f() {\n    loop:\n    return 1\n}\n"},

		// R5 空行
		{"R5.1 文件首空行", "\n\nstatic Int main() {\n    return 0\n}\n", "static Int main() {\n    return 0\n}\n"},
		{"R5.2 折叠", "static Int a() {\n    return 1\n}\n\n\n\nstatic Int b() {\n    return 2\n}\n",
			"static Int a() {\n    return 1\n}\n\nstatic Int b() {\n    return 2\n}\n"},
		{"R5.3 { 后空行", "static Int main() {\n\n    return 0\n}\n", "static Int main() {\n    return 0\n}\n"},
		{"R5.4 } 前空行", "static Int main() {\n    return 0\n\n}\n", "static Int main() {\n    return 0\n}\n"},
		{"R5.5 文件末尾空行", "static Int main() {\n    return 0\n}\n\n\n", "static Int main() {\n    return 0\n}\n"},

		// R6 行内空白
		{"R6.5 调用", "static Int f() {\nreturn  g( 1,2 )\n}\n", "static Int f() {\n    return g(1, 2)\n}\n"},
		{"R6.6 下标", "static Int f(Int[] a) {\nreturn a[ 0 ]\n}\n", "static Int f(Int[] a) {\n    return a[0]\n}\n"},
		{"R6.9 空体", "class A {\n}\nstatic Int f() {\nreturn g()\n}\n", "class A {\n}\nstatic Int f() {\n    return g()\n}\n"},
		{"R6.13 逗号后", "class A {\nInt a;Int b\n}\n", "class A {\n    Int a; Int b\n}\n"},
		{"R6.18 区间", "static Bool f(Int i, Int n) {\nreturn i in 0..<n\n}\n",
			"static Bool f(Int i, Int n) {\n    return i in 0..<n\n}\n"},

		// R7 一元/二元
		{"R7.2 a-1", "static Int f(Int a) {\nreturn a-1\n}\n", "static Int f(Int a) {\n    return a - 1\n}\n"},
		{"R7.3 -1", "static Int f() {\nreturn -1\n}\n", "static Int f() {\n    return -1\n}\n"},
		{"R7.2 i++", "static Int f(Int i) {\ni++\nreturn i\n}\n", "static Int f(Int i) {\n    i++\n    return i\n}\n"},
		{"R7.3 ++i", "static Int f(Int i) {\n++i\nreturn i\n}\n", "static Int f(Int i) {\n    ++i\n    return i\n}\n"},
		{"R7.1 !ok", "static Bool f(Bool ok) {\nreturn !ok\n}\n", "static Bool f(Bool ok) {\n    return !ok\n}\n"},
		{"R7.4 a*-b", "static Int f(Int a, Int b) {\nreturn a*-b\n}\n", "static Int f(Int a, Int b) {\n    return a * -b\n}\n"},

		// R8 ?/<>
		{"R8.4 可空", "static String? f(String? s, List<Int>? xs, Map<String, Int>? m) {\nreturn s\n}\n",
			"static String? f(String? s, List<Int>? xs, Map<String, Int>? m) {\n    return s\n}\n"},
		{"R8.3 三元", "static Int f(Int a, Int b) {\nreturn a<b ? a : b\n}\n",
			"static Int f(Int a, Int b) {\n    return a < b ? a : b\n}\n"},
		{"R8.8 泛型", "static Int f() {\nResult<Int,String> r = identity<Int>(1)\nreturn 0\n}\n",
			"static Int f() {\n    Result<Int, String> r = identity<Int>(1)\n    return 0\n}\n"},
		{"R8.10 嵌套泛型", "static Map<String, List<Int>> f() {\nreturn null\n}\n",
			"static Map<String, List<Int>> f() {\n    return null\n}\n"},
		{"R8.9 比较", "static Bool f(Int a, Int b) {\nreturn a<b\n}\n",
			"static Bool f(Int a, Int b) {\n    return a < b\n}\n"},

		// R9 头部
		{"R9.3 import 排序", "package demo\nimport xdk.sys\nimport lib.text\n\n\n\nstatic Int main() {\n    return 0\n}\n",
			"package demo\n\nimport lib.text\nimport xdk.sys\n\nstatic Int main() {\n    return 0\n}\n"},
		{"R9.8 无 package", "// 头\n\nimport lib.text\nstatic Int main() {\n    return 0\n}\n",
			"// 头\n\nimport lib.text\n\nstatic Int main() {\n    return 0\n}\n"},
		{"R9.6 行尾注释随行", "import b.lib // B\nimport a.lib // A\n",
			"import a.lib // A\nimport b.lib // B\n"},

		// R10 注释
		{"R10.1 行注释正文保留", "//  a  \nstatic Int main() {\n    return 0\n}\n",
			"//  a\n\nstatic Int main() {\n    return 0\n}\n"},
		{"R10.6 字符串内的 //", "static String f() {\nreturn \"http://x\" // 尾注释\n}\n",
			"static String f() {\n    return \"http://x\" // 尾注释\n}\n"},
		{"R10.4 块注释原样", "/* a\n   b */\nstatic Int main() {\n    return 0\n}\n",
			"/* a\n   b */\n\nstatic Int main() {\n    return 0\n}\n"},

		// R11 长行不折
		{"R11 长行", "static Int f() {\nInt veryLongName = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa + b\nreturn 0\n}\n",
			"static Int f() {\n    Int veryLongName = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa + b\n    return 0\n}\n"},

		// 补充：R6 其余例外
		{"R6.4 点号", "static Int f(A a) {\nreturn a.b\n}\n", "static Int f(A a) {\n    return a.b\n}\n"},
		{"R6.7 注解", "@inline\nstatic Int f() {\n    return 0\n}\n", "@inline\nstatic Int f() {\n    return 0\n}\n"},
		{"R6.15 控制关键字", "static Int f(Int x) {\nif(x > 0) {\nreturn 1\n}\nreturn 0\n}\n",
			"static Int f(Int x) {\n    if (x > 0) {\n        return 1\n    }\n    return 0\n}\n"},
		{"R6.19 空 Map", "static Int f() {\nMap<String, Int> m = [:]\nreturn 0\n}\n",
			"static Int f() {\n    Map<String, Int> m = [:]\n    return 0\n}\n"},

		// 补充：R8 其余
		{"R8.5 字典冒号", "static Int f() {\nMap<String, Int> m = [\"k\": 1]\nreturn 0\n}\n",
			"static Int f() {\n    Map<String, Int> m = [\"k\": 1]\n    return 0\n}\n"},
		{"R8.6 ?. 与 as?", "static Int f(A a) {\nString? s = a?.name as? String\nreturn 0\n}\n",
			"static Int f(A a) {\n    String? s = a?.name as? String\n    return 0\n}\n"},

		// 补充：R9 其余
		{"R9.4 重复路径别名", "import b.lib as z\nimport a.lib\nimport a.lib as y\n",
			"import a.lib\nimport a.lib as y\nimport b.lib as z\n"},
		{"R9.9 正文 import 不排序", "static Int main() {\nimport b.lib\nimport a.lib\nreturn 0\n}\n",
			"static Int main() {\n    import b.lib\n    import a.lib\n    return 0\n}\n"},

		// 补充：R10 其余
		{"R10.2 独立注释缩进", "static Int f() {\nif (true) {\n// 说明\nreturn 1\n}\nreturn 0\n}\n",
			"static Int f() {\n    if (true) {\n        // 说明\n        return 1\n    }\n    return 0\n}\n"},
		{"R10.5 注释不计深度", "static Int f() {\nreturn 1 // { 未闭合\n}\n",
			"static Int f() {\n    return 1 // { 未闭合\n}\n"},

		// 补充：R5.7 多行字面量内部空行保留
		{"R5.7 多行串内空行", "static String f() {\nreturn \"\"\"a\n\nb\"\"\"\n}\n",
			"static String f() {\n    return \"\"\"a\n\nb\"\"\"\n}\n"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := mustFormat(t, c.in)
			if got != c.want {
				t.Fatalf("输入：\n%q\n得到：\n%q\n期望：\n%q", c.in, got, c.want)
			}
		})
	}
}

// §16 样例 A：examples/hello.x 是固定点（F(x)=x）。
func TestFormatHelloFixedPoint(t *testing.T) {
	p := filepath.Join("..", "..", "..", "examples", "hello.x")
	data, err := os.ReadFile(p)
	if err != nil {
		t.Fatalf("读取 hello.x：%v", err)
	}
	got, diags := Format(p, string(data))
	if len(diags) > 0 {
		t.Fatalf("诊断：%v", diags)
	}
	if got != string(data) {
		t.Fatalf("hello.x 不是固定点：\n%q", got)
	}
}

// §16 样例 A–F：与规范逐字节一致。
func TestFormatSpecSamples(t *testing.T) {
	samples := []struct {
		name, in, want string
	}{
		{"B", "static Int calc( Int a,Int b ){\n    Int  s=a+b*2\n    Int m = a < b ? a : b        // 取较小值\n    return   s+m\n}\n",
			"static Int calc(Int a, Int b) {\n    Int s = a + b * 2\n    Int m = a < b ? a : b // 取较小值\n    return s + m\n}\n"},
		{"C", "// 入口：演示导入排序\n\npackage   demo.app\nimport xdk.sys\nimport lib.text\n\n\nimport   lib.shapes\n\n\n\nstatic Int main() {\n    return 0\n}\n",
			"// 入口：演示导入排序\n\npackage demo.app\n\nimport lib.shapes\nimport lib.text\nimport xdk.sys\n\nstatic Int main() {\n    return 0\n}\n"},
		{"D", "static String name(Int i) {\nswitch i {\ncase 1:\nreturn \"one\"\ncase 2:\nreturn \"two\"\ndefault:\nreturn \"other\"\n}\n}\n",
			"static String name(Int i) {\n    switch i {\n        case 1:\n            return \"one\"\n        case 2:\n            return \"two\"\n        default:\n            return \"other\"\n    }\n}\n"},
		{"F", "static Int pick(Int v,String? note) {\n    Int   w=v<2 ? v : 2\n    Bool ok = identity<Bool>( true )\n    return w\n}\n",
			"static Int pick(Int v, String? note) {\n    Int w = v < 2 ? v : 2\n    Bool ok = identity<Bool>(true)\n    return w\n}\n"},
	}
	for _, s := range samples {
		t.Run(s.name, func(t *testing.T) {
			if got := mustFormat(t, s.in); got != s.want {
				t.Fatalf("样例 %s 不符：\n得到 %q\n期望 %q", s.name, got, s.want)
			}
		})
	}
}

// R12.1/R12.2：全仓库 .x 幂等 + 10 次稳定；token 多重集不变。
func TestRepoIdempotent(t *testing.T) {
	root, err := filepath.Abs(filepath.Join("..", "..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	var files []string
	err = filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			switch d.Name() {
			case ".git", "wt", "xnull":
				return filepath.SkipDir
			}
			// B2 差分负例语料是故意非法的源码（LEX/SYN 负例），不参与格式化幂等扫描。
			p := filepath.ToSlash(path)
			if strings.HasSuffix(p, "tests/b2/lex_neg") || strings.HasSuffix(p, "tests/b2/parser_neg") {
				return filepath.SkipDir
			}
			return nil
		}
		if strings.HasSuffix(d.Name(), ".x") {
			files = append(files, path)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(files) == 0 {
		t.Skip("仓库内没有 .x 文件")
	}
	for _, f := range files {
		data, err := os.ReadFile(f)
		if err != nil {
			t.Fatalf("%s: %v", f, err)
		}
		once, diags := Format(f, string(data))
		if len(diags) > 0 {
			t.Fatalf("%s: %v", f, diags)
		}
		twice, diags := Format(f, once)
		if len(diags) > 0 {
			t.Fatalf("%s 二次格式化诊断：%v", f, diags)
		}
		if once != twice {
			t.Fatalf("%s 不幂等", f)
		}
		for i := 0; i < 9; i++ {
			again, _ := Format(f, string(data))
			if again != once {
				t.Fatalf("%s 第 %d 次输出不稳定", f, i+2)
			}
		}
		if !sameTokenMultiset(t, string(data), once) {
			t.Fatalf("%s token 多重集改变", f)
		}
	}
}

func sameTokenMultiset(t *testing.T, a, b string) bool {
	t.Helper()
	ta, da := scan("a", a)
	tb, db := scan("b", b)
	if len(da) > 0 || len(db) > 0 {
		return true // 词法失败由调用方其它用例覆盖
	}
	count := map[string]int{}
	for _, x := range ta {
		count[x.text]++
	}
	for _, x := range tb {
		count[x.text]--
	}
	for _, n := range count {
		if n != 0 {
			return false
		}
	}
	return true
}

func TestFormatDiagnostics(t *testing.T) {
	if _, diags := Format("t.x", "static String f() {\nreturn \"unterminated\n}\n"); len(diags) != 1 || diags[0].Code != fmtLex {
		t.Fatalf("未闭合字符串应报 FMT-101：%v", diags)
	}
	invalid := string([]byte{0xff, 0xfe, 0x00})
	if _, diags := Format("t.x", invalid); len(diags) != 1 || diags[0].Code != fmtEnc {
		t.Fatalf("非法 UTF-8 应报 FMT-102：%v", diags)
	}
}
