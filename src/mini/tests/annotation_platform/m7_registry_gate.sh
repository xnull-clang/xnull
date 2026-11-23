#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
"$HERE/../annotation_registry/run.sh"
"$HERE/../annotation_extension/run.sh"
echo "m7_registry_gate: PASS"
