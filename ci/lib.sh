#!/usr/bin/env bash
# ci/lib.sh — XNull CI 公共函数库
#
# 提供：步骤执行与计时（run_step/skip_step）、JSON 行输出（ci_json_line）、
#       可选颜色（默认关闭，不得依赖）、计数与汇总（ci_summary）。
# 兼容 macOS 自带 bash 3.2：不使用关联数组、nameref、${var,,} 等 4.x 语法。
# 本文件只被 ci/run.sh source，不单独执行。

CI_PASS=0
CI_FAIL=0
CI_SKIP=0
CI_ROWS=""            # 每步一行 JSON，末尾汇总时统一落盘
CI_OUT_DIR=${CI_OUT_DIR:-}
CI_VERBOSE=${CI_VERBOSE:-0}

# ---------- 颜色（可选，绝不被依赖） ----------
# 只有在 CI_COLOR=1 且 stdout 是终端时才着色；其余情况全部为空串。
ci_color_init() {
  CI_C_PASS=""; CI_C_FAIL=""; CI_C_SKIP=""; CI_C_OFF=""
  if [ "${CI_COLOR:-0}" = "1" ] && [ -t 1 ]; then
    CI_C_PASS=$(printf '\033[32m')
    CI_C_FAIL=$(printf '\033[31m')
    CI_C_SKIP=$(printf '\033[33m')
    CI_C_OFF=$(printf '\033[0m')
  fi
}

# ---------- 计时 ----------
# 毫秒时间戳；优先 python3，其次 perl，最后退回秒级（不影响判定）。
ci_now_ms() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import time;print(int(time.time()*1000))' 2>/dev/null && return 0
  fi
  if command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes=time -e 'printf "%d\n", time*1000' 2>/dev/null && return 0
  fi
  echo $(( $(date +%s) * 1000 ))
}

ci_elapsed_ms() {
  _now=$(ci_now_ms)
  echo $(( _now - $1 ))
}

# ---------- JSON ----------
# 单行化并转义，保证每个步骤只产生一个合法 JSON 行。
ci_json_escape() {
  printf '%s' "$1" | tr '\n\r\t' '   ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

ci_json_line() {
  # $1 step  $2 name  $3 status  $4 rc  $5 ms  $6 log  [$7 note]
  _line=$(printf '{"step":"%s","name":"%s","status":"%s","rc":%s,"ms":%s,"log":"%s","note":"%s"}' \
    "$(ci_json_escape "$1")" "$(ci_json_escape "$2")" "$(ci_json_escape "$3")" \
    "$4" "$5" "$(ci_json_escape "$6")" "$(ci_json_escape "${7:-}")")
  CI_ROWS="${CI_ROWS}${_line}
"
  if [ -n "$CI_OUT_DIR" ]; then
    printf '%s\n' "$_line" >> "$CI_OUT_DIR/steps.jsonl"
  fi
}

# ---------- 步骤执行 ----------
# run_step <step> <name> <workdir> <shell 片段>
# 片段在 workdir 下用 bash -c 执行；输出重定向到 step 日志，失败时回显尾部。
run_step() {
  _step=$1; _name=$2; _dir=$3; _cmd=$4
  _log=""
  if [ -n "$CI_OUT_DIR" ]; then
    _log="$CI_OUT_DIR/step-$_step.log"
  else
    _log=/dev/null
  fi
  _rs_start=$(ci_now_ms)
  printf '=== [%s] %s ===\n' "$_step" "$_name" > "$_log"
  printf '$ %s\n\n' "$_cmd" >> "$_log"

  if [ "$CI_VERBOSE" = "1" ]; then
    ( cd "$_dir" && bash -c "$_cmd" ) 2>&1 | tee -a "$_log"
    _rc=${PIPESTATUS[0]:-1}
    # bash 3.2 / zsh 兼容：上面取不到时退回子 shell 直跑
    if [ -z "${_rc:-}" ]; then _rc=1; fi
  else
    ( cd "$_dir" && bash -c "$_cmd" ) >> "$_log" 2>&1
    _rc=$?
  fi

  _ms=$(ci_elapsed_ms "$_rs_start")
  if [ "$_rc" -eq 0 ]; then
    CI_PASS=$((CI_PASS + 1))
    printf '%sPASS%s %s %-24s %6sms\n' "$CI_C_PASS" "$CI_C_OFF" "$_step" "$_name" "$_ms"
  else
    CI_FAIL=$((CI_FAIL + 1))
    printf '%sFAIL%s %s %-24s %6sms (rc=%s)\n' "$CI_C_FAIL" "$CI_C_OFF" "$_step" "$_name" "$_ms" "$_rc"
    if [ "$CI_VERBOSE" != "1" ] && [ "$_log" != "/dev/null" ]; then
      printf '  ---- 末尾 20 行（完整日志 %s）----\n' "$_log"
      tail -20 "$_log" | sed 's/^/  | /'
    fi
  fi
  ci_json_line "$_step" "$_name" "$([ "$_rc" -eq 0 ] && echo PASS || echo FAIL)" "$_rc" "$_ms" "$_log" ""
  return "$_rc"
}

# skip_step <step> <name> <原因>
skip_step() {
  _step=$1; _name=$2; _reason=$3
  CI_SKIP=$((CI_SKIP + 1))
  printf '%sSKIP%s %s %-24s %s\n' "$CI_C_SKIP" "$CI_C_OFF" "$_step" "$_name" "$_reason"
  ci_json_line "$_step" "$_name" "SKIP" "0" "0" "" "$_reason"
}

# ---------- 汇总 ----------
# ci_summary <开始毫秒>：打印汇总行并返回 CI 退出码
#   任一 FAIL      -> 1
#   无 PASS 只有 SKIP -> 2
#   其余（全 PASS）-> 0
ci_summary() {
  _total=$(ci_elapsed_ms "$1")
  printf '\n—— 汇总：PASS=%s FAIL=%s SKIP=%s，用时 %sms ——\n' \
    "$CI_PASS" "$CI_FAIL" "$CI_SKIP" "$_total"
  if [ "$CI_FAIL" -gt 0 ]; then
    _code=1
  elif [ "$CI_PASS" -eq 0 ] && [ "$CI_SKIP" -gt 0 ]; then
    _code=2
  else
    _code=0
  fi
  if [ -n "$CI_OUT_DIR" ]; then
    printf '{"type":"summary","pass":%s,"fail":%s,"skip":%s,"ms":%s,"exit":%s}\n' \
      "$CI_PASS" "$CI_FAIL" "$CI_SKIP" "$_total" "$_code" >> "$CI_OUT_DIR/steps.jsonl"
    printf '%s\n' "$CI_ROWS" > /dev/null
  fi
  printf '退出码：%s\n' "$_code"
  return "$_code"
}
