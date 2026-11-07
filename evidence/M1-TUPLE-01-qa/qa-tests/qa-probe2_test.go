package sema

import (
	"fmt"
	"testing"

	"xnull.dev/xnull/internal/xfront"
)

func TestQAProbe2(t *testing.T) {
	cases := []struct{ name, src string }{
		{"byte-300", `static Int main() { (Byte, Int) b = (300, 1)
    return 0 }`},
		{"ubyte-256", `static Int main() { (UByte, Int) b = (256, 1)
    return 0 }`},
		{"int-float-lit", `static Int main() { (Int, Int) b = (1.5, 2)
    return 0 }`},
		{"double-int-lit", `static Int main() { (Double, Int) b = (1, 2)
    return 0 }`},
		{"neg-byte", `static Int main() { (Byte, Int) b = (-129, 1)
    return 0 }`},
	}
	for _, c := range cases {
		u, pd := xfront.ParseUnit("t.x", c.src)
		var sd []string
		if len(pd) == 0 {
			for _, d := range Analyze("t.x", u) {
				sd = append(sd, d.Code+":"+d.Message)
			}
		}
		fmt.Printf("CASE %s P=%v S=%v\n", c.name, pd, sd)
	}
}
