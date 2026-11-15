#!/usr/bin/env python3
"""Emit the stable machine-readable result used by build/run --json."""
import json
import re
import sys

ok, target, output, exit_code, diag_path, log_path = sys.argv[1:7]
diags = []
try:
    lines = [] if int(exit_code) == 0 else open(diag_path, encoding="utf-8", errors="replace").read().splitlines()
except OSError:
    lines = []
for line in lines:
    if not line.strip():
        continue
    m = re.match(r"^(.*?):(\d+):(\d+):\s*(?:\[([^\]]+)\]\s*)?(.*)$", line)
    if m:
        diags.append({
            "file": m.group(1),
            "line": int(m.group(2)),
            "column": int(m.group(3)),
            "code": m.group(4) or "",
            "message": m.group(5),
            "hint": "",
            "snippet": "",
            "width": 1,
        })
    else:
        diags.append({"file": target, "line": 0, "column": 0,
                      "code": "", "message": line, "hint": "",
                      "snippet": "", "width": 1})
try:
    log = open(log_path, encoding="utf-8", errors="replace").read()
except OSError:
    log = ""
print(json.dumps({
    "ok": ok == "0",
    "file": target,
    "output": output,
    "exitCode": int(exit_code),
    "diagnostics": diags,
    "log": log,
}, ensure_ascii=False, separators=(",", ":")))
