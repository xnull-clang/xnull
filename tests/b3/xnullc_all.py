#!/usr/bin/env python3
"""B3-09 全量门禁：Go emit-c vs xnullc（单文件/多文件/负例），支持稳定分片与聚合。"""
import argparse, csv, hashlib, json, os, re, shutil, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor
from difflib import unified_diff

# K-07 文件通道契约：AST/bundle 单文件上限 16 MiB。
LIMIT_BYTES = 16 * 1024 * 1024

def run(cmd, cwd, timeout=300):
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired:
        return 124, "", "timeout"
    except OSError as e:
        return 125, "", str(e)

def shard_of(path, n):
    h = hashlib.sha256(path.encode("utf-8")).hexdigest()[:16]
    return int(h, 16) % n + 1

def norm(text):
    text = re.sub(r"xn_t\d+", "xn_t#", text)
    return "\n".join(line.lstrip(" \t") for line in text.splitlines())

def diff_count(a, b, n=3):
    d = list(unified_diff(a.splitlines(True), b.splitlines(True), n=n))
    return len(d), d

def cause_of(diffs):
    for line in diffs:
        if line.startswith(("---", "+++", "@@")):
            continue
        s = line[1:]
        if "static void" in s and "int64_t" in s:
            return "K-01 void 返回"
        if "typedef int (*xn_fn_" in s:
            return "K-03 函数指针 typedef"
        if "typedef struct { rt_header" in s:
            return "K-02 容器 typedef"
        if "xn_Result_" in s:
            return "K-05 Result typedef"
        if any(ord(ch) > 127 for ch in s):
            return "K-04 非 ASCII"
        if "xn_root_" in s:
            return "K-06 temp/root"
        if "xn_str_substr" in s or "xn_str_length" in s:
            return "K-06 String 发射"
        if line[:1] in "+-":
            return "K-06 temp/编号/缩进"
    return ""

def load_rows(path):
    if path and os.path.exists(path):
        with open(path, newline="") as f:
            return list(csv.DictReader(f, delimiter="\t"))
    return None

def fallback_rows(root):
    out = subprocess.run(["git", "ls-files", "*.x"], cwd=root, capture_output=True, text=True).stdout.split()
    rows = []
    for f in out:
        if f.startswith(("evidence/", "archive/")):
            continue
        rows.append({"path": f, "group": f.split("/")[0], "kind": "?", "files": ""})
    return rows

