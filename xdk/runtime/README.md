# XNull C runtime

C11 runtime sources and headers used by XDK.

Build a static runtime library:

```sh
./build_rt.sh --lib
```

The script produces `libxnrt.a` in this directory. Runtime source files are
compiled with `-std=c11 -O2 -pthread`; include `xrt.h` and `rt.h` when linking
generated code.
