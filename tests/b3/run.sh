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
exit $rc
