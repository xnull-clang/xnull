#!/bin/bash
# M6-B1-03 实际差分运行（临时目录）
set -u
T=/private/var/folders/zr/vyzqhmcn20ggrvrkdpblvchm0000gn/T/opencode/b1-03
GO="$T/xnfmt-go"; XN="$T/xnfmt-xn"
CORPUS="$T/corpus"
LIST="$T/logs/files.txt"
cd /Users/vjs/Desktop/XNull-Lang
git ls-tree -r --name-only f63fcba | grep '\.x$' | LC_ALL=C sort > "$LIST"
N=$(wc -l < "$LIST" | tr -d ' ')
echo "corpus=$N"

R="$T/logs/results.tsv"; : > "$R"
MG="$T/logs/manifest-go.sha256"; MX="$T/logs/manifest-xn.sha256"; : > "$MG"; : > "$MX"

while IFS= read -r rel; do
  wd=$(mktemp -d "$T/work/f-XXXXXX")
  a="$wd/a.x"; b="$wd/b.x"; a2="$wd/a2.x"; b2="$wd/b2.x"
  cp "$CORPUS/$rel" "$a"; cp "$CORPUS/$rel" "$b"
  "$GO" "$a" >"$wd/go.out" 2>"$wd/go.err"; ge=$?
  "$XN" "$b" >"$wd/xn.out" 2>"$wd/xn.err"; xe=$?
  if [ $ge -ne 0 ] || [ $xe -ne 0 ]; then
    printf 'FAIL\t%s\tgo=%d xn=%d\t%s\n' "$rel" "$ge" "$xe" \
      "$(head -1 "$wd/go.err" | tr -d '\r')|$(head -1 "$wd/xn.err" | tr -d '\r')" >> "$R"
    rm -rf "$wd"; continue
  fi
  sg=$(shasum -a 256 "$a" | cut -d' ' -f1)
  sx=$(shasum -a 256 "$b" | cut -d' ' -f1)
  echo "$sg  $rel" >> "$MG"; echo "$sx  $rel" >> "$MX"
  if ! cmp -s "$a" "$b"; then
    printf 'DIFF\t%s\tsha_go=%s sha_xn=%s\n' "$rel" "$sg" "$sx" >> "$R"
    rm -rf "$wd"; continue
  fi
  cp "$a" "$a2"; cp "$b" "$b2"
  "$GO" "$a2" >/dev/null 2>&1 || true
  "$XN" "$b2" >/dev/null 2>&1 || true
  if ! cmp -s "$a" "$a2" || ! cmp -s "$b" "$b2"; then
    printf 'NONIDEM\t%s\tgo_same=%s xn_same=%s\n' "$rel" \
      "$(cmp -s "$a" "$a2" && echo yes || echo no)" \
      "$(cmp -s "$b" "$b2" && echo yes || echo no)" >> "$R"
    rm -rf "$wd"; continue
  fi
  printf 'OK\t%s\tsha=%s\n' "$rel" "$sg" >> "$R"
  rm -rf "$wd"
done < "$LIST"

ok=$(grep -c '^OK' "$R" || true)
diff=$(grep -c '^DIFF' "$R" || true)
fail=$(grep -c '^FAIL' "$R" || true)
non=$(grep -c '^NONIDEM' "$R" || true)
agg_go=$(shasum -a 256 "$MG" | cut -d' ' -f1)
agg_xn=$(shasum -a 256 "$MX" | cut -d' ' -f1)
echo "OK=$ok DIFF=$diff FAIL=$fail NONIDEM=$non"
echo "manifest_go=$agg_go manifest_xn=$agg_xn"
