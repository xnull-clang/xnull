#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cmp "$HERE/MemoryFixture.x" "$HERE/../sql/MemoryFixture.x"
echo "db_fixture: PASS"
