package ffi

import (
	"strings"
	"testing"
)

// S6-02：xdk.runtime 六个签名全部入绑定（diagnose/exit/nowMono/nowWall/env/dumpTasks）。
func TestRuntimeXfbSixEntries(t *testing.T) {
	reg, diags, err := Load(repoBindingsDir(t))
	if err != nil || len(diags) != 0 {
		t.Fatalf("Load 失败：%v %v", err, codeList(diags))
	}
	names := []string{}
	for _, e := range reg.Entries {
		if e.Region == "xdkc_runtime" {
			names = append(names, e.Name)
		}
	}
	want := []string{"diagnose", "dumpTasks", "env", "exit", "nowMono", "nowWall"}
	if strings.Join(names, ",") != strings.Join(want, ",") {
		t.Fatalf("runtime 入口不符\n got=%v\nwant=%v", names, want)
	}
}
