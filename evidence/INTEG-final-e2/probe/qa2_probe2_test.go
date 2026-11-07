package sema

import "testing"

func TestQA2Int64NegativeOverflowProbe(t *testing.T) {
	cases := []struct{ name, src string }{
		{"assign-min-1", "static Int main() { Int64 v = -9223372036854775809\n return 0 }"},
		{"assign-min-2", "static Int main() { Int64 v = -9223372036854775810\n return 0 }"},
		{"cmp-gt-min-1", "static Int main() { Int64 a = 0\n if (a > -9223372036854775809) { return 1 }\n return 0 }"},
		{"cmp-ge-min-1", "static Int main() { Int64 a = 0\n if (a >= -9223372036854775809) { return 1 }\n return 0 }"},
		{"cmp-eq-min-1", "static Int main() { Int64 a = 0\n if (a == -9223372036854775809) { return 1 }\n return 0 }"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := codes(t, c.src)
			t.Logf("diags=%v", got)
			if len(got) == 0 {
				t.Fatalf("越界字面量被静默接受：期望 TY-101/TY-105，实际无诊断")
			}
		})
	}
}
