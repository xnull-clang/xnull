#!/usr/bin/env python3
"""Reject abbreviated value-parameter names in XDK API design docs.

The rule lives in docs/design/t0/00-overview.md §1.1: public value
parameters use full English words; single letters are allowed only for
type parameters and implementation loop indices.

The checker parses the top-level parameter list of each signature. Nested
function types such as Bool(T, T) lessThan are kept as one parameter, so
their type parameters are not mistaken for value names.

Usage: check_doc_naming.py <file-or-dir> [...]
Exit: 0 = clean, 1 = violations.
"""
import os
import re
import sys

BANNED = {
    "s", "e", "r", "f", "v", "c", "n", "i", "j", "x", "y", "a", "b",
    "d", "m", "h", "q", "p", "w", "k", "lo", "hi", "ms", "ns", "us",
    "len", "buf", "val", "tmp", "obj", "ptr", "num", "str", "init",
    "unit", "times", "needle", "sep", "pad", "ctx", "args", "cmp",
    "eq", "pred", "fn", "idx", "msg", "res", "err", "ch", "sig", "off",
}
TYPE_ONLY = {
    "String", "Int", "Int32", "Int64", "Long", "Bool", "Double", "Char",
    "Bytes", "Context", "Args", "Error", "Unit", "void", "Void",
}
SKIP_MARKERS = ("不合格", "反例", "禁止")


def top_level_params(text):
    """Return the outermost comma-separated parameter segments."""
    start = text.find("(")
    if start < 0:
        return []
    depth = 0
    end = -1
    for i in range(start, len(text)):
        ch = text[i]
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                end = i
                break
    if end < 0:
        return []
    inner = text[start + 1:end]
    if inner.strip() == "":
        return []
    parts = []
    current = ""
    depth = 0
    for ch in inner:
        if ch in "(<[{":
            depth += 1
        elif ch in ")>]}":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(current.strip())
            current = ""
        else:
            current += ch
    parts.append(current.strip())
    return parts


def check_signature(text, path, lineno, out):
    for part in top_level_params(text):
        if not part:
            continue
        if "=" in part:
            part = part.split("=", 1)[0].strip()
        if " " not in part.strip():
            out.append((path, lineno, "parameter has no name: " + part))
            continue
        # The value name is the last identifier outside function/generic types.
        name_match = re.search(r"([A-Za-z_][A-Za-z0-9_]*)$", part)
        if not name_match:
            continue
        name = name_match.group(1)
        # A bare type token was already handled; a single type parameter is fine.
        if name in {"T", "K", "V", "E", "A", "B", "R", "U", "F"}:
            continue
        if name == "_":
            continue
        if name in BANNED or len(name) <= 2 or re.fullmatch(r"[a-z][a-z]?\d+", name):
            out.append((path, lineno, "abbreviated parameter name: " + name))


RETURN_PREFIX = re.compile(
    r"^\s*(?:static\s+)?(?:String|Int|Int32|Int64|Long|Bool|Double|Char|"
    r"Bytes|Void|void|Unit|Context|Error|ErrorKind|Signal|"
    r"Result<.*?>|List<.*?>|Map<.*?>|Set<.*?>|Task<.*?>|Mutex<.*?>|"
    r"Channel<.*?>|Iterator<.*?>|Pair<.*?>|Indexed<.*?>|Instant|Duration|"
    r"DateTime|Civil|TimeZone|Int128|Logger|Config|Args|Command)\s+"
    r"[A-Za-z_]\w*\s*(?:<[^>]*>)?\("
)


def looks_like_signature(text, current_class):
    stripped = text.strip()
    if stripped.startswith("//") or stripped.startswith("#"):
        return False
    if RETURN_PREFIX.match(text):
        return True
    if current_class and stripped.startswith(current_class + "("):
        return True
    if stripped.startswith("static ") and "(" in stripped:
        return True
    return False


def check_line(text, path, lineno, out, in_code, current_class):
    if any(marker in text for marker in SKIP_MARKERS):
        return
    spans = []
    if in_code:
        if looks_like_signature(text, current_class):
            spans = [text]
    else:
        spans = [span for span in re.findall(r"`([^`]*)`", text)
                 if looks_like_signature(span, "")]
    for span in spans:
        if "(" not in span or ")" not in span:
            continue
        if span.strip().startswith("O("):
            continue
        check_signature(span, path, lineno, out)


def check_file(path, out):
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().splitlines()
    in_code = False
    current_class = ""
    for lineno, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith("```"):
            in_code = not in_code
            if not in_code:
                current_class = ""
            continue
        if not in_code:
            check_line(line, path, lineno, out, False, "")
            continue
        match = re.match(r"^\s*class\s+([A-Za-z_]\w*)", line)
        if match:
            current_class = match.group(1)
        check_line(line, path, lineno, out, True, current_class)


def main(argv):
    if len(argv) < 2:
        print("usage: check_doc_naming.py <file-or-dir> [...]", file=sys.stderr)
        return 2
    out = []
    for target in argv[1:]:
        if os.path.isdir(target):
            for root, _dirs, files in os.walk(target):
                for name in sorted(files):
                    if name.endswith(".md"):
                        check_file(os.path.join(root, name), out)
        else:
            check_file(target, out)
    for path, lineno, message in out:
        print("%s:%d: %s" % (path, lineno, message))
    if out:
        print("check_doc_naming: %d violation(s)" % len(out), file=sys.stderr)
        return 1
    print("check_doc_naming: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
