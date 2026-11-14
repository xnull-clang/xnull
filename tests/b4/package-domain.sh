#!/usr/bin/env bash
# 包域垂直验收：解析器单测、真实 CLI、XDK 类文件聚合与聚焦编译运行。
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
XP="$ROOT/bootstrap/bin/xparser"
XN="$ROOT/bootstrap/bin/xn-s4"
[ -x "$XP" ] && [ -x "$XN" ] || { echo "缺少 bootstrap/bin/{xparser,xn-s4}" >&2; exit 1; }

python3 "$HERE/package_resolver_test.py"

python3 - "$ROOT" <<'PY'
import os
import re
import sys

root = sys.argv[1]
lib = os.path.join(root, "impl/lib")
assert sorted(n for n in os.listdir(lib) if not n.startswith(".")) == ["xdk"], os.listdir(lib)
xdk = os.path.join(root, "impl/lib/xdk")
assert not [n for n in os.listdir(xdk) if n.endswith(".x")], "xdk 根目录不得有 .x 文件"
layers = sorted(n for n in os.listdir(xdk)
                if os.path.isdir(os.path.join(xdk, n)) and not n.startswith("."))
assert layers == ["build", "compiler", "concurrent", "core", "data", "io", "net", "text", "util"], layers
for layer in layers:
    assert layer == layer.lower(), layer
    for domain in sorted(os.listdir(os.path.join(xdk, layer))):
        path = os.path.join(xdk, layer, domain)
        if not os.path.isdir(path) or domain.startswith("."):
            continue
        assert domain.isalpha() and "_" not in domain, domain
        assert domain == domain.lower(), domain
for dirpath, dirs, files in os.walk(xdk):
    for name in files:
        if name.endswith(".x"):
            path = os.path.join(dirpath, name)
            assert name[0].isupper(), path
            text = open(path, encoding="utf-8").read()
            assert not re.search(r"\bB[2-5]\b|\bQ3\b", text), path
print("PASS xdk-layout")
PY

run_cli() {
  local name=$1 entry=$2 expected=$3 actual
  actual=$(cd "$ROOT" && bin/xnull --bootstrap run "$entry")
  if [ "$actual" != "$expected" ]; then
    printf 'FAIL %s\n' "$name" >&2
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") >&2 || true
    exit 1
  fi
  echo "PASS $name"
}
run_cli package-class-import tests/b4/package-domain/main.x "8"
run_cli legacy-package-import examples/multi/main.x $'[xnull]\n25\n[norm=25]'

W=$(mktemp -d "${TMPDIR:-/tmp}/xnull-package-domain.XXXXXX")
trap 'rm -rf "$W"' EXIT
python3 "$HERE/xdk-bundle.py" "$ROOT" "$ROOT/tests/s6/xdk-source/package_duration.x" "$W" >/dev/null
python3 - "$ROOT" "$W" <<'PY'
import json
import os
import subprocess
import sys

root, work = sys.argv[1:]
bundle = json.load(open(os.path.join(work, "bundle.json"), encoding="utf-8"))
assert len(bundle["files"]) == 14, len(bundle["files"])
time_slot = next(slot for slot in bundle["files"]
                 if slot["path"].endswith("/impl/lib/xdk/core/time/Time.x"))
assert time_slot["ast"].count('(Name "Duration")') >= 1
codec_slot = next(slot for slot in bundle["files"]
                  if slot["path"].endswith("/impl/lib/xdk/data/codec/Codec.x"))
assert codec_slot["ast"].count("(ClassDecl ") == 6, codec_slot["ast"].count("(ClassDecl ")
for name in ("CsvRow", "CsvTable", "JsonValue", "JsonParser",
             "BinaryReader", "BinaryWriter"):
    assert '(Name "%s")' % name in codec_slot["ast"], name
print("PASS xdk-codec-package-aggregation")
entry = bundle["files"][-1]
open(os.path.join(work, "selective.ast"), "w", encoding="utf-8").write(entry["ast"])
duration_path = os.path.join(root, "impl/lib/xdk/core/time/Duration.x")
duration_ast = subprocess.run(
    [os.path.join(root, "bootstrap/bin/xparser"), "--file", duration_path],
    cwd=root, capture_output=True, text=True, check=True).stdout
json.dump({"version": "xnast-bundle v1", "files": [
    {"path": duration_path, "ast": duration_ast}, entry]},
    open(os.path.join(work, "selective.json"), "w", encoding="utf-8"))
legacy_entry_path = os.path.join(root, "tests/s6/xdk-source/package_duration_legacy.x")
legacy_ast = subprocess.run(
    [os.path.join(root, "bootstrap/bin/xparser"), "--file", legacy_entry_path],
    cwd=root, capture_output=True, text=True, check=True).stdout
open(os.path.join(work, "legacy.ast"), "w", encoding="utf-8").write(legacy_ast)
json.dump({"version": "xnast-bundle v1", "files": [
    time_slot, {"path": legacy_entry_path, "ast": legacy_ast}]},
    open(os.path.join(work, "legacy.json"), "w", encoding="utf-8"))
print("PASS xdk-time-package-aggregation")
PY

RUNTIME_SRCS=(
  rt.c rt_gc.c rt_policy.c rt_weak.c xrt_abi.c
  rt_std_runtime.c rt_std_text.c rt_std_sys.c rt_std_bytes.c rt_std_net.c
  rt_task.c rt_sync.c rt_std_res.c rt_std_res_empty.c rt_std_ext.c
)
build_focused() {
  local name=$1 entry=$2 project=$3 expected=$4
  local sources=() src
  for src in "${RUNTIME_SRCS[@]}"; do sources+=("$ROOT/impl/runtime/$src"); done
  (cd "$ROOT" && "$XN" "$entry" --ast-file "$W/$name.ast" \
    --bundle-file "$W/$name.json" --project "$project") > "$W/$name.c"
  cc -std=c11 -O2 -pthread -I "$ROOT/impl/runtime" -o "$W/$name.bin" \
    "$W/$name.c" "${sources[@]}" "$ROOT/bootstrap/bin/res.c" -lz
  "$W/$name.bin" > "$W/$name.out"
  diff -u "$expected" "$W/$name.out"
  echo "PASS xdk-time-$name"
}
# 聚焦 time 包，隔离全量 XDK 已存在的跨包 codegen 越界；完整套件仍由 tests/s6/xdk-source/run.sh 执行。
build_focused selective tests/s6/xdk-source/package_duration.x "" \
  "$ROOT/tests/s6/xdk-source/package_duration.expect"
# legacy 全 time 包含既有 DateTime.format C 发射缺口，本步骤只验证聚合后的 codegen 不崩溃。
(cd "$ROOT" && "$XN" tests/s6/xdk-source/package_duration_legacy.x \
  --ast-file "$W/legacy.ast" --bundle-file "$W/legacy.json" \
  --project "$(cat "$W/project.txt")") > "$W/legacy.c"
echo "PASS xdk-time-legacy-codegen"
