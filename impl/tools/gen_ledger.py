#!/usr/bin/env python3
"""从规范文档抽取验收编号行，生成《一致性用例台账》。

用法：python3 impl/tools/gen_ledger.py [仓库根]
规范增删验收行后重跑即可；人工只在台账里填「用例文件 / 状态」两列。
"""
import os
import re
import sys
from collections import Counter, OrderedDict

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "XNull一致性用例台账-v1.0.0.md")
STATUS = os.path.join(ROOT, "impl", "docs", "conformance", "status.tsv")

DOCS = OrderedDict([
    ("S1", "第1部分-基础语法"), ("S2", "第2部分-对象编程"), ("S3", "第3部分-内存管理"),
    ("S4", "第4部分-错误处理"), ("S5", "第5部分-运行时任务与并发"), ("S6", "第6部分-标准库XDK"),
    ("S7", "第7部分-FFI"), ("S8", "第8部分-工程配置"),
])

# 编号前缀 → 实现里程碑（M1 前段 / M2 语义 / M3 后端与工具链）
MILESTONE = {
    "LEX": "M1", "EXPR": "M1", "STMT": "M1", "BLOCK": "M1", "CTRL": "M1",
    "TYPE": "M1", "FIELD": "M1", "INH": "M1", "PROTO": "M1", "STRUCT": "M1",
    "ENUM": "M1", "TUPLE": "M1", "GEN": "M1", "INT": "M1", "KIND": "M1",
    "DISP": "M1", "ENTRY": "M1", "PKG": "M1", "ANN": "M1",
    "MEM": "M2", "DET": "M2", "CLEAN": "M2", "GATE": "M2", "BND": "M2",
    "BOUND": "M2", "ERR": "M2", "OBS": "M2", "CANCEL": "M2", "NEG": "M2",
    "TASK": "M2", "SYNC": "M2", "SCHED": "M2", "PCTOR": "M2",
    "XDK": "M3", "FFI": "M3", "BLD": "M3", "EXT": "M3", "SINGLE": "M3",
    "PROJ": "M0/M3",
}
ROW = re.compile(r"^\|\s*([A-Z]{2,6})-(\d{2,3})\s*\|(.*)$")


def doc_files():
    for sid, stem in DOCS.items():
        for name in sorted(os.listdir(ROOT)):
            if stem in name and name.endswith(".md"):
                yield sid, name
                break


def rows():
    for sid, name in doc_files():
        with open(os.path.join(ROOT, name), encoding="utf-8") as fh:
            for line in fh:
                m = ROW.match(line.strip())
                if not m:
                    continue
                prefix, num, rest = m.group(1), m.group(2), m.group(3)
                cells = [c.strip() for c in rest.split("|")]
                cells = [c for c in cells if c and not set(c) <= {"-"}]
                if not cells:
                    continue
                text = "；".join(cells).replace("<br>", "；")
                text = re.sub(r"\s+", " ", text).strip(" ；")
                yield sid, f"{prefix}-{num}", text, MILESTONE.get(prefix, "M3")


def load_status():
    """读取人工维护的状态旁表：编号 → (用例文件, 状态)。"""
    table = {}
    if not os.path.exists(STATUS):
        return table
    with open(STATUS, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            cells = line.split("\t")
            if len(cells) < 3:
                continue
            table[cells[0]] = (cells[1], cells[2])
    return table


def main():
    items = list(rows())
    seen, uniq = set(), []
    for sid, cid, text, ms in items:
        if cid in seen:
            continue
        seen.add(cid)
        uniq.append((sid, cid, text, ms))

    by_doc = Counter(s for s, *_ in uniq)
    by_ms = Counter(m for *_, m in uniq)
    status = load_status()
    passed = sum(1 for v in status.values() if v[1] == "PASS")

    out = ["# XNull 一致性用例台账",
           "",
           "> 由 `impl/tools/gen_ledger.py` 自动生成，**不要手改编号列**。人工只维护两列：`用例文件`（相对 `impl/Tests/`）与`状态`。",
           "> 状态取值：`未实现` / `部分` / `PASS` / `N/A（非承诺或被否决，见对应文档）`。",
           "> 台账是实现的单一事实源：任何里程碑宣告完成，必须先把对应行的状态改为 `PASS`。",
           "",
           "## 0. 统计",
           "",
           "| 维度 | 分布 |",
           "| --- | --- |",
           f"| 总计 | {len(uniq)} 条（PASS {passed}） |",
           "| 按文档 | " + " · ".join(f"{k} {v}" for k, v in by_doc.items()) + " |",
           "| 按里程碑 | " + " · ".join(f"{k} {v}" for k, v in sorted(by_ms.items())) + " |",
           "",
           "## 1. 用例清单",
           "",
           "| 编号 | 文档 | 验收要点 | 里程碑 | 用例文件 | 状态 |",
           "| --- | --- | --- | --- | --- | --- |"]
    for sid, cid, text, ms in uniq:
        text = text.replace("|", "\\|")
        case, st = status.get(cid, ("—", "未实现"))
        out.append(f"| {cid} | {sid} | {text} | {ms} | {case} | {st} |")
    out.append("")
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out))
    print(f"已生成 {OUT}：{len(uniq)} 条；按文档 {dict(by_doc)}；按里程碑 {dict(sorted(by_ms.items()))}")


if __name__ == "__main__":
    main()
