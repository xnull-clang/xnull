package sema

import "testing"

// PKG-01 F2：`xdk.net.http` 是合法多级 XDK 包导入（S1 §3.2）。
func TestPKGF2XdkMultilevelPackage(t *testing.T) {
	expectNone(t, "import xdk.net.http\n\nstatic Int main() { return 0 }")
}
