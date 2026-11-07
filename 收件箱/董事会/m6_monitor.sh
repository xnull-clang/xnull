#!/bin/bash
# 董事会 M6-B0 实时驱动器（董事会专用，不进产品、不提交）
# 每 120 秒检查 B0 回执；空闲且未完成则自动续跑；全部 DONE/BLOCKED 或 T+12 退出
set -u
ROOT=/Users/vjs/Desktop/XNull-Lang
BOARD="$ROOT/收件箱/CEO2/M6-B0实时看板.md"
STATE=/tmp/m6_driver_state
mkdir -p "$STATE" "$(dirname "$BOARD")"
OPENCODE=/usr/local/bin/opencode
PY=/usr/bin/python3

MAN="B0-01|ses_e4e568d9bffe1XwhIi21Ec2s95|收件箱/回执箱/CEO1/回执-M6-B0-01.md
B0-02|ses_e4e17eaa3ffe9Pijn8543mwLab|收件箱/回执箱/CEO3/回执-M6-B0-02.md
B0-05|ses_e4e569129ffeGB5tOMcNlJXwAs|收件箱/回执箱/CEO3/回执-M6-B0-05.md
B0-06|ses_e4e56869dffeQ1DzIibbIVRZ9M|收件箱/回执箱/CEO3/验收-M6-B0-06.md"

deadline=$(( $(date +%s) + 12*3600 ))
while :; do
  now=$(date +%s)
  if [ "$now" -ge "$deadline" ]; then echo "T+12 reached" >> "$STATE/log"; break; fi
  done_n=0; blocked_n=0; tmp="$STATE/board.tmp"; : > "$tmp"
  echo "# M6-B0 实时看板（自动，每 120s）" >> "$tmp"
  echo "" >> "$tmp"
  echo "更新时间：$(date '+%Y-%m-%d %H:%M:%S %Z')　B0 截止：T+12" >> "$tmp"
  echo "" >> "$tmp"
  echo "| 卡片 | 状态 | 会话 | 回执 | 最近动作 |" >> "$tmp"
  echo "|---|---|---|---|---|" >> "$tmp"
  while IFS='|' read -r card sid rcpt; do
    [ -z "$card" ] && continue
    f="$ROOT/$rcpt"
    if [ -f "$f" ]; then
      if grep -q 'BLOCKED' "$f"; then
        state="BLOCKED"; blocked_n=$((blocked_n+1))
      elif grep -q 'DONE' "$f"; then
        state="DONE"; done_n=$((done_n+1))
      else
        state="进行中"
      fi
    else
      state="无回执"
    fi
    busy=$("$OPENCODE" api GET "/api/session/$sid" 2>/dev/null | "$PY" -c '
import json,sys
try:
 d=json.load(sys.stdin).get("data")
 if isinstance(d,dict):
  t=d.get("time",{}); print("BUSY" if t.get("busy",0)>t.get("idle",0) else "IDLE")
 else: print("?")
except Exception: print("?")' 2>/dev/null)
    act="-"
    if [ "$state" != "DONE" ] && [ "$state" != "BLOCKED" ] && [ "$busy" = "IDLE" ]; then
      last=$(cat "$STATE/$card.last" 2>/dev/null || echo 0)
      if [ $((now-last)) -ge 600 ]; then
        msg="[M6-B0 auto] $card not done. Continue per v1.9.0: red-first, smallest next step, update receipt $rcpt; if blocked write BLOCKED with needed support."
        "$OPENCODE" api POST "/api/session/$sid/prompt" -d "$("$PY" -c 'import json,sys;print(json.dumps({"text":sys.argv[1]}))' "$msg")" >/dev/null 2>&1
        echo "$now" > "$STATE/$card.last"
        act="auto-continue $(date +%H:%M)"
      else
        act="cooldown"
      fi
    fi
    echo "| $card | $state | $busy | $(basename "$f") | $act |" >> "$tmp"
  done <<< "$MAN"
  echo "" >> "$tmp"
  echo "**统计：DONE $done_n/4，BLOCKED $blocked_n/4**" >> "$tmp"
  cp "$tmp" "$BOARD"
  echo "$(date '+%H:%M:%S') DONE=$done_n BLOCKED=$blocked_n" >> "$STATE/log"
  [ $((done_n+blocked_n)) -ge 4 ] && break
  sleep 120
done
echo "m6 driver exit: $(date '+%H:%M:%S')" >> "$STATE/log"