def process(row, args):
    root = args.root
    f = row["path"]
    kind = row.get("kind", "?")
    if kind in ("?", ""):
        code, _out, err = run([args.go_bin, "build", "--emit-c", f], root)
        if code != 0:
            return dict(row, go_exit=code, raw="", content="", status="NEG-PASS",
                        cause="", note=(err.splitlines()[0] if err.splitlines() else ""))
    if kind.startswith("非入口"):
        code, _out, err = run([args.go_bin, "build", "--emit-c", f], root)
        if code != 0:
            return dict(row, go_exit=code, raw="", content="", status="NEG-PASS",
                        cause="", note=(err.splitlines()[0] if err.splitlines() else ""))
        return dict(row, go_exit=code, raw="", content="", status="FAIL",
                    cause="负例意外成功", note="")
    go_code, go_c, go_err = run([args.go_bin, "build", "--emit-c", f], root)
    if go_code != 0:
        return dict(row, go_exit=go_code, raw="", content="", status="FAIL",
                    cause="Go emit-c 失败", note=(go_err.splitlines()[0] if go_err.splitlines() else ""))
    b_code, b_out, b_err = run([args.go_bin, "--emit-ast-bundle", f], root)
    if b_code != 0:
        return dict(row, go_exit=0, raw="", content="", status="FAIL",
                    cause="bundle 失败", note=b_err[:120])
    try:
        bundle = json.loads(b_out)
        nf = len(bundle["files"])
    except Exception as e:
        return dict(row, go_exit=0, raw="", content="", status="FAIL",
                    cause="bundle 解析失败", note=str(e)[:120])
    kind = "单文件" if nf == 1 else "多文件"
    ast_code, ast, ast_err = run([args.xnast_bin, "--ast", f], root)
    if ast_code != 0:
        return dict(row, go_exit=0, raw="", content="", status="FAIL",
                    cause="AST 失败", note=ast_err[:120])
    proj_code, proj, _ = run(["python3", os.path.join(root, "tests/b3/xfb-projection.py"),
                              os.path.dirname(f) or "."], root)
    bundle_json = json.dumps(bundle, ensure_ascii=False)
    tmpdir = ""
    paths = []
    if args.inline_args:
        # 兼容形态（合同 1.1）：AST/projection/bundle 走位置参数。
        base = [args.go_bin, "run", "--interp", args.xnullc, "--", f, ast, proj]
        if nf > 1:
            base.append(bundle_json)
    else:
        # 文件形态（合同 1.2）：AST/bundle 写临时文件，projection 仍内联。
        tmpdir = tempfile.mkdtemp(prefix="b3-09-")
        ast_path = os.path.join(tmpdir, "ast.txt")
        note = write_limited(ast_path, ast)
        if note:
            return limit_row(row, kind, nf, f"ast-file {ast_path} {note} tmp={tmpdir}")
        paths.append(ast_path)
        base = [args.go_bin, "run", "--interp", args.xnullc, "--", f,
                "--ast-file", ast_path, "--project", proj]
        bundle_path = os.path.join(tmpdir, "bundle.json")
        note = write_limited(bundle_path, bundle_json)
        if note:
            return limit_row(row, kind, nf, f"bundle-file {bundle_path} {note} tmp={tmpdir}")
        paths.append(bundle_path)
        if nf > 1:
            base += ["--bundle-file", bundle_path]
    code, xn_c, xn_err = run(base, root)
    if code != 0:
        lines = (xn_err or "").strip().splitlines()
        first = lines[0] if lines else ""
        # 文件通道读写失败 / argv 超限统一归 K-07-LIMIT，不再产生 ARGMAX。
        limit = is_limit_error(code, xn_err, paths if not args.inline_args else [])
        note = first[:200]
        if tmpdir:
            note = (note + " " if note else "") + f"tmp={tmpdir}"
        if limit:
            return dict(row, kind=kind, files=nf, go_exit=0, raw="", content="",
                        status="K07-LIMIT", cause="K-07-LIMIT", note=note)
        return dict(row, kind=kind, files=nf, go_exit=0, raw="", content="",
                    status="FAIL", cause="xnullc 失败", note=note)
    if tmpdir:
        shutil.rmtree(tmpdir, ignore_errors=True)
    raw, rd = diff_count(go_c, xn_c)
    content, cd = diff_count(norm(go_c), norm(xn_c))
    status = "PASS0" if raw == 0 else ("NORM0" if content == 0 else "DIFF")
    return dict(row, kind=kind, files=nf, go_exit=0, raw=raw, content=content,
                status=status, cause=(cause_of(cd) if raw else ""), note="")


def write_limited(path, text):
    """写临时文件；超 16 MiB 或写入失败返回错误说明（空串表示成功）。"""
    data = text.encode("utf-8")
    if len(data) > LIMIT_BYTES:
        return f"超过 16MiB（{len(data)} 字节）"
    try:
        with open(path, "wb") as fh:
            fh.write(data)
    except OSError as e:
        return f"写入失败：{e}"
    return ""


def supports_file_args(path):
    """检查 xnullc 是否已实现 K-07 文件形态参数（源内出现 --ast-file）。"""
    try:
        with open(path, "rb") as fh:
            return b"--ast-file" in fh.read()
    except OSError:
        return False


def is_limit_error(code, stderr, paths):
    """判断失败是否属于 K-07 文件通道（读写失败/超限/argv 超限）。"""
    low = (stderr or "").lower()
    if "argument list too long" in low or code == 125 and "argument" in low:
        return True
    if any(p and p in (stderr or "") for p in paths):
        return True
    return bool(re.search(r"readfile|读取|无法打开|no such file|enoent|too large|16\s*mib", low))


def limit_row(row, kind, nf, note):
    return dict(row, kind=kind, files=nf, go_exit=0, raw="", content="",
                status="K07-LIMIT", cause="K-07-LIMIT", note=note)

