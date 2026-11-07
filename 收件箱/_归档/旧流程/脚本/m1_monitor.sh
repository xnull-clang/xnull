#!/bin/bash
# 董事会 M1 实时驱动器（仅董事会使用；不进入产品、不提交）
# 每 120 秒：读 8 锚点回执 -> 判 DONE/BLOCKED/进行中 -> 对 idle 且未完成者自动续跑 -> 写实时看板
# 全部 DONE/BLOCKED 或到 T+16 退出（退出会通知董事会）
set -u
ROOT=/Users/vjs/Desktop/XNull-Lang
BOARD=$ROOT/收件箱/CEO2/M1实时看板.md
STATE=/tmp/m1_driver_state
mkdir -p "$STATE" "$(dirname "$BOARD")"
OPENCODE=/usr/local/bin/opencode

MAN="ERR-01|ses_e4dc38fe7ffe9ixnueVA93u852|.|收件箱/回执箱/CEO1/回执-M1-ERR-01.md
GEN-01|ses_e4dc38cdfffeId2FW1ev64S7ED|.|收件箱/回执箱/CEO1/回执-M1-GEN-01.md
PKG-01|ses_e4dc393beffeuAplNJjn5kav2D|.|收件箱/回执箱/CEO1/回执-M1-PKG-01.md
TUPLE-01|ses_e4e5694b8ffeoV3oj9y77xkwfK|.|收件箱/回执箱/CEO1/回执-M1-TUPLE-01.md
ENTRY-01|ses_e4e568d9bffe1XwhIi21Ec2s95|.|收件箱/回执箱/CEO1/回执-M1-ENTRY-01.md
BLD-01|ses_e4dc37977ffekR6zGlJ10AqQ8S|.|收件箱/回执箱/CEO2/回执-M1-BLD-01.md
DET-01|ses_e4dc36301ffemsFvWum1EdDnbY|.|收件箱/回执箱/CEO3/回执-M1-DET-01.md
NEG-01|ses_e4dc35fccffeu5H7knH1Outu0p|.|收件箱/回执箱/CEO3/回执-M1-NEG-01.md"

deadline=$(( $(date +%s) + 16*3600 ))
while :; do
  now=$(date +%s); [ "$now" -ge "$deadline" ] && { echo "T+16 reached" >> "$STATE/log"; break; }
  done_n=0; blocked_n=0; board_tmp="$STATE/board.tmp"; : > "$board_tmp"
  echo "# M1 实时看板（自动，每 120s）" >> "$board_tmp"
  echo "" >> "$board_tmp"
  echo "更新时间：$(date '+%Y-%m-%d %H:%M:%S %Z')　截止：T+16 = 19:30" >> "$board_tmp"
  echo "" >> "$board_tmp"
  echo "| 锚点 | 状态 | 会话 | 回执 | 最近动作 |" >> "$board_tmp"
  echo "|---|---|---|---|---|" >> "$board_tmp"
  while IFS='|' read -r anchor sid wt receipt; do
    [ -z "$anchor" ] && continue
    f="$ROOT/$wt/$receipt"
    [ -f "$f" ] || f="$ROOT/$receipt"
    qf=$(ls "$ROOT"/收件箱/CEO*/验收-M1-$anchor.md 2>/dev/null | head -1)
    qa="待验"
    if [ -n "$qf" ]; then
      if grep -qE '结论[^。]*PASS|PASS$' "$qf"; then qa="PASS"; done_n=$((done_n+1)); else qa="FAIL/部分"; fi
    fi
    if [ -f "$f" ]; then
      if grep -q 'BLOCKED' "$f"; then state="BLOCKED"; blocked_n=$((blocked_n+1));
      elif grep -qE '状态[^｜|]*DONE|检查表 *[0-9]+/[0-9]+|全绿|全 PASS' "$f"; then state="待验";
      else state="进行中"; fi
    else state="无回执"; fi
    state="$state / QA:$qa"
    busy=$("$OPENCODE" api GET "/api/session/$sid" 2>/dev/null | python3 -c '
import json,sys
try:
 d=json.load(sys.stdin).get("data")
 if isinstance(d,dict):
  t=d.get("time",{}); print("BUSY" if t.get("busy",0)>t.get("idle",0) else "IDLE")
 else: print("?")
except Exception: print("?")' 2>/dev/null)
    act="—"
    if [ "$state" = "进行中" ] && [ "$busy" = "IDLE" ]; then
      last=$(cat "$STATE/$anchor.last" 2>/dev/null || echo 0)
      if [ $((now-last)) -ge 600 ]; then
        msg="【自动续跑·M1】$anchor 回执未标 DONE/BLOCKED。读你的回执与检查表，完成最小下一项并更新回执；若仍阻塞，写 BLOCKED 并列出需要哪个域支援。不要停在半路，不要改测试期望。"
        "$OPENCODE" api POST "/api/session/$sid/prompt" -d "$(python3 -c 'import json,sys;print(json.dumps({"text":sys.argv[1]}))' "$msg")" >/dev/null 2>&1
        echo "$now" > "$STATE/$anchor.last"; act="已自动续跑 $(date +%H:%M)"
      else act="冷却中"; fi
    fi
    echo "| $anchor | $state | $busy | $(basename "$f") | $act |" >> "$board_tmp"
  done <<< "$MAN"
  echo "" >> "$board_tmp"
  official=$((6+done_n))
  echo "**统计：QA PASS $done_n/8，BLOCKED $blocked_n/8，官方 M1 = $official/14**" >> "$board_tmp"
  echo "" >> "$board_tmp"
  echo "## 基础设施任务（人工维护状态）" >> "$board_tmp"
  echo "" >> "$board_tmp"
  echo "| 项 | 主责 | 状态 | 截止 |" >> "$board_tmp"
  echo "|---|---|---|---|" >> "$board_tmp"
  echo "| Stage 0 tag | CEO2 | 未开始 | T+3 |" >> "$board_tmp"
  echo "| 干净 clone 复现 | COO | 待 tag 后重跑 | T+3 |" >> "$board_tmp"
  echo "| ERR-005 关闭复核 | CEO3 | 进行中 | T+3 |" >> "$board_tmp"
  echo "| 条款 ID 生成器 S1 | E6 | 未开始 | T+8 |" >> "$board_tmp"
  echo "| 台账三列 | E6 | 未开始 | T+8 |" >> "$board_tmp"
  echo "| CI 04–09 真实现 | E6 | SKIP 桩 | T+12 |" >> "$board_tmp"
  echo "| CI 10 文件扫描 | E6 | 已完成 65e7dd4 | — |" >> "$board_tmp"
  echo "| 9 个研发 worktree | E6 | 已完成 S0-28 | — |" >> "$board_tmp"
  cp "$board_tmp" "$BOARD"
  cp "$board_tmp" "$ROOT/收件箱/董事会判决-任务列表-实时.md"
  echo "$(date '+%H:%M:%S') DONE=$done_n BLOCKED=$blocked_n" >> "$STATE/log"
  [ $((done_n+blocked_n)) -ge 8 ] && break
  sleep 120
done
echo "driver exit: $(date '+%H:%M:%S')" >> "$STATE/log"
