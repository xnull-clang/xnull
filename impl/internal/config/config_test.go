package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"xnull.dev/xnull/internal/diag"
)

func writeConfigFile(t *testing.T, dir, name, content string) string {
	t.Helper()
	p := filepath.Join(dir, name)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func hasCode(ds []diag.Diagnostic, code string) bool {
	for _, d := range ds {
		if d.Code == code {
			return true
		}
	}
	return false
}

func countCode(ds []diag.Diagnostic, code string) int {
	n := 0
	for _, d := range ds {
		if d.Code == code {
			n++
		}
	}
	return n
}

func messageContains(ds []diag.Diagnostic, code, substr string) bool {
	for _, d := range ds {
		if d.Code == code && strings.Contains(d.Message, substr) {
			return true
		}
	}
	return false
}

func baseSpec() Spec {
	return Spec{
		Keys: map[string]KeySpec{
			"app.name":             {Kind: KindString, Required: true},
			"net.http.listen-port": {Kind: KindInt},
			"db.url":               {Kind: KindString},
			"db.password":          {Kind: KindString},
			"feature.flag":         {Kind: KindBool},
			"app.ratio":            {Kind: KindFloat},
		},
		Profiles:     []string{"prod", "dev"},
		EnvWhitelist: []string{"db.password", "db.url"},
	}
}

// 五层覆盖：configuration < builtin < application < profile < env < CLI。
func TestLoadFiveLayers(t *testing.T) {
	dir := t.TempDir()
	writeConfigFile(t, dir, "application.properties", "db.url=app\nnet.http.listen-port=8080\nfeature.flag=true\n")
	writeConfigFile(t, dir, "application-prod.properties", "db.url=prod\napp.ratio=1.5\n")

	var audit strings.Builder
	res, ds := Load(Options{
		ResourcesDir: dir,
		Profile:      "prod",
		Packaging:    "app",
		Configuration: map[string]string{
			"db.url":               "cfg",
			"net.http.listen-port": "1",
		},
		Builtin: map[string]string{
			"app.name":     "svc",
			"feature.flag": "false",
			"app.ratio":    "0.5",
		},
		Environ: []string{
			"XNULL_OVERRIDE_DB_URL=env",
			"XNULL_OVERRIDE_DB_PASSWORD=s3cret",
			"XNULL_OVERRIDE_APP_RATIO=9.9", // 不在白名单 → 忽略
		},
		CLI: map[string]string{
			"db.url":               "cli",
			"net.http.listen-port": "9090",
		},
		Spec:  baseSpec(),
		Audit: &audit,
	})
	if len(ds) != 0 {
		t.Fatalf("不应有诊断：%v", ds)
	}
	want := map[string]string{
		"app.name":             "svc",    // layer 1
		"net.http.listen-port": "9090",   // layer 5
		"db.url":               "cli",    // layer 5
		"db.password":          "s3cret", // layer 4
		"feature.flag":         "true",   // layer 2
		"app.ratio":            "1.5",    // layer 3（env 非白名单）
	}
	for k, v := range want {
		if got := res.Values[k]; got != v {
			t.Fatalf("%s=%q，期望 %q", k, got, v)
		}
	}
	if res.Origins["db.url"].Layer != LayerCLI {
		t.Fatalf("db.url 来源层=%v，期望 CLI", res.Origins["db.url"].Layer)
	}
	if res.Origins["app.name"].Layer != LayerBuiltin {
		t.Fatalf("app.name 来源层=%v，期望 builtin", res.Origins["app.name"].Layer)
	}
	if res.Origins["db.password"].Layer != LayerEnv {
		t.Fatalf("db.password 来源层=%v，期望 env", res.Origins["db.password"].Layer)
	}
	if !strings.Contains(audit.String(), "key=db.url") || !strings.Contains(audit.String(), "layer=5") {
		t.Fatalf("CLI 覆盖未写审计：%q", audit.String())
	}
}

func TestEnvWhitelistIgnoresNonWhitelisted(t *testing.T) {
	dir := t.TempDir()
	writeConfigFile(t, dir, "application.properties", "db.url=app\n")
	spec := baseSpec()
	spec.EnvWhitelist = nil
	res, ds := Load(Options{
		ResourcesDir: dir, Packaging: "app", Environ: []string{"XNULL_OVERRIDE_DB_URL=env"},
		Builtin: map[string]string{"app.name": "svc"}, Spec: spec,
	})
	if len(ds) != 0 {
		t.Fatalf("白名单外环境变量应被忽略：%v", ds)
	}
	if res.Values["db.url"] != "app" {
		t.Fatalf("db.url=%q，期望 app", res.Values["db.url"])
	}
}

func TestUnknownKeysListed(t *testing.T) {
	dir := t.TempDir()
	writeConfigFile(t, dir, "application.properties", "unknown.a=1\nunknown.b=2\n")
	_, ds := Load(Options{
		ResourcesDir: dir, Packaging: "app",
		Builtin: map[string]string{"app.name": "svc"},
		CLI:     map[string]string{"unknown.c": "3"},
		Spec:    baseSpec(),
	})
	if n := countCode(ds, CodeUnknownKey); n != 3 {
		t.Fatalf("未知键诊断数=%d，期望 3：%v", n, ds)
	}
	for _, k := range []string{"unknown.a", "unknown.b", "unknown.c"} {
		if !messageContains(ds, CodeUnknownKey, k) {
			t.Fatalf("未知键 %s 未被点名：%v", k, ds)
		}
	}
}

func TestDuplicateKeyInSameLayer(t *testing.T) {
	dir := t.TempDir()
	writeConfigFile(t, dir, "application.properties", "db.url=a\ndb.url=b\n")
	_, ds := Load(Options{
		ResourcesDir: dir, Packaging: "app",
		Builtin: map[string]string{"app.name": "svc"}, Spec: baseSpec(),
	})
	if !hasCode(ds, CodeDuplicateKey) {
		t.Fatalf("同层重复键未报错：%v", ds)
	}
}

func TestInvalidKeys(t *testing.T) {
	dir := t.TempDir()
	long := strings.Repeat("a", 129)
	writeConfigFile(t, dir, "application.properties",
		"Bad=1\na_b=1\na..b=1\n.a=1\na.=1\n"+long+"=1\n")
	spec := baseSpec()
	for _, k := range []string{"Bad", "a_b", "a..b", ".a", "a.", long} {
		spec.Keys[k] = KeySpec{Kind: KindString}
	}
	_, ds := Load(Options{
		ResourcesDir: dir, Packaging: "app",
		Builtin: map[string]string{"app.name": "svc"}, Spec: spec,
	})
	if n := countCode(ds, CodeKeyInvalid); n != 6 {
		t.Fatalf("非法键诊断数=%d，期望 6：%v", n, ds)
	}
}

func TestMissingRequiredKey(t *testing.T) {
	_, ds := Load(Options{
		Packaging: "app",
		Spec:      baseSpec(),
	})
	if !messageContains(ds, CodeMissingRequired, "app.name") {
		t.Fatalf("缺失必需键未点名：%v", ds)
	}
}

func TestTypeMismatch(t *testing.T) {
	dir := t.TempDir()
	writeConfigFile(t, dir, "application.properties", "net.http.listen-port=abc\nfeature.flag=yes\n")
	_, ds := Load(Options{
		ResourcesDir: dir, Packaging: "app",
		Builtin: map[string]string{"app.name": "svc"}, Spec: baseSpec(),
	})
	if n := countCode(ds, CodeTypeMismatch); n != 2 {
		t.Fatalf("类型错误诊断数=%d，期望 2：%v", n, ds)
	}
	for _, k := range []string{"net.http.listen-port", "feature.flag"} {
		if !messageContains(ds, CodeTypeMismatch, k) {
			t.Fatalf("类型错误未点名 %s：%v", k, ds)
		}
	}
	if !messageContains(ds, CodeTypeMismatch, "application.properties") {
		t.Fatalf("类型错误未含文件路径：%v", ds)
	}
}

func TestSecretLiteralsRejected(t *testing.T) {
	dir := t.TempDir()
	writeConfigFile(t, dir, "application.properties", "db.password=plain\n")
	_, ds := Load(Options{
		ResourcesDir: dir, Packaging: "app",
		Configuration: map[string]string{"api.token": "plain"},
		Builtin:       map[string]string{"app.name": "svc"},
		Spec: func() Spec {
			s := baseSpec()
			s.Keys["api.token"] = KeySpec{Kind: KindString}
			return s
		}(),
	})
	if n := countCode(ds, CodeSecretLiteral); n != 2 {
		t.Fatalf("疑似密钥诊断数=%d，期望 2：%v", n, ds)
	}
	if !messageContains(ds, CodeSecretLiteral, "db.password") ||
		!messageContains(ds, CodeSecretLiteral, "api.token") {
		t.Fatalf("密钥键未点名：%v", ds)
	}
}

func TestSecretPlaceholderAllowed(t *testing.T) {
	dir := t.TempDir()
	writeConfigFile(t, dir, "application.properties", "db.password=${DB_PASSWORD}\n")
	_, ds := Load(Options{
		ResourcesDir: dir, Packaging: "app",
		Builtin: map[string]string{"app.name": "svc"}, Spec: baseSpec(),
	})
	if hasCode(ds, CodeSecretLiteral) {
		t.Fatalf("占位值不应报密钥泄漏：%v", ds)
	}
}

func TestProfileMismatch(t *testing.T) {
	dir := t.TempDir()
	writeConfigFile(t, dir, "application-staging.properties", "db.url=x\n")
	_, ds := Load(Options{
		ResourcesDir: dir, Packaging: "app",
		Builtin: map[string]string{"app.name": "svc"}, Spec: baseSpec(),
	})
	if !messageContains(ds, CodeProfileMismatch, "staging") {
		t.Fatalf("profile 文件名不符未报错：%v", ds)
	}
}

func TestNonAppConfigRejected(t *testing.T) {
	dir := t.TempDir()
	writeConfigFile(t, dir, "application.properties", "db.url=x\n")
	_, ds := Load(Options{
		ResourcesDir: dir, Packaging: "library",
		Builtin: map[string]string{"app.name": "svc"}, Spec: baseSpec(),
	})
	if !hasCode(ds, CodeConfigPlacement) {
		t.Fatalf("非 app 出现 application.properties 未报错：%v", ds)
	}
}

func TestPropertiesCommentsAndHash(t *testing.T) {
	dir := t.TempDir()
	writeConfigFile(t, dir, "application.properties", "# comment\na = 1\nb=hello # trailing\nc=#only-comment\n")
	spec := Spec{Keys: map[string]KeySpec{
		"a": {Kind: KindString}, "b": {Kind: KindString}, "c": {Kind: KindString},
	}}
	res, ds := Load(Options{ResourcesDir: dir, Packaging: "app", Spec: spec})
	if len(ds) != 0 {
		t.Fatalf("不应有诊断：%v", ds)
	}
	if res.Values["a"] != "1" || res.Values["b"] != "hello" || res.Values["c"] != "" {
		t.Fatalf("注释/# 语义不符：%#v", res.Values)
	}
}

func TestParseCLIOverrides(t *testing.T) {
	m, ds := ParseCLIOverrides([]string{"--db.url=x=y", "--feature.flag=true", "--tool-flag", "--Bad=1"})
	if len(ds) != 1 || ds[0].Code != CodeKeyInvalid {
		t.Fatalf("非法 CLI 键诊断不符：%v", ds)
	}
	if m["db.url"] != "x=y" || m["feature.flag"] != "true" {
		t.Fatalf("CLI 解析不符：%#v", m)
	}
	if _, ok := m["tool-flag"]; ok {
		t.Fatalf("无 = 的工具参数不应进入配置：%#v", m)
	}
}

func TestConfigFileMustBeAtResourcesRoot(t *testing.T) {
	dir := t.TempDir()
	writeConfigFile(t, dir, "sub/application.properties", "db.url=x\n")
	_, ds := Load(Options{
		ResourcesDir: dir, Packaging: "app",
		Builtin: map[string]string{"app.name": "svc"}, Spec: baseSpec(),
	})
	if !messageContains(ds, CodeConfigPlacement, "资源根顶层") {
		t.Fatalf("子目录配置文件未报位置错误：%v", ds)
	}
}

func TestInvalidUTF8Rejected(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "application.properties"), []byte{0xff, 0xfe}, 0o644); err != nil {
		t.Fatal(err)
	}
	_, ds := Load(Options{
		ResourcesDir: dir, Packaging: "app",
		Builtin: map[string]string{"app.name": "svc"}, Spec: baseSpec(),
	})
	if !hasCode(ds, CodeFormat) {
		t.Fatalf("非法 UTF-8 未报格式错误：%v", ds)
	}
}
