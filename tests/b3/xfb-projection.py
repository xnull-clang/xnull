#!/usr/bin/env python3
"""把 .xfb 绑定声明投影为 xnullc 可消费的紧凑注册表（B3-08）。

B3 只消费注册表、不重写 .xfb 解析；本脚本是差分测试侧的投影器，
仅覆盖 B3-08 锚点需要的合同子集。

输出行（以 \\n 分隔）：
  M|region|code|Kind
  E|region|name|cName|retKind|retName|errCodeParam|errCodeRet|companion|p:kind:type:lease;...
"""
import os
import re
import sys


def find_xfb(root):
    out = []
    for dirpath, _dirs, files in os.walk(root):
        for f in sorted(files):
            if f.endswith(".xfb"):
                out.append(os.path.join(dirpath, f))
    return sorted(out)


def split_params(text):
    parts, cur, depth = [], "", 0
    for ch in text:
        if ch in "(<[":
            depth += 1
        elif ch in ")>]":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        parts.append(cur)
    return parts


def kind_of(t, handles):
    if t == "String":
        return "string"
    if t == "Text":
        return "text"
    if t == "Bytes":
        return "bytes"
    if t in handles:
        return "handle"
    return "scalar"


def parse(path):
    src = open(path, encoding="utf-8").read()
    regions = re.findall(r"ffi\s+([A-Za-z_]\w*)\s*\{", src)
    region = regions[0] if regions else "region"
    handles = set(re.findall(r"handle\s+([A-Za-z_]\w*)", src))
    rules = []
    m = re.search(r"errorMap\s*\{(.*?)\}", src, re.S)
    if m:
        for code, kind in re.findall(r"(\d+)\s*=\s*([A-Za-z_]\w*)", m.group(1)):
            rules.append((int(code), kind))
    entries = []
    for chunk in re.split(r"@ffiEntry", src)[1:]:
        entry = re.search(r"([A-Za-z_]\w*)\s+([A-Za-z_]\w*)\s*\(([^)]*)\)\s*;", chunk)
        if not entry:
            continue
        anns = chunk[:entry.start()]
        rett, name, ps = entry.group(1), entry.group(2), entry.group(3)
        cname = re.search(r'cName\s*=\s*"([^"]+)"', anns)
        cname = cname.group(1) if cname else name
        lease = {}
        lm = re.search(r"@lease\s*\((.*?)\)", anns, re.S)
        if lm:
            for pn, lk in re.findall(r"(\w+)\s*=\s*\.(\w+)", lm.group(1)):
                lease[pn] = lk
        code_param, code_ret = "", 0
        em = re.search(r"@errorCode\s*\(\s*codeParam\s*=\s*\.(\w+)\s*\)", anns)
        if em:
            if em.group(1) in ("result", "return"):
                code_ret = 1
            else:
                code_param = em.group(1)
        longrun = 1 if "@longRunning" in anns else 0
        unaware = 1 if re.search(r"@blocking\s*\(\s*\.unaware\s*\)", anns) else 0
        companion = 1 if (longrun and unaware) else 0
        params = []
        for p in split_params(ps.strip()):
            p = p.strip()
            if not p:
                continue
            pt, pn = p.rsplit(None, 1)
            params.append("%s:%s:%s:%s" % (pn, kind_of(pt, handles), pt, lease.get(pn, "")))
        entries.append("|".join([
            "E", region, name, cname, kind_of(rett, handles), rett,
            code_param, str(code_ret), str(companion), ";".join(params),
        ]))
    return region, rules, entries


def main():
    root = sys.argv[1]
    all_entries, all_rules = [], {}
    for path in find_xfb(root):
        region, rules, entries = parse(path)
        all_entries.extend(entries)
        seen = all_rules.setdefault(region, {})
        for code, kind in rules:
            seen.setdefault(code, kind)
    out = []
    for region in sorted(all_rules):
        for code in sorted(all_rules[region]):
            out.append("M|%s|%d|%s" % (region, code, all_rules[region][code]))
    out.extend(e for e in sorted(all_entries, key=lambda s: s.split("|")[2]))
    sys.stdout.write("\n".join(out) + ("\n" if out else ""))


if __name__ == "__main__":
    main()
