# XDK

XDK is the developer-facing XNull standard library package. It contains:

```
lib/xdk/          XDK package sources (`xdk.errors`, `xdk.runtime`, ...)
runtime/          C runtime sources and headers
bindings/xdk/     typed FFI binding contracts (`.xfb`)
ffi/              raw FFI bridge contracts
install.sh        POSIX sh installer
```

## Install

```sh
./install.sh --prefix "$HOME/.local"
```

The installer is idempotent and does not require root when the prefix is
writable by the current user. For packaging, use a staging root:

```sh
DESTDIR=/tmp/xdk-pkg ./install.sh --prefix /usr/local
```

After installation, point the XNull toolchain at:

- `XNULL_XDK_ROOT=<prefix>/share/xnull/xdk`
- `XNULL_RUNTIME=<prefix>/share/xnull/runtime`
- `XNULL_BINDINGS=<prefix>/share/xnull/bindings`
- `XNULL_FFI=<prefix>/share/xnull/ffi`

The package is source-only; the XNull compiler remains a separate toolchain
component.
