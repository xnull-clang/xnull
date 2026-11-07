#!/usr/bin/env bash
# QA1-B1-03 独立复验：B1 语料逐字节差分 + 双方幂等。
# 只读 git 提交；不引用 E4 的 evidence/结论。
# 默认语料：B1-00 基线 7df123d（122 文件）、main f63fcba（155 文件）。
set -uo pipefail

REPO=${REPO:-/Users/vjs/Desktop/XNull-Lang}
E4_SHA=${E4_SHA:-cac6686}
CORPUS_SHAS=${CORPUS_SHAS:-"7df123d f63fcba"}
TMP=$(mktemp -d "${TMPDIR:-/tmp}/qa-b1-03.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/e4"
git -C "$REPO" archive --format=tar "$E4_SHA" | tar -x -C "$TMP/e4" || exit 2
( cd "$TMP/e4/impl" && go build -o "$TMP/xnfmt-go" ./cmd/xnfmt && go build -o "$TMP/xnull" ./cmd/xnull ) || exit 2
( cd "$TMP/e4" && "$TMP/xnull" build impl/xnfmt/xnfmt.x -o "$TMP/xnfmt-x" ) >"$TMP/build-x.log" 2>&1 || {
    echo "XNull xnfmt 构建失败"; tail -5 "$TMP/build-x.log"; exit 2; }

rc=0
for corpus in $CORPUS_SHAS; do
    src="$TMP/corpus-$corpus"
    mkdir -p "$src"
    git -C "$REPO" archive --format=tar "$corpus" | tar -x -C "$src" || { rc=2; continue; }
    python3 - "$src" "$TMP/xnfmt-go" "$TMP/xnfmt-x" "$corpus" <<'PY' || rc=1
import subprocess, shutil, pathlib, sys, tempfile
root=pathlib.Path(sys.argv[1]); gobin=sys.argv[2]; xbin=sys.argv[3]; label=sys.argv[4]
tmp=pathlib.Path(tempfile.mkdtemp(prefix='qa-b1-diff.'))
go=tmp/'go'; xn=tmp/'xn'; go.mkdir(); xn.mkdir()
files=sorted(root.rglob('*.x')); diffs=[]; errs=[]; idem_go=[]; idem_xn=[]
for src in files:
    rel=src.relative_to(root)
    for base in (go,xn):
        dst=base/rel; dst.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src,dst)
    r1=subprocess.run([gobin,str(go/rel)],capture_output=True)
    r2=subprocess.run([xbin,str(xn/rel)],capture_output=True)
    if r1.returncode or r2.returncode:
        errs.append((str(rel),r1.returncode,r2.returncode)); continue
    first_go=(go/rel).read_bytes(); first_xn=(xn/rel).read_bytes()
    if first_go!=first_xn:
        diffs.append(str(rel))
    # 幂等：各自再格式化一次，必须与首次输出逐字节相同
    r1=subprocess.run([gobin,str(go/rel)],capture_output=True)
    r2=subprocess.run([xbin,str(xn/rel)],capture_output=True)
    if r1.returncode or (go/rel).read_bytes()!=first_go: idem_go.append(str(rel))
    if r2.returncode or (xn/rel).read_bytes()!=first_xn: idem_xn.append(str(rel))
print(f'corpus={label} files={len(files)} diffs={len(diffs)} errors={len(errs)} idem_go={len(idem_go)} idem_xn={len(idem_xn)}')
for d in diffs: print('DIFF',d)
for e in errs: print('ERR',e)
for d in idem_go: print('IDEM-GO',d)
for d in idem_xn: print('IDEM-XN',d)
sys.exit(0 if not diffs and not errs and not idem_go and not idem_xn else 1)
PY
done
exit $rc
