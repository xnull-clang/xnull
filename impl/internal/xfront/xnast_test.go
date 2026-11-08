package xfront

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// B2-00：oracle 格式 v1 的稳定性和字段覆盖。
const xnastSample = `package com.example

import xdk.errors

@annotation Flag {
    final String name = ""
}

class Box<T> {
    final Int id;
    Box(Int id) { self.id = id }
    Int get() { return self.id }
}

struct Point {
    Int x;
    Int y;
}

protocol P {
    Int get();
}

enum Color {
    Red,
    Blue,
}

static Int? pick(Int x, String? s) {
    if x > 0 {
        return x
    }
    return null
}

static Int main() {
    List<Int> xs = [1, 2, 3]
    Int n = xs.length()
    for v in xs { n = n + v }
    return n
}
`

func TestXNASTDeterministic(t *testing.T) {
	u, ds := ParseUnit("sample.x", xnastSample)
	if len(ds) != 0 {
		t.Fatalf("样例不应有诊断：%v", ds)
	}
	a1, a2 := PrintUnitPos(u), PrintUnitPos(u)
	if a1 != a2 {
		t.Fatal("AST 输出不稳定")
	}
	toks, _ := Lex("sample.x", xnastSample)
	t1, t2 := PrintTokens(toks), PrintTokens(toks)
	if t1 != t2 {
		t.Fatal("token 输出不稳定")
	}
	if d1, d2 := PrintDiags(ds), PrintDiags(ds); d1 != d2 {
		t.Fatal("诊断输出不稳定")
	}
	if !strings.HasPrefix(a1, "(xnast v1 ") {
		t.Fatalf("AST 头不符：%q", a1)
	}
	if !strings.HasPrefix(t1, "xnast-tokens v1\n") {
		t.Fatalf("token 头不符：%q", t1)
	}
}

func TestXNASTFieldCoverage(t *testing.T) {
	u, ds := ParseUnit("sample.x", xnastSample)
	if len(ds) != 0 {
		t.Fatalf("样例不应有诊断：%v", ds)
	}
	out := PrintUnitPos(u)
	// 抽样校验“容易漏掉”的 AST 字段均出现在输出中。
	for _, field := range []string{
		"Public", "Protected", "Private", "Static", "Void",
		"TypePars", "Params", "Body", "Annos", "Primary",
		"Base", "Protocols", "Fields", "Methods", "Ctors",
		"Init", "Canonical", "IsDeinit", "Extends", "Sigs",
	} {
		if !strings.Contains(out, "("+field+" ") && !strings.Contains(out, "("+field+")") {
			t.Errorf("AST 输出缺少字段 %s", field)
		}
	}
	// token 的所有可选字段也必须出现。
	toks, _ := Lex("sample.x", xnastSample)
	tout := PrintTokens(toks)
	for _, field := range []string{"Kind", "Text", "Line", "Col", "Str", "Value", "Segs", "Interps", "Char", "Base", "Suffix", "HasSuffixF"} {
		if !strings.Contains(tout, "("+field+" ") && !strings.Contains(tout, "("+field+")") {
			t.Errorf("token 输出缺少字段 %s", field)
		}
	}
}

func TestXNASTPositionPresence(t *testing.T) {
	u, ds := ParseUnit("sample.x", "static Int main() {\n    return 1\n}\n")
	if len(ds) != 0 {
		t.Fatalf("诊断：%v", ds)
	}
	out := PrintUnitPos(u)
	if !strings.Contains(out, "(Line 1)") || !strings.Contains(out, "(Col 5)") {
		t.Fatalf("输出缺少位置：%s", out)
	}
}

func TestXNASTCorpusStable(t *testing.T) {
	root := filepath.Join("..", "..", "..")
	data, err := os.ReadFile(filepath.Join(root, "tests", "b2", "corpus.tsv"))
	if err != nil {
		t.Skip("语料清单未生成")
	}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.SplitN(line, "\t", 2)
		if len(parts) != 2 {
			t.Fatalf("语料行非法：%q", line)
		}
		path := filepath.Join(root, parts[1])
		src, err := os.ReadFile(path)
		if err != nil {
			t.Skipf("语料暂不可读（%s）：%v", parts[1], err)
		}
		toks1, _ := Lex(parts[1], string(src))
		toks2, _ := Lex(parts[1], string(src))
		if PrintTokens(toks1) != PrintTokens(toks2) {
			t.Errorf("%s token 输出不稳定", parts[1])
		}
		u1, d1 := ParseUnit(parts[1], string(src))
		u2, d2 := ParseUnit(parts[1], string(src))
		if PrintUnitPos(u1) != PrintUnitPos(u2) {
			t.Errorf("%s AST 输出不稳定", parts[1])
		}
		if PrintDiags(d1) != PrintDiags(d2) {
			t.Errorf("%s 诊断输出不稳定", parts[1])
		}
	}
}
