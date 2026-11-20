# mini

mini is the only XNull compiler. It self-hosts from `bin/mini` and emits C for
the XNull runtime. mini is the only compiler.

## Build

```sh
./src/mini/build.sh
```

`build.sh` requires an existing `src/mini/bin/mini` seed. It compiles
`main.x`, rebuilds `bin/mini.c`, and links `bin/mini` against the runtime.
If the seed is missing, build fails; restore it from git history.

## Run a file

```sh
./src/cli/xnull run src/examples/hello.x
./src/cli/xnull build src/examples/hello.x -o /tmp/hello
./src/cli/xnull check src/examples/hello.x
```

## Tests

```sh
src/mini/tests/selfhost.sh
src/mini/tests/xdk.sh
src/mini/tests/m10_parity.sh
src/mini/tests/resources.sh
src/mini/tests/m8.sh
src/mini/tests/m10_perf.sh
```

## Layout

- `main.x` — compiler source.
- `bin/mini` — self-hosted compiler seed/binary.
- `bin/mini.c` — generated C for the compiler.
- `support/io.c` — compiler I/O support.
- `tests/` — mini-only regression scenarios.
