package sema

import "testing"

// PKG-01 F3：别名与同包裸导入的简单名同名必须报 RES-103。
func TestPKGF3AliasVsBareSameName(t *testing.T) {
	a := depPkg(t, "lib.a", `package lib.a

Int X() { return 1 }

Int Y() { return 2 }
`)
	b := depPkg(t, "lib.b", `package lib.b

Int X() { return 3 }
`)
	src := `package app
import lib.a.X as Y
import lib.b.X as BX
import lib.a.Y
static Int main() { return 0 }
`
	wantCodeWithDeps(t, src, ResAliasConflict, a, b)
}
