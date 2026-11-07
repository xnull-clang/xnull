package sema

import (
	"fmt"
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

func TestQAProbe(t *testing.T) {
	cases := []struct{ name, src string }{
		{"nullable-decl", `static Int main() { (Int, String)? p = null
    return 0 }`},
		{"tuple-return", `static (Int, String) f() { return (1, "a") }
static Int main() { return 0 }`},
		{"tuple-param", `static Int f((Int, String) p) { return p.0 }
static Int main() { return 0 }`},
		{"tuple-field", `class C { (Int, String) f = (1, "a") }
static Int main() { return 0 }`},
		{"tuple-array", `static Int main() { (Int, String)[] xs = [(1, "a")]
    return 0 }`},
		{"tuple-list", `static Int main() { List<(Int, String)> xs = [(1, "a")]
    return 0 }`},
		{"destructure", `static Int main() { (Int, Int) p = (1, 2)
    (Int a, Int b) = p
    return 0 }`},
		{"tuple-const", `const (Int, Int) P = (1, 2)
static Int main() { return 0 }`},
		{"oob-read", `static Int main() { (Int, String) p = (1, "a")
    print(p.2)
    return 0 }`},
		{"oob-write", `static Int main() { (Int, String) p = (1, "a")
    p.2 = 3
    return 0 }`},
		{"member-name", `static Int main() { (Int, String) p = (1, "a")
    print(p.length)
    return 0 }`},
		{"switch", `static Int main() { (Int, Int) p = (1, 2)
    switch (p) { case (1, 2): print("x") }
    return 0 }`},
		{"as-wrong", `static Int main() { (Int, Int) p = (1, 2)
    (Int, String) q = p as (Int, String)
    return 0 }`},
		{"eq-wrong", `static Int main() { (Int, Int) a = (1, 2)
    (Int, String) b = (1, "x")
    Bool e = a == b
    return 0 }`},
		{"lit-arity", `static Int main() { (Int, String) p = (1, 2, 3)
    return 0 }`},
		{"lit-elem", `static Int main() { (Int, String) p = ("a", 1)
    return 0 }`},
		{"tuple-null-safe-oob", `static Int main() { (Int, String) p = (1, "a")
    print(p?.2)
    return 0 }`},
		{"zero", `static Int main() { Tuple t = ()
    return 0 }`},
		{"one", `static Int main() { Int x = (1,)
    return 0 }`},
		{"paren", `static Int main() { Int x = (1)
    return x }`},
	}
	for _, c := range cases {
		u, pd := xfront.ParseUnit("t.x", c.src)
		sd := []string{}
		if len(pd) == 0 {
			for _, d := range Analyze("t.x", u) {
				sd = append(sd, d.Code+":"+d.Message)
			}
		}
		fmt.Printf("CASE %s P=%v S=%v\n", c.name, pd, sd)
	}
}
