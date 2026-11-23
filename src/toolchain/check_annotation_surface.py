#!/usr/bin/env python3
"""P7-04: compare @annotation declarations with catalog/API surface docs."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "docs/design/ANNOTATION-CATALOG.md"
SURFACE = ROOT / "docs/design/API-SURFACE.md"
XDF = ROOT / "src/xdk"

TARGET_BLOCK = re.compile(r"@annotation\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{(.*?)\n\}", re.S)
TARGET_LINE = re.compile(r"@Target\(([^)]*)\)")
RETENTION_LINE = re.compile(r"@Retention\(([^)]*)\)")
NAME_IN_CELL = re.compile(r"@([A-Za-z_][A-Za-z0-9_]*)")
TARGET_RET = re.compile(r"([A-Za-z]+(?:\s*,\s*[A-Za-z]+)*)\s*/\s*(Source|Binary|Runtime)")


def declarations():
    result = {}
    for path in sorted(XDF.rglob("*.x")):
        text = path.read_text(encoding="utf-8")
        for match in TARGET_BLOCK.finditer(text):
            name = match.group(1)
            prefix = text[max(0, match.start() - 700):match.start()]
            targets = TARGET_LINE.findall(prefix)
            retentions = RETENTION_LINE.findall(prefix)
            target_text = targets[-1] if targets else ""
            retention = retentions[-1].strip() if retentions else "Binary"
            target_list = [part.strip() for part in target_text.split(",") if part.strip()]
            line = text[:match.start()].count("\n") + 1
            result[name] = {"file": path, "line": line, "targets": target_list,
                            "retention": retention}
    return result


def catalog_rows():
    rows = {}
    for number, line in enumerate(CATALOG.read_text(encoding="utf-8").splitlines(), 1):
        match = re.match(r"^\|\s*`@([A-Za-z_][A-Za-z0-9_]*)`\s*\|", line)
        if not match:
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        status = ""
        for cell in reversed(cells):
            if re.search(r"implemented|planned|reserved|open", cell):
                status = cell
                break
        targets = []
        retention = ""
        for cell in cells:
            target_match = TARGET_RET.search(cell)
            if target_match:
                targets = [part.strip() for part in target_match.group(1).split(",")]
                retention = target_match.group(2)
                break
        owner_text = " ".join(cells)
        rows[match.group(1)] = {
            "line": number, "status": status, "targets": targets,
            "retention": retention, "owner": owner_text,
        }
    return rows


def is_compiler_row(row):
    owner = row["owner"]
    return any(word in owner for word in ("编译器", "A8", "语言规则", "compiler", "Language"))


def table_blocks(path):
    blocks = []
    current = []
    start = 0
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if line.strip().startswith("|"):
            if not current:
                start = number
            current.append((number, line))
        else:
            if current:
                blocks.append((start, current))
                current = []
    if current:
        blocks.append((start, current))
    return blocks


def surface_gaps(decls):
    gaps = []
    for start, rows in table_blocks(SURFACE):
        header = None
        if rows:
            header = [cell.strip() for cell in rows[0][1].strip().strip("|").split("|")]
        if header and "可用注解" in header and "状态" in header:
            name_index = header.index("可用注解")
            status_index = header.index("状态")
            owner_index = header.index("包") if "包" in header else (header.index("处理器") if "处理器" in header else -1)
            for number, line in rows[1:]:
                cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
                if len(cells) <= max(name_index, status_index):
                    continue
                names = NAME_IN_CELL.findall(cells[name_index])
                if "implemented" not in cells[status_index]:
                    continue
                owner = cells[owner_index] if owner_index >= 0 else ""
                if any(word in owner for word in ("编译器", "A8", "语言", "compiler", "Language")):
                    continue
                for name in names:
                    if name not in decls:
                        gaps.append(f"{SURFACE}:{number}: surface implemented @{name} has no @annotation declaration")
            continue
        names = []
        owner = ""
        status = ""
        for number, line in rows:
            cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
            if not cells:
                continue
            if cells[0] == "可用注解" and len(cells) > 1:
                names = NAME_IN_CELL.findall(cells[1])
            elif cells[0] == "所属包/处理器" and len(cells) > 1:
                owner = cells[1]
            elif cells[0] == "状态" and len(cells) > 1:
                status = cells[1]
        if not names or "implemented" not in status:
            continue
        if any(word in owner for word in ("编译器", "A8", "语言", "compiler", "Language")):
            continue
        for name in names:
            if name not in decls:
                gaps.append(f"{SURFACE}:{start}: surface implemented @{name} has no @annotation declaration")
    return gaps


def main():
    decls = declarations()
    catalog = catalog_rows()
    gaps = []
    for name, info in sorted(decls.items()):
        row = catalog.get(name)
        if row is None:
            gaps.append(f"{info['file']}:{info['line']}: @{name} missing from ANNOTATION-CATALOG.md")
            continue
        if row["targets"] and sorted(row["targets"]) != sorted(info["targets"]):
            gaps.append(f"{CATALOG}:{row['line']}: @{name} targets doc={row['targets']} declared={info['targets']}")
        if row["retention"] and row["retention"] != info["retention"]:
            gaps.append(f"{CATALOG}:{row['line']}: @{name} retention doc={row['retention']} declared={info['retention']}")
    for name, row in sorted(catalog.items()):
        if "implemented" in row["status"] and name not in decls and not is_compiler_row(row):
            gaps.append(f"{CATALOG}:{row['line']}: implemented @{name} has no @annotation declaration")
    gaps.extend(surface_gaps(decls))

    print(f"annotation_surface: declarations={len(decls)} catalog_rows={len(catalog)}")
    if gaps:
        for gap in gaps:
            print("GAP " + gap)
        print(f"annotation_surface: FAIL ({len(gaps)} gap(s))")
        return 1
    print("annotation_surface: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
