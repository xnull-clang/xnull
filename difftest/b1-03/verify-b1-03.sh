#!/usr/bin/env bash
# QA1-B1-03 独立复验：B1 语料 122 文件，Go oracle vs XNull formatter 逐字节 diff。
# 只读 git 提交；不使用 E4 的 evidence/结论。
# 依据：B1-00 基线 7df123d 的 122 个 .x；实现：B1-03 0d8c985（Go oracle + XNull xnfmt）。
set -uo pipefail

REPO=${REPO:-/Users/vjs/Desktop/XNull-Lang}
E4_SHA=${E4_SHA:-0d8c985}
CORPUS_SHA=${CORPUS_SHA:-7df123d}
TMP=$(mktemp -d "${TMPDIR:-/tmp}/qa-b1-03.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/e4" "$TMP/corpus"
git -C "$REPO" archive --format=tar "$E4_SHA" | tar -x -C "$TMP/e4" || exit 2
git -C "$REPO" archive --format=tar "$CORPUS_SHA" | tar -x -C "$TMP/corpus" || exit 2

( cd "$TMP/e4/impl" && go build -o "$TMP/xnfmt-go" ./cmd/xnfmt && go build -o "$TMP/xnull" ./cmd/xnull ) || exit 2
( cd "$TMP/e4" && "$TMP/xnull" build impl/xnfmt/xnfmt.x -o "$TMP/xnfmt-x" ) >"$TMP/build-x.log" 2>&1 || { echo "XNull xnfmt 构建失败"; tail -5 "$TMP/build-x.log"; exit 2; }

python3 - "$TMP/corpus" "$TMP/xnfmt-go" "$TMP/xnfmt-x" <<'PY'
import subprocess, shutil, pathlib, sys, tempfile
root=pathlib.Path(sys.argv[1]); gobin=sys.argv[2]; xbin=sys.argv[3]
tmp=pathlib.Path(tempfile.mkdtemp(prefix='qa-b1-diff.'))
go=tmp/'go'; xn=tmp/'xn'; go.mkdir(); xn.mkdir()
files=sorted(root.rglob('*.x')); diffs=[]; errs=[]
for src in files:
    rel=src.relative_to(root)
    for base in (go,xn):
        dst=base/rel; dst.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src,dst)
    r1=subprocess.run([gobin,str(go/rel)],capture_output=True)
    r2=subprocess.run([xbin,str(xn/rel)],capture_output=True)
    if r1.returncode or r2.returncode:
        errs.append((str(rel),r1.returncode,r2.returncode)); continue
    if (go/rel).read_bytes()!=(xn/rel).read_bytes():
        diffs.append(str(rel))
print(f'files={len(files)} diffs={len(diffs)} errors={len(errs)}')
for d in diffs: print('DIFF',d)
for e in errs: print('ERR',e)
sys.exit(0 if not diffs and not errs else 1)
PY
