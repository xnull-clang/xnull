#!/bin/sh
# XDK installer: deploy the XDK sources, runtime sources, and raw FFI
# contracts into a developer prefix. No build step is required.
set -eu

PREFIX=${PREFIX:-$HOME/.local}
DESTDIR=${DESTDIR:-}
SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

usage() {
    cat <<'USAGE'
usage: ./install.sh [--prefix DIR] [--destdir DIR]

  --prefix DIR   installation prefix (default: $HOME/.local)
  --destdir DIR  staging root for packaging (default: empty)
  -h, --help     show this help

Installs:
  <prefix>/share/xnull/xdk        XDK library sources
  <prefix>/share/xnull/runtime    C runtime sources and headers
  <prefix>/share/xnull/ffi        raw FFI bridge contracts
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix) [ $# -ge 2 ] || { usage >&2; exit 2; }; PREFIX=$2; shift 2 ;;
        --prefix=*) PREFIX=${1#--prefix=}; shift ;;
        --destdir) [ $# -ge 2 ] || { usage >&2; exit 2; }; DESTDIR=$2; shift 2 ;;
        --destdir=*) DESTDIR=${1#--destdir=}; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "install.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

for d in lib/xdk runtime ffi; do
    [ -d "$SELF_DIR/$d" ] || { echo "install.sh: missing payload: $d" >&2; exit 1; }
done

DEST="$DESTDIR$PREFIX/share/xnull"
install -d "$DEST/xdk" "$DEST/runtime" "$DEST/ffi"

copy_tree() {
    src=$1
    dst=$2
    # POSIX cp: copy directory contents, including dotfiles.
    (cd "$src" && find . -mindepth 1 -maxdepth 1 -exec cp -R {} "$dst/" \;)
}

copy_tree "$SELF_DIR/lib/xdk" "$DEST/xdk"
copy_tree "$SELF_DIR/runtime" "$DEST/runtime"
copy_tree "$SELF_DIR/ffi" "$DEST/ffi"

printf '%s\n' "XDK installed under: $DEST"
printf '%s\n' "  XNULL_XDK_ROOT=$DEST/xdk"
printf '%s\n' "  XNULL_RUNTIME=$DEST/runtime"
printf '%s\n' "  XNULL_FFI=$DEST/ffi"
