#!/usr/bin/env bash
# 构建 QA 黄金库工具：xnull（main）+ astdump（overlay 注入 impl/cmd/astdump，不入生产树）
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
mkdir -p "$HERE/.bin"
( cd "$ROOT/impl" && go build -o "$HERE/.bin/xnull" ./cmd/xnull )
cat >"$HERE/.bin/overlay.json" <<EOF
{"Replace":{"$ROOT/impl/cmd/astdump/main.go":"$HERE/astdump/main.go"}}
EOF
( cd "$ROOT/impl" && go build -overlay "$HERE/.bin/overlay.json" -o "$HERE/.bin/astdump" ./cmd/astdump )
echo "xnull: $HERE/.bin/xnull"
echo "astdump: $HERE/.bin/astdump"
