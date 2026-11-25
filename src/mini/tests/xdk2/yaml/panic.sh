#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.yaml
import xdk.yaml
import xdk.codec
import xdk.errors

static Int main(String[] args) {
    String name = args.get(0)
    YamlOptions options = new YamlOptions()
    JsonValue value = Json.string("x")
    List<String> emptyProfiles = []
    if name == "parseNull" {
        Result<JsonValue, Error> result = Yaml.parse(null)
    } else if name == "parseOptionsNull" {
        Result<JsonValue, Error> result = Yaml.parseWithOptions("a: 1", null)
    } else if name == "parseTextNull" {
        Result<JsonValue, Error> result = Yaml.parseWithOptions(null, options)
    } else if name == "parseAllNull" {
        Result<List<YamlDocument>, Error> result = Yaml.parseAll(null)
    } else if name == "sourceNameNull" {
        Result<List<YamlPropertySource>, Error> result = Yaml.parsePropertySources(null, "a: 1")
    } else if name == "sourceTextNull" {
        Result<List<YamlPropertySource>, Error> result = Yaml.parsePropertySources("app", null)
    } else if name == "sourceNameEmpty" {
        Result<List<YamlPropertySource>, Error> result = Yaml.parsePropertySources("", "a: 1")
    } else if name == "stringifyNull" {
        Result<String, Error> result = Yaml.stringify(null)
    } else if name == "stringifyAllNull" {
        Result<String, Error> result = Yaml.stringifyAll(null)
    } else if name == "depthZero" {
        options.maxDepth(0)
    } else if name == "bytesZero" {
        options.maxBytes(0 as Long)
    } else if name == "documentsZero" {
        options.maxDocuments(0)
    } else if name == "aliasesNegative" {
        options.maxAliases(-1)
    } else if name == "profileNull" {
        options.profileKey(null)
    } else if name == "documentIndex" {
        YamlDocument document = new YamlDocument(-1, value, emptyProfiles)
    } else if name == "documentValue" {
        YamlDocument document = new YamlDocument(0, null, emptyProfiles)
    } else if name == "documentProfiles" {
        YamlDocument document = new YamlDocument(0, value, null)
    } else if name == "documentEmptyProfile" {
        List<String> profiles = [""]
        YamlDocument document = new YamlDocument(0, value, profiles)
    } else if name == "propertyName" {
        Map<String, String> properties = [:]
        YamlPropertySource source = new YamlPropertySource("", 0, emptyProfiles, properties)
    } else if name == "propertyProfiles" {
        Map<String, String> properties = [:]
        YamlPropertySource source = new YamlPropertySource("app", 0, null, properties)
    } else if name == "propertyMap" {
        YamlPropertySource source = new YamlPropertySource("app", 0, emptyProfiles, null)
    } else if name == "propertyKeyNull" {
        Map<String, String> properties = [:]
        YamlPropertySource source = new YamlPropertySource("app", 0, emptyProfiles, properties)
        String? result = source.getOrNull(null)
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || { cat "$TMP/build.err" >&2; exit 1; }
check_panic() {
    name=$1
    marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && { echo "yaml panic: $name did not fail" >&2; exit 1; }
    grep -Fq "$marker" "$TMP/$name.err" || { echo "yaml panic: $name missing '$marker'" >&2; cat "$TMP/$name.err" >&2; exit 1; }
}
check_panic parseNull "Yaml.parse: null argument"
check_panic parseOptionsNull "Yaml.parse: null argument"
check_panic parseTextNull "Yaml.parse: null argument"
check_panic parseAllNull "Yaml.parseAll: null argument"
check_panic sourceNameNull "Yaml.parsePropertySources: null argument"
check_panic sourceTextNull "Yaml.parsePropertySources: null argument"
check_panic stringifyNull "Yaml.stringify: null argument"
check_panic stringifyAllNull "Yaml.stringifyAll: null argument"
check_panic depthZero "YamlOptions.maxDepth: must be positive"
check_panic bytesZero "YamlOptions.maxBytes: must be positive"
check_panic documentsZero "YamlOptions.maxDocuments: must be positive"
check_panic aliasesNegative "YamlOptions.maxAliases: must be non-negative"
check_panic profileNull "YamlOptions.profileKey: null"
check_panic documentIndex "YamlDocument: negative index"
check_panic documentValue "YamlDocument: null value"
check_panic documentProfiles "YamlDocument: null profiles"
check_panic documentEmptyProfile "YamlDocument: empty profile"
check_panic propertyName "YamlPropertySource: empty name"
check_panic propertyProfiles "YamlPropertySource: null argument"
check_panic propertyMap "YamlPropertySource: null argument"
check_panic propertyKeyNull "YamlPropertySource.getOrNull: null key"
echo "yaml_panic: PASS"
