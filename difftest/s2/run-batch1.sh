#!/bin/sh
# S2 QA batch 1: BND-01 / BND-05 / PCTOR-01 (fixtures only; no production code)
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
X=${XNULL:-/tmp/xnull-s2}
export XNULL_RUNTIME=${XNULL_RUNTIME:-/private/tmp/qa-s2-f975810/impl/runtime}
EV="$ROOT/evidence/S2-QA"
mkdir -p "$EV"

run_pos() {
  anchor=$1; case=$2; file=$3
  d="$EV/$anchor/$case"; mkdir -p "$d"
  {
    echo "X=$X"; echo "file=$file"; echo "runtime=$XNULL_RUNTIME"; echo "sha=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)"
  } > "$d/cmd.txt"
  "$X" run --interp "$file" > "$d/interp.out" 2> "$d/interp.err"; echo $? > "$d/interp.exit"
  "$X" run "$file" > "$d/compiled.out" 2> "$d/compiled.err"; echo $? > "$d/compiled.exit"
  printf '%s\t%s\tinterp_rc=%s\tcompiled_rc=%s\tinterp=%s\tcompiled=%s\n' \
    "$anchor" "$case" "$(cat "$d/interp.exit")" "$(cat "$d/compiled.exit")" \
    "$(tr '\n' '|' < "$d/interp.out")" "$(tr '\n' '|' < "$d/compiled.out")" >> "$EV/matrix.tsv"
}

run_neg() {
  anchor=$1; case=$2; file=$3
  d="$EV/$anchor/$case"; mkdir -p "$d"
  {
    echo "X=$X"; echo "file=$file"; echo "sha=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)"
  } > "$d/cmd.txt"
  "$X" check "$file" > "$d/check.out" 2> "$d/check.err"; echo $? > "$d/check.exit"
  printf '%s\t%s\tcheck_rc=%s\terr=%s\n' \
    "$anchor" "$case" "$(cat "$d/check.exit")" "$(tr '\n' '|' < "$d/check.err")" >> "$EV/matrix.tsv"
}

: > "$EV/matrix.tsv"

# BND-01
run_pos BND-01 A01 difftest/s2/bnd01/a01_member_visibility.x
run_pos BND-01 A02 difftest/s2/bnd01/a02_protected_subclass.x
run_neg BND-01 R01 difftest/s2/bnd01/r01_private_outside.x
run_neg BND-01 R02 difftest/s2/bnd01/r02_protected_outside.x
run_neg BND-01 R03 difftest/s2/bnd01/r03_subclass_private.x
run_neg BND-01 R04 difftest/s2/bnd01/r04_other_instance_protected.x
run_pos BND-01 X01 difftest/s2/bnd01/xpkg/main.x
run_neg BND-01 X02 difftest/s2/bnd01/xpkg/main_prot.x
run_neg BND-01 X03 difftest/s2/bnd01/xpkg/main_priv.x

# BND-05
run_pos BND-05 A01 difftest/s2/bnd05/a01_impl_ok.x
run_pos BND-05 A02 difftest/s2/bnd05/a02_inherited_impl.x
run_neg BND-05 R01 difftest/s2/bnd05/r01_missing.x
run_neg BND-05 R02 difftest/s2/bnd05/r02_sig_mismatch.x
run_neg BND-05 R03 difftest/s2/bnd05/r03_parent_missing.x
run_neg BND-05 R04 difftest/s2/bnd05/r04_private_impl.x
run_neg BND-05 R05 difftest/s2/bnd05/r05_override_unknown.x
run_neg BND-05 R06 difftest/s2/bnd05/r06_multi_conflict.x
run_neg BND-05 R07 difftest/s2/bnd05/r07_field.x
run_neg BND-05 R08 difftest/s2/bnd05/r08_method_body.x
run_neg BND-05 R09 difftest/s2/bnd05/r09_generic_protocol.x

# PCTOR-01
run_pos PCTOR-01 A01 difftest/s2/pctor01/a01_primary.x
run_pos PCTOR-01 A02 difftest/s2/pctor01/a02_explicit_noarg.x
run_pos PCTOR-01 A03 difftest/s2/pctor01/a03_explicit_param.x
run_pos PCTOR-01 A04 difftest/s2/pctor01/a04_ctor_order.x
run_pos PCTOR-01 A05 difftest/s2/pctor01/a05_super.x
run_neg PCTOR-01 R01 difftest/s2/pctor01/r01_mix.x
run_neg PCTOR-01 R02 difftest/s2/pctor01/r02_nonfinal.x
run_neg PCTOR-01 R03 difftest/s2/pctor01/r03_nonclass.x
run_neg PCTOR-01 R04 difftest/s2/pctor01/r04_super_not_first.x
run_neg PCTOR-01 R05 difftest/s2/pctor01/r05_final_twice.x

echo "matrix=$EV/matrix.tsv"
