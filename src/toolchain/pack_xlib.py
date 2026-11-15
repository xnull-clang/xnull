#!/usr/bin/env python3
"""Create a deterministic .xlib archive for a library module.

Usage: pack_xlib.py OUT.xlib MODULE_DIR GROUP_PATH ARTIFACT VERSION PACKAGING [DEP...]
"""
import os
import sys
import zipfile

if len(sys.argv) < 7:
    print("usage: pack_xlib.py OUT MODULE GROUP ARTIFACT VERSION PACKAGING [DEP...]", file=sys.stderr)
    sys.exit(2)

out, root, group, artifact, version, packaging = sys.argv[1:7]
deps = sys.argv[7:]
root = os.path.abspath(root)

entries = []
for base, dirs, files in os.walk(root):
    relbase = os.path.relpath(base, root)
    if relbase == ".":
        relbase = ""
    # Build outputs and caches are never part of a library artifact.
    dirs[:] = sorted(d for d in dirs if d not in (".cache", "target", "__pycache__", ".git"))
    for name in sorted(files):
        if name.endswith((".o", ".a", ".so", ".dylib", ".xlib")):
            continue
        rel = os.path.join(relbase, name) if relbase else name
        entries.append((rel.replace(os.sep, "/"), os.path.join(base, name)))

manifest = [
    "format=xlib-1",
    "groupId=%s" % group.replace("/", "."),
    "artifactId=%s" % artifact,
    "version=%s" % version,
    "packaging=%s" % packaging,
]
for dep in sorted(deps):
    manifest.append("dependency=%s" % dep)
entries.append(("META-INF/xlib.manifest", None))

# Stored entries + fixed timestamps make the digest stable across hosts.
os.makedirs(os.path.dirname(os.path.abspath(out)) or ".", exist_ok=True)
with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_STORED, allowZip64=True) as z:
    for rel, path in sorted(entries, key=lambda x: x[0]):
        info = zipfile.ZipInfo(rel, date_time=(1980, 1, 1, 0, 0, 0))
        info.external_attr = 0o100644 << 16
        if path is None:
            z.writestr(info, ("\n".join(manifest) + "\n").encode("utf-8"))
        else:
            with open(path, "rb") as f:
                z.writestr(info, f.read())
