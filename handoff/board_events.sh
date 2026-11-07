#!/bin/bash
# 董事会事件桥：SSE 长连接 -> 会话完成事件 -> 推送到董事会
# 不做轮询；只订阅 /api/event，过滤 session.execution.*
set -u
ROOT=/Users/vjs/Desktop/XNull-Lang
BOARD=ses_e5064858fffebRYkY6Gr2xlCPu
SERVICE=http://127.0.0.1:49374
PASS=$(/usr/bin/python3 -c 'import json;print(json.load(open("/Users/vjs/.config/opencode/service.json"))["password"])')
OPENCODE=/usr/local/bin/opencode
PY=/usr/bin/python3
LOG="$ROOT/收件箱/告警/events.log"
mkdir -p "$ROOT/收件箱/告警"
touch "$LOG"

line_of() {
  case "$1" in
    ses_e4e5694b8ffeoV3oj9y77xkwfK) echo "前端线/E2" ;;
    ses_e4e569129ffeGB5tOMcNlJXwAs) echo "前端线支援/E3" ;;
    ses_e4b31fb05ffeFzVjC1mO6ORCtF) echo "自举线/E4" ;;
    ses_e4e568a1effejGcw2Ap4Y2oxMv) echo "运行时线/E5" ;;
    ses_e4e17eaa3ffe9Pijn8543mwLab) echo "自举线执行/E6" ;;
    ses_e4b40f4a3ffesv79t1JcZwI9Xt) echo "QA线/QA1" ;;
    ses_e4e569b96ffeQvES2WO0T2Dbr4) echo "发布线/COO" ;;
    *) echo "" ;;
  esac
}

echo "$(date '+%F %T') bridge started" >> "$LOG"
/usr/bin/curl -sN -u "opencode:$PASS" "$SERVICE/api/event" | while IFS= read -r line; do
  case "$line" in
    data:*) json="${line#data: }" ;;
    *) continue ;;
  esac
  parsed=$("$PY" -c '
import json,sys
try:
 d=json.loads(sys.argv[1])
 t=d.get("type","")
 sid=(d.get("data") or {}).get("sessionID","")
 if t in ("session.execution.succeeded","session.execution.failed","session.execution.interrupted"):
  print(t, sid)
except Exception: pass
' "$json" 2>/dev/null)
  [ -z "$parsed" ] && continue
  type=${parsed%% *}; sid=${parsed##* }
  who=$(line_of "$sid")
  [ -z "$who" ] && continue
  now=$(date +%s)
  lastf="/tmp/board_evt_$sid"
  last=$(cat "$lastf" 2>/dev/null || echo 0)
  [ $((now-last)) -lt 30 ] && continue
  echo "$now" > "$lastf"
  msg="[EVENT] $who ${type#session.execution.} $sid — 读 handoff/ 最新接力棒与回执；完成则验收/接下一棒。"
  body=$("$PY" -c 'import json,sys;print(json.dumps({"text":sys.argv[1]}))' "$msg")
  "$OPENCODE" api POST "/api/session/$BOARD/prompt" -d "$body" >/dev/null 2>&1
  echo "$(date '+%F %T') $type $sid $who" >> "$LOG"
done
echo "$(date '+%F %T') bridge exited" >> "$LOG"
