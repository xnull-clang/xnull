#!/usr/bin/env bash
# QA1-B1-03 同时复跑 ERR/PKG/TUPLE/ENTRY 现有验收，输出 FAIL 项清单。
# 只读 main；ERR 的 QA 测试用 go -overlay 临时注入，不改工作树。
set -uo pipefail

REPO=${REPO:-/Users/vjs/Desktop/XNull-Lang}
TMP=$(mktemp -d "${TMPDIR:-/tmp}/qa-acc.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# ERR：QA 独立用例（evidence/M1-ERR-01-qa）
cat >"$TMP/ov.json" <<EOF
{"Replace":{
 "$REPO/impl/internal/sema/qa_err01_accept_test.go":"$REPO/evidence/M1-ERR-01-qa/qa/qa-sema-test.go.txt",
 "$REPO/impl/internal/interp/qa_err01_accept_test.go":"$REPO/evidence/M1-ERR-01-qa/qa/qa-interp-test.go.txt"
}}
EOF

run() { # name workdir args...
    local name=$1 dir=$2; shift 2
    ( cd "$dir" && "$@" ) >"$TMP/$name.log" 2>&1
    echo "$name exit=$?"
}
cd "$REPO/impl" || exit 2
run err-sema "$REPO/impl" go test -overlay "$TMP/ov.json" ./internal/sema -run TestQAERR01 -count=1 -v
run err-interp "$REPO/impl" go test -overlay "$TMP/ov.json" ./internal/interp -run TestQAERR01 -count=1 -v
run pkg "$REPO/impl" go test ./internal/sema -run 'TestPkgImport|TestSymbolImport|TestAliasDisambiguation|TestNeedlessAliasRejected|TestAmbiguousSimpleName|TestXdkNotImportedStrict|TestImportCycle|TestImportTargetRules' -count=1 -v
run tuple "$REPO/impl" go test ./internal/sema ./internal/interp -run 'TestTuple' -count=1 -v
run entry-interp "$REPO/impl" go test ./internal/interp -run 'TestEntry' -count=1 -v
run entry-cli "$REPO/impl" go test ./internal/cli -run 'TestRunEntry' -count=1 -v
run entry-codegen "$REPO/impl" go test ./internal/codegen -run 'TestExamplesCompileMatchesInterp|TestMultiFile|TestLoadUnits|TestCompile|TestXdkSeed' -count=1 -v

echo
echo "FAIL 项清单（叶子用例；不含聚合父测试）："
grep -hE '^\s*--- FAIL: [^ ]+/' "$TMP"/*.log | sed 's/^[[:space:]]*/  /'
n=$(grep -hE '^\s*--- FAIL: [^ ]+/' "$TMP"/*.log | wc -l | tr -d ' ')
[ "$n" -eq 0 ] && n=$(grep -hE '^\s*--- FAIL: ' "$TMP"/*.log | wc -l | tr -d ' ')
echo "FAIL 总数=$n"
[ "$n" -eq 0 ] && exit 0 || exit 1