def git_rev(root):
    try:
        r = subprocess.run(["git", "-C", root, "rev-parse", "--short=12", "HEAD"],
                           capture_output=True, text=True, timeout=5)
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip()
    except Exception:
        pass
    return "work"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.getcwd())
    ap.add_argument("--baseline", default="")
    ap.add_argument("--go-bin", default=None,
                    help="Go oracle 二进制；默认 /tmp/xnull-b3-all-<HEAD>")
    ap.add_argument("--xnast-bin", default=None,
                    help="xnast 二进制；默认 /tmp/xnast-b3-all-<HEAD>")
    ap.add_argument("--xnullc", default="impl/lib/b3/xnullc.x")
    ap.add_argument("--shard", default="1/1")
    ap.add_argument("--parallel", type=int, default=4)
    ap.add_argument("--inline-args", action="store_true",
                    help="兼容旧位置参数形态（合同 1.1；默认走 AST/bundle 临时文件）")
    ap.add_argument("--out", default="")
    ap.add_argument("--aggregate", action="store_true")
    args = ap.parse_args()
    root = os.path.abspath(args.root)
    rev = git_rev(root)
    if args.go_bin is None:
        args.go_bin = f"/tmp/xnull-b3-all-{rev}"
    if args.xnast_bin is None:
        args.xnast_bin = f"/tmp/xnast-b3-all-{rev}"
    out = args.out or os.path.join(root, "tests/b3/out")
    os.makedirs(out, exist_ok=True)
    if not os.path.exists(os.path.join(root, args.xnullc)):
        print(f"缺少 xnullc：{args.xnullc}", file=sys.stderr); return 2
    if not args.inline_args and not supports_file_args(os.path.join(root, args.xnullc)):
        print("xnullc 尚未实现 --ast-file/--bundle-file/--project（K-07 合同 1.2）；\n"
              "当前请加 --inline-args 走兼容形态保持绿，待 E2 合入文件通道后去掉该开关。",
              file=sys.stderr)
        return 2
    for b, name in ((args.go_bin, "xnull"), (args.xnast_bin, "xnast")):
        if not os.path.exists(b):
            print(f"缺少 Go helper：{b}（{name}）", file=sys.stderr); return 2
    if args.aggregate:
        files = sorted([f for f in os.listdir(out) if f.startswith("results.shard-") and f.endswith(".tsv")])
        if not files:
            print("没有可聚合的 shard 结果", file=sys.stderr); return 2
        ns = set()
        for f in files:
            m = re.search(r"-of-(\d+)\.tsv$", f)
            if m: ns.add(int(m.group(1)))
        if len(ns) != 1:
            print("shard 文件的 n 不一致", file=sys.stderr); return 2
        n = ns.pop()
        got = {int(re.search(r"-(\d+)-of-", f).group(1)) for f in files}
        if got != set(range(1, n + 1)):
            print(f"缺少 shard：已有 {sorted(got)} / 1..{n}", file=sys.stderr); return 2
        rows = []
        for f in files:
            with open(os.path.join(out, f), newline="") as fh:
                rows.extend(list(csv.DictReader(fh, delimiter="\t")))
        return write_summary(out, rows)
    baseline = args.baseline or os.path.join(root, "handoff/B3-09-baseline.tsv")
    rows = load_rows(baseline) or fallback_rows(root)
    k, n = (int(x) for x in args.shard.split("/"))
    if not (1 <= k <= n):
        print("--shard k/n 非法", file=sys.stderr); return 2
    sel = [r for r in rows if shard_of(r["path"], n) == k]
    with ThreadPoolExecutor(max_workers=max(1, args.parallel)) as ex:
        results = list(ex.map(lambda r: process(r, args), sel))
    cols = ["path", "group", "kind", "files", "shard", "go_exit", "raw", "content", "status", "cause", "note"]
    path = os.path.join(out, f"results.shard-{k}-of-{n}.tsv") if n > 1 or args.shard != "1/1" else os.path.join(out, "results.tsv")
    with open(path, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, delimiter="\t", extrasaction="ignore")
        w.writeheader()
        for r in results:
            r["shard"] = f"{k}/{n}"
            w.writerow(r)
    print(f"shard {k}/{n}: {len(results)} 文件 -> {path}")
    if n > 1 and args.shard != "1/1":
        return 0 if all(r["status"] in ("PASS0", "NEG-PASS") for r in results) else 1
    return write_summary(out, results)

def write_summary(out, results):
    cols = ["path", "group", "kind", "files", "shard", "go_exit", "raw", "content", "status", "cause", "note"]
    with open(os.path.join(out, "results.tsv"), "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, delimiter="\t", extrasaction="ignore")
        w.writeheader()
        for r in results: w.writerow(r)
    from collections import Counter
    st = Counter(r.get("status", "") for r in results)
    causes = Counter(r.get("cause", "") for r in results if r.get("cause"))
    zero = sum(1 for r in results if r.get("raw") in ("0", 0))
    print(f"汇总：文件 {len(results)}；raw 0 diff {zero}；status {dict(st)}")
    print("首因：" + ("; ".join(f"{k}={v}" for k, v in causes.most_common()) if causes else "无"))
    bad = [r for r in results if r.get("status") not in ("PASS0", "NEG-PASS")]
    for r in bad[:20]:
        print(f"  RED {r['status']:8} {r['path']} raw={r.get('raw','')} content={r.get('content','')} {r.get('cause','')}")
    return 0 if not bad else 1

if __name__ == "__main__":
    sys.exit(main())
