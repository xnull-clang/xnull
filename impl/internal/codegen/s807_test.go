package codegen

import (
	"bytes"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/codegen/ffi"
)

const s807Manifest = `project {
  groupId    = com.example
  artifactId = s807-app
  version    = 1.0.0
  packaging  = app

  link {
    libraries {
      library z {
        kind = dynamic
      }
      library m {
        kind   = static
        system = true
      }
    }
  }
}
`

func TestS807ReadLinkLibraries(t *testing.T) {
	root := t.TempDir()
	writeFFIFile(t, filepath.Join(root, "xnull.project"), s807Manifest)
	libs, has, err := readLinkLibraries(root)
	if err != nil {
		t.Fatalf("readLinkLibraries: %v", err)
	}
	if !has || len(libs) != 2 {
		t.Fatalf("has=%v libs=%v，期望 2 个库", has, libs)
	}
	if libs[0].Name != "m" || libs[0].Kind != "static" || !libs[0].System {
		t.Fatalf("m 库解析不符：%+v", libs[0])
	}
	if libs[1].Name != "z" || libs[1].Kind != "dynamic" || libs[1].System {
		t.Fatalf("z 库解析不符：%+v", libs[1])
	}
}

func TestS807LinkLibrariesRejectInvalid(t *testing.T) {
	cases := []struct{ name, link, want string }{
		{"重复库", "library m { kind = static }\n      library m { kind = dynamic }", "重复"},
		{"缺 kind", "library m { system = true }", "kind"},
		{"kind 非法", "library m { kind = weird }", "kind"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			root := t.TempDir()
			writeFFIFile(t, filepath.Join(root, "xnull.project"), `project {
  packaging = app
  link {
    libraries {
      `+tc.link+`
    }
  }
}
`)
			_, _, err := readLinkLibraries(root)
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("错误=%v，期望含 %q", err, tc.want)
			}
		})
	}
}

func TestS807FFIRegionMustBeDeclared(t *testing.T) {
	reg := &ffi.Registry{Entries: []ffi.Entry{
		{Name: "ffiOk", Region: "m"},
		{Name: "ffiBad", Region: "other"},
		{Name: "ffiInternal", Region: "xdkc_sys"},
	}}
	err := checkFFILibraries(reg, []ffi.LinkLib{{Name: "m"}}, true)
	if err == nil || !strings.Contains(err.Error(), "other") {
		t.Fatalf("未声明的 FFI 区域未被拒绝：%v", err)
	}
	if strings.Contains(err.Error(), "xdkc_sys") {
		t.Fatalf("内部区域不应参与 link.libraries 校验：%v", err)
	}
	if err := checkFFILibraries(reg, nil, false); err != nil {
		t.Fatalf("无 libraries 块时应跳过（bootstrap）：%v", err)
	}
}

func TestS807MergeLinkArgs(t *testing.T) {
	got := mergeLinkArgs([]string{"-L/x", "-lz"}, []ffi.LinkLib{
		{Name: "m"}, {Name: "z"},
	})
	want := []string{"-L/x", "-lm", "-lz"}
	if strings.Join(got, " ") != strings.Join(want, " ") {
		t.Fatalf("mergeLinkArgs=%v，期望 %v", got, want)
	}
}

func TestS807UnsafeLogWithoutEntries(t *testing.T) {
	dir := t.TempDir()
	mainPath := filepath.Join(dir, "main.x")
	writeFFIFile(t, mainPath, "static Int main() { return 0 }\n")
	writeFFIFile(t, filepath.Join(dir, "xnull.project"), `project {
  packaging = app
  link {
    unsafe = true
  }
}
`)
	bin := filepath.Join(dir, "prog")
	var stderr bytes.Buffer
	if code := BuildWithOptions(mainPath, bin, filepath.Join("..", "..", "runtime"), Options{}, &stderr); code != 0 {
		t.Fatalf("构建失败：%s", stderr.String())
	}
	if !strings.Contains(stderr.String(), "link.unsafe=true") {
		t.Fatalf("link.unsafe=true 未写构建日志（S8 §7）：%q", stderr.String())
	}
}

