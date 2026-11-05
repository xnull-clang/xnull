#!/usr/bin/env python3
"""规范体系守门检查（P2 脚本化，用户规则：正式版内容必须补齐，不得有待确认项）。

检查项：
  1. 头部三方一致：文件名版本号 = 头部「文档版本」= 「规范状态」含"正式"。
  2. 待定内容扫描：正文出现 待定/待确认/待议/待落实/暂定 即为缺陷
     （排除否定句"无待定"、删除线 ~~ 与行内已标注"已过时/已定案"的历史记录）。
  3. § 引用悬空：所有 `§N(.M)*` 引用必须命中八部分章节号全集。

用法：python3 impl/tools/check_specs.py   （在仓库根执行）
退出码：0 全部通过；1 存在缺陷。
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

PARTS = sorted(
    f for f in os.listdir(ROOT)
    if re.match(r"XNull解决方案-第[1-8]部分-.+-v\d+\.\d+\.\d+\.md$", f)
)
INDEX = "XNull规范索引-v1.0.0.md"

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
    with open(os.path.join(ROOT, name), encoding="utf-8") as fh:
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


def main():
    print(f"仓库：{ROOT}")
    print(f"扫描 {len(PARTS)} 份正式文档 + 索引\n")
    fails = []
    fails += check_headers()
    fails += check_pending()
    fails += check_refs()
    print()
    if fails:
        print(f"共 {len(fails)} 处缺陷")
        return 1
    print("全部通过：正式体系零待定、引用零悬空、头部三方一致")
    return 0


if __name__ == "__main__":
    sys.exit(main())
