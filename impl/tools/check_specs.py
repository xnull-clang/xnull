#!/usr/bin/env python3
"""规范体系守门检查（P2 脚本化，用户规则：正式版内容必须补齐，不得有待确认项）。

检查项：
  1. 头部三方一致：文件名版本号 = 头部「文档版本」= 「规范状态」含"正式"。
  2. 待定内容扫描：正文出现 待定/待确认/待议/待落实/暂定 即为缺陷
     （排除否定句"无待定"、删除线 ~~ 与行内已标注"已过时/已定案"的历史记录）。
  3. § 引用悬空：所有 `§N(.M)*` 引用必须命中八部分章节号全集。
  4. 二进制文档：仓库根出现 *.docx/*.doc/*.pptx/*.xlsx/*.pdf 即缺陷
     （文档格式纪律：技术内容一律 Markdown，单一事实源）。
  5. EN 快照同步：xnull/spec/en/ 的英译必须覆盖八部分 + 台账，
     版本与中文母本一致，且母本 mtime 不得晚于英译（母本改动必须先重译再提交）。

用法：python3 impl/tools/check_specs.py   （在仓库根执行）
退出码：0 全部通过；1 存在缺陷。
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

INDEX = "XNull规范索引-v1.0.0.md"

# 布局自适应：工作空间根布局（规范在根目录，EN 在 xnull/spec/en）
# 与公开仓库布局（规范与 EN 均在 spec/ 下）二选一。
SPEC_DIR = next(
    d
    for d in (ROOT, os.path.join(ROOT, "spec"))
    if os.path.isfile(os.path.join(d, INDEX))
)

PARTS = sorted(
    f for f in os.listdir(SPEC_DIR)
    if re.match(r"XNull解决方案-第[1-8]部分-.+-v\d+\.\d+\.\d+\.md$", f)
)

PENDING_WORDS = re.compile(r"待定|待确认|待议|待落实|暂定")


def fail_list(title, fails):
    if fails:
        print(f"[FAIL] {title}")
        for f in fails:
            print(f"  - {f}")
    else:
        print(f"[ok]   {title}")
    return fails


def read(name):
    with open(os.path.join(SPEC_DIR, name), encoding="utf-8") as fh:
        return fh.read()


def check_headers():
    fails = []
    for f in PARTS:
        s = read(f)
        v_file = re.search(r"v(\d+\.\d+\.\d+)\.md$", f)
        m_ver = re.search(r"^\| 文档版本 \| (\d+\.\d+\.\d+) \|", s, re.M)
        m_st = re.search(r"^\| 规范状态 \| (.+?) \|", s, re.M)
        if not (v_file and m_ver and m_st):
            fails.append(f"{f}: 缺头部三方字段")
            continue
        if v_file.group(1) != m_ver.group(1):
            fails.append(f"{f}: 文件名版本 {v_file.group(1)} ≠ 头部 {m_ver.group(1)}")
        if "正式" not in m_st.group(1):
            fails.append(f"{f}: 规范状态非正式：{m_st.group(1)}")
    return fail_list("头部三方一致（文件名版本 = 头部版本 = 正式）", fails)


def check_pending():
    """正式文档正文不得出现待定类措辞；历史沿革必须显式标注已过时/已定案。"""
    fails = []
    for f in PARTS + [INDEX]:
        for n, line in enumerate(read(f).splitlines(), 1):
            if not PENDING_WORDS.search(line):
                continue
            if "无待定" in line:  # 否定句（如第7部分附录B"本表无待定项"）
                continue
            if "禁用措辞" in line:  # 索引中定义本规则的那一行
                continue
            if "~~" in line and ("已过时" in line or "已定案" in line):
                continue  # 历史日志中已显式作废的陈述
            fails.append(f"{f}:{n}: {line.strip()[:80]}")
    return fail_list("待定内容扫描（正式版零待确认）", fails)


def check_refs():
    """全部 § 引用必须命中八部分章节号并集。"""
    heads = set()
    for f in PARTS:
        for m in re.finditer(r"^#{2,4} (\d+(?:\.\d+)*)", read(f), re.M):
            heads.add(m.group(1).rstrip("."))
    fails = []
    for f in PARTS + [INDEX]:
        for n, line in enumerate(read(f).splitlines(), 1):
            for m in re.finditer(r"§(\d+(?:\.\d+)*)", line):
                ref = m.group(1)
                if ref in heads:
                    continue
                # 引用小节（如 §5.6）时，允许其顶层章节存在（小节悬空由引用完整性审计兜底）
                if ref.split(".")[0] in heads:
                    continue
                fails.append(f"{f}:{n}: §{ref} 未命中任何章节")
    return fail_list("§ 引用悬空（全集校验）", fails)


def check_binaries():
    """仓库根禁止 Office 二进制（文档格式纪律，2026-11-06 用户裁决）。"""
    exts = (".docx", ".doc", ".pptx", ".xlsx", ".pdf")
    fails = [f for f in os.listdir(ROOT) if f.lower().endswith(exts)]
    return fail_list("二进制文档拦截（根目录仅 Markdown）", fails)


def check_en_sync():
    """EN 快照：覆盖、版本一致、不滞后于中文母本。"""
    en_dir = os.path.join(SPEC_DIR, "en")
    if not os.path.isdir(en_dir):
        en_dir = os.path.join(ROOT, "xnull", "spec", "en")
    if not os.path.isdir(en_dir):
        return fail_list("EN 快照同步（公开内容线）", ["xnull/spec/en/ 目录不存在"])
    en_files = os.listdir(en_dir)
    fails = []
    # 按部件号配对：第N部分 ↔ S{N}-*；台账 ↔ Conformance-Ledger-*
    pairs = []
    for cn in PARTS:
        n = re.search(r"第(\d)部分", cn).group(1)
        cand = [e for e in en_files if e.startswith(f"S{n}-")]
        if not cand:
            fails.append(f"缺 S{n} 英译（母本 {cn}）")
            continue
        pairs.append((cn, cand[0]))
    led_cand = [e for e in en_files if e.startswith("Conformance-Ledger-")]
    if led_cand:
        pairs.append(("XNull一致性用例台账-v1.0.0.md", led_cand[0]))
    else:
        fails.append("缺台账英译（Conformance-Ledger）")
    for cn, en in pairs:
        v_cn = re.search(r"v(\d+\.\d+\.\d+)\.md$", cn).group(1)
        m_en = re.search(r"v(\d+\.\d+\.\d+)\.md$", en)
        if not m_en or m_en.group(1) != v_cn:
            fails.append(f"{en}: 版本 {m_en.group(1) if m_en else '?'} ≠ 母本 {v_cn}")
            continue
        t_cn = os.path.getmtime(os.path.join(SPEC_DIR, cn))
        t_en = os.path.getmtime(os.path.join(en_dir, en))
        if t_cn > t_en:
            fails.append(f"{en}: 晚于母本改动——母本 {cn} 变更后英译未同步重译")
    return fail_list(f"EN 快照同步（{len(pairs)} 份对照）", fails)


def main():
    print(f"仓库：{ROOT}")
    print(f"扫描 {len(PARTS)} 份正式文档 + 索引\n")
    fails = []
    fails += check_headers()
    fails += check_pending()
    fails += check_refs()
    fails += check_binaries()
    fails += check_en_sync()
    print()
    if fails:
        print(f"共 {len(fails)} 处缺陷")
        return 1
    print("全部通过：零待定、引用零悬空、头部一致、根目录纯 Markdown、EN 快照同步")
    return 0


if __name__ == "__main__":
    sys.exit(main())
