#!/bin/bash
# 董事会 M6-B0 第二波驱动器（B0-04/05/06）
set -u
ROOT=/Users/vjs/Desktop/XNull-Lang
BOARD="$ROOT/收件箱/CEO2/M6-B0第二波看板.md"
STATE=/tmp/m6b_driver_state
mkdir -p "$STATE" "$(dirname "$BOARD")"
OPENCODE=/usr/local/bin/opencode
PY=/usr/bin/python3

MAN="B0-04|ses_e4dc38cdfffeId2FW1ev64S7ED|收件箱/回执箱/CEO1/回执-M6-B0-04.md
B0-05|ses_e4e568d9bffe1XwhIi21Ec2s95|收件箱/回执箱/CEO1/回执-M6-B0-05.md
B0-06|ses_e4e56869dffeQ1DzIibbIVRZ9M|收件箱/回执箱/CEO3/验收-M6-B0-06.md"

deadline=$(( $(date +%s) + 12*3600 ))
while :; do
  now=$(date +%s)
  if [ "$now" -ge "$deadline" ]; then echo "T+12" >> "$STATE/log"; break; fi
  done_n=0; tmp="$STATE/board.tmp"; : > "$tmp"
  echo "# M6-B0 第二波看板（自动）" >> "$tmp"; echo "" >> "$tmp"
  echo "更新时间：$(date '+%H:%M:%S')" >> "$tmp"; echo "" >> "$tmp"
  echo "| 卡片 | 状态 | 会话 | 最近动作 |" >> "$tmp"; echo "|---|---|---|---|" >> "$tmp"
  while IFS='|' read -r card sid rcpt; do
    [ -z "$card" ] && continue
    f="$ROOT/$rcpt"
    if [ -f "$f" ] && grep -q 'DONE' "$f"; then state="DONE"; done_n=$((done_n+1)); else state="进行中"; fi
    busy=$("$OPENCODE" api GET "/api/session/$sid" 2>/dev/null | "$PY" -c '
import json,sys
try:
 d=json.load(sys.stdin).get("data")
 if isinstance(d,dict):
  t=d.get("time",{}); print("BUSY" if t.get("busy",0)>t.get("idle",0) else "IDLE")
 else: print("?")
except Exception: print("?")' 2>/dev/null)
    act="-"
    if [ "$state" != "DONE" ] && [ "$busy" = "IDLE" ]; then
      last=$(cat "$STATE/$card.last" 2>/dev/null || echo 0)
      if [ $((now-last)) -ge 600 ]; then
        msg="[M6-B0 auto] $card not done. Continue: red-first, smallest next step, update receipt $rcpt; if blocked write BLOCKED with support needed."
        "$OPENCODE" api POST "/api/session/$sid/prompt" -d "$("$PY" -c 'import json,sys;print(json.dumps({"text":sys.argv[1]}))' "$msg")" >/dev/null 2>&1
        echo "$now" > "$STATE/$card.last"; act="auto $(date +%H:%M)"
      else act="cooldown"; fi
    fi
    echo "| $card | $state | $busy | $act |" >> "$tmp"
  done <<< "$MAN"
  echo "" >> "$tmp"; echo "**DONE $done_n/3**" >> "$tmp"
  cp "$tmp" "$BOARD"; echo "$(date +%H:%M:%S) DONE=$done_n" >> "$STATE/log"
  [ "$done_n" -ge 3 ] && break
  sleep 120
done
echo "m6b exit $(date +%H:%M:%S)" >> "$STATE/log"
