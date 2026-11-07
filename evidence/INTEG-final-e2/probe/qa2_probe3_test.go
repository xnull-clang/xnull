package sema

import (
	"strings"
	"testing"
)

func TestQA2Int64NegativeOverflowExactCodes(t *testing.T) {
	cases := []struct{ name, src, code string }{
		{"assign-min-1", "static Int main() { Int64 v = -9223372036854775809\n return 0 }", TyAssignability},
		{"assign-min-2", "static Int main() { Int64 v = -9223372036854775810\n return 0 }", TyAssignability},
		{"assign-min-max", "static Int main() { Int64 v = -18446744073709551615\n return 0 }", TyAssignability},
		{"cmp-gt-min-1", "static Int main() { Int64 a = 0\n if (a > -9223372036854775809) { return 1 }\n return 0 }", TyBadOperand},
		{"cmp-ge-min-1", "static Int main() { Int64 a = 0\n if (a >= -9223372036854775809) { return 1 }\n return 0 }", TyBadOperand},
		{"cmp-eq-min-1", "static Int main() { Int64 a = 0\n if (a == -9223372036854775809) { return 1 }\n return 0 }", TyBadOperand},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := codes(t, c.src)
			if len(got) != 1 || !strings.HasPrefix(got[0], c.code) {
				t.Fatalf("期望 [%s]，实际 %v", c.code, got)
			}
		})
	}
}
