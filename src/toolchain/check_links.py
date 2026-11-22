#!/usr/bin/env python3
"""Fail on broken relative Markdown links/images under a directory."""
import os
import re
import sys

LINK = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")


def main(argv):
    roots = argv[1:] or ["docs/design"]
    bad = []
    for root in roots:
        for dirpath, dirs, files in os.walk(root):
            dirs[:] = sorted(d for d in dirs if d not in {".git", "__pycache__"})
            for name in sorted(files):
                if not name.endswith(".md"):
                    continue
                path = os.path.join(dirpath, name)
                text = open(path, encoding="utf-8", errors="ignore").read()
                for target in LINK.findall(text):
                    target = target.strip().split(" ", 1)[0]
                    if target.startswith(("http://", "https://", "mailto:", "#", "tel:")):
                        continue
                    target = target.split("#", 1)[0]
                    if not target:
                        continue
                    resolved = os.path.normpath(os.path.join(dirpath, target))
                    if not os.path.exists(resolved):
                        bad.append((path, target))
    for path, target in bad:
        print("%s: broken link %s" % (path, target))
    if bad:
        print("check_links: %d broken link(s)" % len(bad), file=sys.stderr)
        return 1
    print("check_links: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
