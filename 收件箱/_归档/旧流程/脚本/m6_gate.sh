#!/bin/bash
# 董事会 M6 门级自动驾驶：B0 -> B1-00 -> B1；到 B2 冻结前置时退出并告警
set -u
ROOT=/Users/vjs/Desktop/XNull-Lang
STATE=/tmp/m6_gate_state
LOG=/tmp/m6_gate.log
OPENCODE=/usr/local/bin/opencode
PY=/usr/bin/python3
touch "$LOG"

get_state() { cat "$STATE" 2>/dev/null || echo B0; }
set_state() { echo "$1" > "$STATE"; }
has_done() { [ -f "$ROOT/$1" ] && grep -qE 'DONE|PASS' "$ROOT/$1"; }
is_idle() {
  "$OPENCODE" api GET "/api/session/$1" 2>/dev/null | "$PY" -c '
import json,sys
try:
 d=json.load(sys.stdin).get("data")
 t=d.get("time",{}) if isinstance(d,dict) else {}
 print("IDLE" if d and t.get("idle",0)>=t.get("busy",0) else "BUSY")
except Exception: print("?")' 2>/dev/null
}
kick() {
  local sid="$1" msg="$2" tag="$3"
  [ "$(is_idle "$sid")" = "IDLE" ] || return 0
  local lastf="/tmp/m6_gate_$tag.last" last
  last=$(cat "$lastf" 2>/dev/null || echo 0)
  [ $(( $(date +%s) - last )) -ge 600 ] || return 0
  "$OPENCODE" api POST "/api/session/$sid/prompt" -d "$("$PY" -c 'import json,sys;print(json.dumps({"text":sys.argv[1]}))' "$msg")" >/dev/null 2>&1
  echo "$(date +%s)" > "$lastf"
}

while :; do
  phase=$(get_state)
  echo "$(date '+%H:%M:%S') phase=$phase" >> "$LOG"
  case "$phase" in
    B0)
      ok=1
      for f in \
        收件箱/回执箱/CEO1/回执-M6-B0-01.md \
        收件箱/回执箱/CEO3/回执-M6-B0-02.md \
        收件箱/回执箱/CEO1/回执-M6-B0-03.md \
        收件箱/回执箱/CEO1/回执-M6-B0-04.md \
        收件箱/回执箱/CEO1/回执-M6-B0-05.md \
        收件箱/回执箱/CEO3/验收-M6-B0-06.md ; do
        has_done "$f" || ok=0
      done
      if [ "$ok" = "1" ]; then
        ( cd "$ROOT/impl" && go test ./... -count=1 -timeout 300s > /tmp/m6_b0_test.out 2>&1 )
        rc=$?
        if [ "$rc" = "0" ]; then
          {
            echo "# M6-B0 门（自动驾驶）"
            echo ""
            echo "- 时间：$(date '+%Y-%m-%d %H:%M:%S')"
            echo "- 六卡回执：齐全"
            echo "- go test ./...：exit 0"
            echo "- 结论：PASS"
          } > "$ROOT/收件箱/CEO2/M6-B0门.md"
          kick ses_e4dc35cb7ffeTq6StaqG0yiba6 "【M6-B1-00】B0 门已通过。读 收件箱/董事会/cards/B1-00.txt 并执行：定义 xnfmt 格式化规范，写 收件箱/CEO3/格式化规范-v1.0.0.md，回执 收件箱/回执箱/CEO3/规范-M6-B1-00.md。" B1-00
          set_state B1-00
        else
          echo "B0 test failed rc=$rc" >> "$LOG"; exit 2
        fi
      else
        kick ses_e4e568d9bffe1XwhIi21Ec2s95 "[M6-B0] B0-03 cross-package import still not done. Continue: merge main, implement multifile import, red-first, update 收件箱/回执箱/CEO1/回执-M6-B0-03.md." B0-03
      fi
      ;;
    B1-00)
      if grep -q 'DONE' "$ROOT/收件箱/回执箱/CEO3/规范-M6-B1-00.md" 2>/dev/null; then
        kick ses_e4e17eaa3ffe9Pijn8543mwLab "【M6-B1-01】读 收件箱/董事会/cards/B1-01.txt：实现 Go 版 xnfmt oracle，按规范，回执 收件箱/回执箱/CEO3/回执-M6-B1-01.md。" B1-01
        kick ses_e4dc36630ffeNuaOuTsM5oolJW "【M6-B1-02】读 收件箱/董事会/cards/B1-02.txt：用 XNull 写 xnfmt，与 Go 版逐字节一致，回执 收件箱/回执箱/CEO3/回执-M6-B1-02.md。" B1-02
        kick ses_e4dc3535bffemLX0lyQt6HsRRW "【M6-B1-03】读 收件箱/董事会/cards/B1-03.txt：建 xnfmt 差分验收，回执 收件箱/回执箱/CEO3/验收-M6-B1-03.md。" B1-03
        set_state B1
      else
        kick ses_e4dc35cb7ffeTq6StaqG0yiba6 "[M6-B1-00] xnfmt 规范仍未交。写 收件箱/CEO3/格式化规范-v1.0.0.md 与回执 收件箱/回执箱/CEO3/规范-M6-B1-00.md。" B1-00
      fi
      ;;
    B1)
      ok=1
      for f in \
        收件箱/回执箱/CEO3/回执-M6-B1-01.md \
        收件箱/回执箱/CEO3/回执-M6-B1-02.md \
        收件箱/回执箱/CEO3/验收-M6-B1-03.md ; do
        has_done "$f" || ok=0
      done
      if [ "$ok" = "1" ]; then
        {
          echo "# M6-B1 门（自动驾驶）"
          echo ""
          echo "- 时间：$(date '+%Y-%m-%d %H:%M:%S')"
          echo "- xnfmt Go/XNull/差分：三份回执齐全"
          echo "- 结论：PASS（待 QA 复核差异数=0）"
          echo "- 下一门 B2：被死命令 1.5.2 语义冻结阻塞，需 S1–S8 定版与全量验收"
        } > "$ROOT/收件箱/CEO2/M6-B1门.md"
        echo "B2 blocked by semantic freeze" >> "$LOG"
        set_state B2-WAIT
        exit 0
      else
        kick ses_e4e17eaa3ffe9Pijn8543mwLab "[M6-B1] B1-01 still pending; update receipt." B1-01
        kick ses_e4dc36630ffeNuaOuTsM5oolJW "[M6-B1] B1-02 still pending; update receipt." B1-02
        kick ses_e4dc3535bffemLX0lyQt6HsRRW "[M6-B1] B1-03 still pending; update receipt." B1-03
      fi
      ;;
    *)
      echo "state $phase, nothing to do" >> "$LOG"; exit 0
      ;;
  esac
  sleep 120
done
