#!/bin/bash
# CEO3-QA2 只读变异探针：在临时副本上跑，不触碰仓库。
set -u
TMP=/private/var/folders/zr/vyzqhmcn20ggrvrkdpblvchm0000gn/T/opencode/ceo3qa2-mut
REPO="$TMP/repo"
PRIST="$TMP/pristine"
IMPL="$REPO/impl"

mkdir -p "$PRIST/impl/internal/xfront" "$PRIST/impl/internal/devtool"
cp "$IMPL/internal/xfront/lexer.go" "$PRIST/impl/internal/xfront/lexer.go"
cp "$IMPL/internal/devtool/ledger.go" "$PRIST/impl/internal/devtool/ledger.go"
cp "$IMPL/internal/devtool/resources.go" "$PRIST/impl/internal/devtool/resources.go"

restore() {
  cp "$PRIST/impl/internal/xfront/lexer.go" "$IMPL/internal/xfront/lexer.go"
  cp "$PRIST/impl/internal/devtool/ledger.go" "$IMPL/internal/devtool/ledger.go"
  cp "$PRIST/impl/internal/devtool/resources.go" "$IMPL/internal/devtool/resources.go"
}

run_one() {
  id=$1; file=$IMPL/$2; from=$3; to=$4; pkg=$5; pattern=$6
  restore
  python3 - "$file" "$from" "$to" <<'PY'
import sys
p, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding='utf-8').read()
if s.count(a) != 1:
    print("MUTATION_NOT_UNIQUE:%d" % s.count(a)); sys.exit(9)
open(p, 'w', encoding='utf-8').write(s.replace(a, b, 1))
PY
  [ $? -ne 0 ] && { echo -e "$id\tMUTATION_APPLY_FAILED"; return; }
  ( cd "$IMPL" && go test ./internal/$pkg -count=1 -run "$pattern" -timeout 300s >"$TMP/$id.log" 2>&1 )
  rc=$?
  if [ $rc -eq 0 ]; then verdict=SURVIVED; else verdict=KILLED; fi
  echo -e "$id\t$verdict\trc=$rc\tpkg=$pkg"
}

run_one M1 internal/xfront/lexer.go "return func(r rune) bool { return r == '0' || r == '1' }" "return func(r rune) bool { return r >= '0' && r <= '2' }" xfront 'TestInteger|TestFloat'
run_one M2 internal/xfront/lexer.go "return r == 'L' || r == 'l' || r == 'U' || r == 'u'" "return r == 'L' || r == 'l'" xfront 'TestInteger|TestFloat'
run_one M3 internal/devtool/ledger.go 'if v.state == "PASS" {' 'if v.state != "" {' devtool 'TestBuildLedger'
run_one M4 internal/devtool/ledger.go 'if len(cells) < 3 {' 'if len(cells) < 2 {' devtool '.'
run_one M5 internal/devtool/resources.go 'entries[i].name < entries[j].name' 'entries[i].name > entries[j].name' devtool 'TestGenerateResources'

restore
echo "RESTORED"
