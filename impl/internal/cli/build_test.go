package cli

import (
	"reflect"
	"testing"

	"xnull.dev/xnull/internal/codegen/ffi"
)

// M6-B0-02（P-10 条件 3）：链接参数确定性——去重 + 升序，-L 在 -l 之前。
func TestLinkArgsDeterministic(t *testing.T) {
	libs := []ffi.LinkLib{{Name: "z"}, {Name: "m"}, {Name: "z"}}
	dirs := []string{"/opt/lib", "/usr/lib", "/opt/lib"}

	got := linkArgs(libs, dirs)
	want := []string{"-L/opt/lib", "-L/usr/lib", "-lm", "-lz"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("链接参数不符：got %v want %v", got, want)
	}
	if got := linkArgs(nil, nil); len(got) != 0 {
		t.Fatalf("无库时应为空，实际 %v", got)
	}
}
