# Migration guide: mini 0.x → 1.0 T0 core

| Item | Value |
| --- | --- |
| Applies to | `mini-v0.2.0`, `mini-v0.3.0` sources upgrading to the 1.0 T0 surface |
| Status | Guide + compilable sample; **no installable 0.x artifact in this workspace** |
| Sample | `src/mini/tests/ref/migration_sample.x` |

## 1. What changed

| Area | 0.x pattern | 1.0 pattern |
| --- | --- | --- |
| Logging fields | concatenate key/value into the message | `Logger.withField(key, value)` + `Sink`/`LogRecord` |
| Config sources | set values manually or read env | `ConfigSource`, `MapSource`, `FileSource`, `Config.apply/overlay` |
| CLI commands | `Args` only | `OptionSpec`, `Command`, `CommandMatch`, subcommands and `help()` |
| Bytes to text | implicit NUL-terminated conversion | explicit length-based conversion (compiler helper); no behavior change at source level |
| Tasks/sync | package-shaped calls | language/runtime builtins; package docs are builtin references, not 1.0 packages |
| Int/Wide values | `Int` assumed wide in old code | `Int` is 32-bit; use `Long` for epoch/size/handle values |

## 2. Migration steps

1. Replace free-form log messages that embedded fields with
   `Logger.withField`; keep messages stable.
2. Move environment/file loading behind `ConfigSource` + `Config.apply`.
3. Replace hand-written argv loops with `OptionSpec` + `Command.parse` where
   the program has subcommands or required options.
4. Audit `Int` values that hold epoch milliseconds, file sizes, process
   handles, or resource sizes; change them to `Long`.
5. Rebuild and run:

   ```sh
   ./src/cli/xnull build <entry-or-project> -o /tmp/app
   ./src/cli/xnull run <entry-or-project>
   ```

## 3. Before / after sample

See `src/mini/tests/ref/migration_sample.x`:

```text
Logger logger = new Logger("migration", Level.Info)
Logger fielded = logger.withField("version", "1.0")
fielded.info("ready")
```

Expected output:

```text
[INFO] migration: ready version=1.0
```

## 4. Explicit incomplete item

No installable `0.x` release artifact exists in this workspace, so the guide
was validated against source-level patterns and a compilable 1.0 sample, not by
installing an old artifact and upgrading it in place. **This missing 0.x
artifact is the only unfinished item of U3.** No other migration step is
claimed as skipped.
