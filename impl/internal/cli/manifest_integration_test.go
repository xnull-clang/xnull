package cli

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// S8 集成：application.properties + resources/ + .xplugin 一路构建通过，
// .xmeta 带 config/resources/plugin 摘要。
func TestManifestIntegrationEndToEnd(t *testing.T) {
	root := t.TempDir()
	repo := t.TempDir()
	t.Setenv("XNULL_REPO", repo)

	writeFileAt(t, root, "xnull.project", `project {
  groupId = g
  artifactId = demo
  version = 1.0.0
  packaging = app
  properties {
    xdk-version = 1.0.0
    language-version = 3.3.0
  }
  configuration {
    app.name = demo
  }
  build {
    resources {
      resource src/main/resources {
        includes = [**]
        excludes = [**/*.psd]
      }
    }
    plugins {
      plugin com.example:codegen 1.2.0 {
        phase = validate
        goal  = check
        configuration {
          output = target/gen
        }
      }
    }
  }
}
`)
	writeFileAt(t, root, "src/main/x/main.x", "static Int main() {\n    return 0\n}\n")
	writeFileAt(t, root, "src/main/resources/application.properties", "app.name = from-file\n")
	writeFileAt(t, root, "src/main/resources/templates/a.txt", "hello resource\n")
	writeFileAt(t, root, "src/main/resources/skip.psd", "no\n")
	writeFileAt(t, repo, "com/example/codegen/1.2.0/.xplugin", `plugin {
  groupId          = com.example
  artifactId       = codegen
  version          = 1.2.0
  toolchainVersion = 0.1.0
  goals {
    goal check {
      phase      = validate
      configKeys = [output]
    }
  }
}
`)
	writeFileAt(t, repo, "com/example/codegen/1.2.0/codegen-1.2.0.jar", "jar")

	var out, errb bytes.Buffer
	env := Env{Stdout: &out, Stderr: &errb}
	if _, code := buildManifest(env, nil, root); code != 0 {
		t.Fatalf("构建应通过，exit=%d\n%s", code, errb.String())
	}

	artifact := filepath.Join(root, "target", "demo-1.0.0")
	bin, err := os.ReadFile(artifact)
	if err != nil {
		t.Fatalf("产物缺失：%v", err)
	}
	if !bytes.Contains(bin, []byte("templates/a.txt")) {
		t.Fatalf("产物未包含资源名 templates/a.txt")
	}
	if bytes.Contains(bin, []byte("skip.psd")) {
		t.Fatalf("excludes 未生效：skip.psd 进入了产物")
	}

	meta, err := os.ReadFile(artifact + ".xmeta")
	if err != nil {
		t.Fatalf("缺少 .xmeta：%v", err)
	}
	for _, want := range []string{"configSha256     = ", "resourcesSha256  = ", "pluginsSha256    = ", "plugins          = [com.example:codegen@1.2.0:check]"} {
		if !strings.Contains(string(meta), want) {
			t.Fatalf(".xmeta 缺少 %q：\n%s", want, meta)
		}
	}
	if strings.Contains(string(meta), "configSha256     = \n") {
		t.Fatalf("config 摘要为空：\n%s", meta)
	}
}

// 负向：缺 .xplugin → XPD-504，构建失败。
func TestManifestIntegrationMissingPluginMeta(t *testing.T) {
	root := t.TempDir()
	t.Setenv("XNULL_REPO", t.TempDir())
	writeFileAt(t, root, "xnull.project", `project {
  groupId = g
  artifactId = demo
  version = 1.0.0
  packaging = app
  build {
    plugins {
      plugin com.example:codegen 1.2.0 {
        phase = validate
        goal  = check
      }
    }
  }
}
`)
	writeFileAt(t, root, "src/main/x/main.x", "static Int main() {\n    return 0\n}\n")

	var out, errb bytes.Buffer
	env := Env{Stdout: &out, Stderr: &errb}
	if _, code := buildManifest(env, nil, root); code == 0 {
		t.Fatalf("缺 .xplugin 应构建失败")
	}
	if !strings.Contains(errb.String(), "XPD-504") {
		t.Fatalf("应为 XPD-504：%s", errb.String())
	}
}

func writeFileAt(t *testing.T, root, rel, body string) {
	t.Helper()
	p := filepath.Join(root, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}
