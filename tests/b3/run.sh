#!/usr/bin/env bash
# B3-00 差分基座总入口：oracle 冻结 + C 文本 diff/sha + 双路径 + 负例。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${XNULL_ROOT:-$(cd "$HERE/../.." && pwd)}
echo "oracle main sha: $(cat "$HERE/oracle.sha")"
rc=0
bash "$HERE/emit-diff.sh" || rc=1
bash "$HERE/dual-path.sh" || rc=1
bash "$HERE/negative.sh" || rc=1
bash "$HERE/xnullc-skeleton.sh" || rc=1
bash "$HERE/xnullc-expr-stmt.sh" || rc=1
bash "$HERE/xnullc-err.sh" || rc=1
bash "$HERE/xnullc-containers.sh" || rc=1
bash "$HERE/xnullc-obj.sh" || rc=1
bash "$HERE/xnullc-obj2.sh" || rc=1
bash "$HERE/xnullc-obj3.sh" || rc=1
bash "$HERE/xnullc-gen.sh" || rc=1
bash "$HERE/xnullc-tuple.sh" || rc=1
bash "$HERE/xnullc-type.sh" || rc=1
bash "$HERE/xnullc-mem.sh" || rc=1
bash "$HERE/xnullc-ffi.sh" || rc=1
bash "$HERE/ast-bundle.sh" || rc=1
exit $rc
