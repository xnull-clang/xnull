package sema

import "testing"

// PKG-01 F1：同一包的不同符号不得共用一个 as 别名（§3.3/§3.5）。
func TestPKGF1SameSourceAliasConflict(t *testing.T) {
	a := depPkg(t, "lib.a", `package lib.a

Int X() { return 1 }

Int Y() { return 2 }
`)
	b := depPkg(t, "lib.b", `package lib.b

Int X() { return 3 }

Int Y() { return 4 }
`)
	src := `package app
import lib.a.X as P
import lib.b.X as BX
import lib.a.Y as P
import lib.b.Y as BY
static Int main() { return P() + BX() + BY() }
`
	wantCodeWithDeps(t, src, ResAliasConflict, a, b)
}