const s807Xfb = `ffi m {
  @ffiEntry(cName = "native_add")
  @lease(a = .borrow, b = .borrow)
  @blocking(.aware)
  Int64 ffiAdd(Int64 a, Int64 b);
}
`

const s807Main = `static Int main() {
    print(str(ffiAdd(2, 3)))
    return 0
}
`

func TestS807BuildUsesManifestLibraries(t *testing.T) {
	cc, err := exec.LookPath("cc")
	if err != nil {
		t.Skip("无 C 编译器")
	}
	ar, err := exec.LookPath("ar")
	if err != nil {
		t.Skip("无 ar")
	}
	dir := t.TempDir()
	writeFFIFile(t, filepath.Join(dir, "bindings", "native.xfb"), s807Xfb)
	writeFFIFile(t, filepath.Join(dir, "main.x"), s807Main)
	writeFFIFile(t, filepath.Join(dir, "xnull.project"), `project {
  packaging = app
  link {
    libraries {
      library m {
        kind = static
      }
    }
  }
}
`)
	writeFFIFile(t, filepath.Join(dir, "native.c"), "#include <stdint.h>\nint64_t native_add(int64_t a, int64_t b) { return a + b; }\n")

	obj := filepath.Join(dir, "native.o")
	if out, err := exec.Command(cc, "-std=c11", "-O2", "-c", filepath.Join(dir, "native.c"), "-o", obj).CombinedOutput(); err != nil {
		t.Fatalf("cc -c: %v\n%s", err, out)
	}
	if out, err := exec.Command(ar, "rcs", filepath.Join(dir, "libm.a"), obj).CombinedOutput(); err != nil {
		t.Fatalf("ar: %v\n%s", err, out)
	}

	bin := filepath.Join(dir, "prog")
	var stderr bytes.Buffer
	code := BuildWithOptions(filepath.Join(dir, "main.x"), bin, filepath.Join("..", "..", "runtime"),
		Options{LinkArgs: []string{"-L" + dir}}, &stderr)
	if code != 0 {
		t.Fatalf("manifest link.libraries 未接入构建：%s", stderr.String())
	}
	out, err := exec.Command(bin).CombinedOutput()
	if err != nil {
		t.Fatalf("运行失败：%v\n%s", err, out)
	}
	if strings.TrimSpace(string(out)) != "5" {
		t.Fatalf("输出=%q，期望 5", out)
	}
}

func TestS807BuildRejectsUndeclaredFFIRegion(t *testing.T) {
	cc, err := exec.LookPath("cc")
	if err != nil {
		t.Skip("无 C 编译器")
	}
	_ = cc
	dir := t.TempDir()
	writeFFIFile(t, filepath.Join(dir, "bindings", "other.xfb"), `ffi other {
  @ffiEntry(cName = "native_add")
  @lease(a = .borrow, b = .borrow)
  @blocking(.aware)
  Int64 ffiAdd(Int64 a, Int64 b);
}
`)
	writeFFIFile(t, filepath.Join(dir, "main.x"), s807Main)
	writeFFIFile(t, filepath.Join(dir, "xnull.project"), `project {
  packaging = app
  link {
    libraries {
      library m {
        kind = static
      }
    }
  }
}
`)
	bin := filepath.Join(dir, "prog")
	var stderr bytes.Buffer
	code := BuildWithOptions(filepath.Join(dir, "main.x"), bin, filepath.Join("..", "..", "runtime"), Options{}, &stderr)
	if code == 0 {
		t.Fatalf("FFI 区域 other 未在 link.libraries 声明，构建应失败")
	}
	if !strings.Contains(stderr.String(), "other") || !strings.Contains(stderr.String(), "link.libraries") {
		t.Fatalf("失败原因未点名未声明区域：%s", stderr.String())
	}
}
