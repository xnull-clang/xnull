#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)

python3 - "$ROOT" <<'PY'
import re
import sys
from pathlib import Path
root = Path(sys.argv[1])
checks = {
    "src/xdk/core/errors/Errors.x": ["BasicError", "ErrorReport", "ErrorGroup"],
    "src/xdk/config/Config.x": ["MapSource", "FileSource"],
    "src/xdk/io/IO.x": ["Reader", "Writer", "StdioReader", "StdioWriter", "BufferedReader", "BufferedWriter", "ChainReader", "TeeReader", "LimitReader"],
    "src/xdk/log/Log.x": ["SystemClock", "ConsoleSink", "MemorySink", "PredicateFilter", "KeepAllFilter", "ReplaceRedactor", "IdentityRedactor", "EveryNSampler", "KeepAllSampler"],
}
top = re.compile(r"^(class|protocol|enum|static|func|interface|abstract|final)\b")
problems = []
for rel, classes in checks.items():
    lines = (root / rel).read_text(encoding="utf-8").splitlines()
    starts = [(i, m.group(1)) for i, line in enumerate(lines) if (m := re.match(r"class (\w+)", line))]
    for idx, (start, name) in enumerate(starts):
        if name not in classes:
            continue
        end = len(lines)
        for j in range(start + 1, len(lines)):
            if top.match(lines[j]):
                end = j
                break
        if not any(lines[j].strip() == "@Override" for j in range(start + 1, end)):
            problems.append(f"{rel}: {name} has no @Override")
cli = (root / "src/xdk/cli/Cli.x").read_text(encoding="utf-8")
if not re.search(r"@Deprecated\s*\n\s*String value\(String flag\)", cli):
    problems.append("Cli.Args.value is missing @Deprecated")
uses = 0
for path in (root / "src/xdk").rglob("*.x"):
    if "annotations" in path.parts:
        continue
    uses += sum(1 for line in path.read_text(encoding="utf-8").splitlines() if line.lstrip().startswith("@"))
if uses == 0:
    problems.append("src/xdk non-annotation packages contain no annotation uses")
if problems:
    for item in problems:
        print(f"core_annotations: {item}", file=sys.stderr)
    sys.exit(1)
print(f"core_annotations: annotation uses={uses}")
PY

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/probe.x" <<'X'
import xdk.errors
import xdk.config
import xdk.io
import xdk.log
import xdk.cli
static Int main() {
    BasicError err = new BasicError(ErrorKind.InvalidArgument, "probe")
    print(err.kind() == ErrorKind.InvalidArgument)
    List<String> raw = []
    Args args = new Args(raw)
    print(args.value("flag"))
    return 0
}
X
"$ROOT/src/cli/xnull" check "$TMP/probe.x" >/dev/null
echo "core_annotations: PASS"
