#!/bin/bash
# 15 分钟进度定时器：到点把四数推给董事会，并写日志
set -u
ROOT=/Users/vjs/Desktop/XNull-Lang
BOARD=ses_e5064858fffebRYkY6Gr2xlCPu
OPENCODE=/usr/local/bin/opencode
PY=/usr/bin/python3
LOG="$ROOT/收件箱/告警/timer-15m.log"
mkdir -p "$ROOT/收件箱/告警"
echo "$$" > /tmp/timer_15m.pid
echo "$(date '+%F %T') timer started (900s)" >> "$LOG"

while :; do
  sleep 900
  NOW=$(date '+%F %T')
  SINCE=$(date -v-15M '+%Y-%m-%d %H:%M:%S')
  cd "$ROOT" || exit 1
  COMMITS=$(git log --since="$SINCE" --oneline --all 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')
  PASS=$(/usr/bin/grep -c 'PASS' impl/docs/conformance/status.tsv 2>/dev/null || echo '?')
  BUSY=$("$OPENCODE" api GET /api/session 2>/dev/null | "$PY" -c '
import json,sys
try:
 d=json.load(sys.stdin).get("data",[])
 n=0
 for s in d:
  t=s.get("time",{})
  if t.get("busy",0)>t.get("idle",0): n+=1
 print(n)
except Exception: print("?")' 2>/dev/null)
  TOP=$(git log --since="$SINCE" --oneline --all 2>/dev/null | /usr/bin/head -3 | /usr/bin/tr '\n' '; ')
  {
    echo ""
    echo "## ${NOW}"
    echo "- window: ${SINCE} -> now"
    echo "- commits: ${COMMITS}"
    echo "- status.tsv PASS rows: ${PASS}"
    echo "- busy sessions: ${BUSY}"
    echo "- recent: ${TOP}"
  } >> "$LOG"
  MSG="[TIMER 15m] ${NOW} | commits +${COMMITS} | status.tsv PASS=${PASS} | busy=${BUSY} | recent: ${TOP} | log: 收件箱/告警/timer-15m.log"
  BODY=$("$PY" -c 'import json,sys;print(json.dumps({"text":sys.argv[1]}))' "$MSG")
  "$OPENCODE" api POST "/api/session/${BOARD}/prompt" -d "$BODY" >/dev/null 2>&1
  echo "${NOW} pushed" >> "$LOG"
done
