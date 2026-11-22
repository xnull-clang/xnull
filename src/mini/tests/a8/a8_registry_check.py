#!/usr/bin/env python3
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
m = re.search(r"Bool expandA8Annotations\(AstNode program\) \{(.*?)\n\}", text, flags=re.S)
if not m:
    raise SystemExit("a8_registry: missing expandA8Annotations")
body = m.group(1)
for name in ("@Value", "@Data", "@Copy", "@Builder", "@Delegate", "a8HasAnno"):
    if name in body:
        raise SystemExit(f"a8_registry: annotation dispatch leaked into expandA8Annotations: {name}")

reg = re.search(r"List<A8Processor> a8Processors\(\) \{(.*?)\n\}", text, flags=re.S)
if not reg:
    raise SystemExit("a8_registry: missing a8Processors body")
order = re.findall(r"new (A8\w+Processor)\(\)", reg.group(1))
expected = ["A8CoreProcessor", "A8BuilderProcessor", "A8DelegateProcessor"]
if order != expected:
    raise SystemExit(f"a8_registry: processor order {order} != {expected}")
