#!/bin/sh
# Build a deterministic local release tarball.
# Fixed SOURCE_DATE_EPOCH, sorted entries, fixed mtime/uid/gid; two runs of the
# same tree must produce the same sha256.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
VERSION=${XNULL_RELEASE_VERSION:-1.0.0}
EPOCH=${SOURCE_DATE_EPOCH:-1700000000}
OUTDIR=${XNULL_RELEASE_DIR:-"$ROOT/dist"}
mkdir -p "$OUTDIR"
BASE="xnull-$VERSION"
TAR="$OUTDIR/$BASE.tar.gz"

SOURCES="src/cli src/toolchain src/mini/bin/mini src/mini/main.x src/mini/support src/runtime src/xdk src/ffi README.md"
( cd "$ROOT" && SOURCE_DATE_EPOCH="$EPOCH" VERSION="$VERSION" BASE="$BASE" TAR="$TAR" python3 - $SOURCES <<'PY'
import gzip, os, sys, tarfile, time

epoch = int(os.environ["SOURCE_DATE_EPOCH"])
base = os.environ["BASE"]
tar_path = os.environ["TAR"]
roots = sys.argv[1:]

files = []
for root in roots:
    if os.path.isfile(root):
        files.append(root)
        continue
    for dirpath, dirs, names in os.walk(root):
        dirs[:] = sorted(d for d in dirs if d not in {".cache", "__pycache__"})
        for name in sorted(names):
            if name.startswith("test_") or name.endswith((".o", ".a", ".dylib", ".so")):
                continue
            files.append(os.path.join(dirpath, name))
files = sorted(set(files))

with gzip.GzipFile(tar_path, "wb", mtime=epoch) as gz:
    with tarfile.open(fileobj=gz, mode="w") as tar:
        for rel in files:
            info = tar.gettarinfo(rel, arcname=base + "/" + rel)
            info.mtime = epoch
            info.uid = 0
            info.gid = 0
            info.uname = ""
            info.gname = ""
            with open(rel, "rb") as handle:
                tar.addfile(info, handle)
PY
)
shasum -a 256 "$TAR" > "$TAR.sha256"
printf '%s\n' "$VERSION" > "$OUTDIR/VERSION"
printf '%s\n' "$TAR"
printf '%s\n' "$(cat "$TAR.sha256")"
