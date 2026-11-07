#!/usr/bin/env python3
"""GEN-01 独立验收（QA1）：26 项，双路径 accept + 单路径 reject。
不引用 E2 测试；用例与期望由 QA1 按 S1 §8 与台账检查表自写。
用法：run_gen01.py <xnull> <repo_root>
"""
import json, pathlib, subprocess, sys, tempfile, shutil

XN, ROOT = sys.argv[1], sys.argv[2]
HERE = pathlib.Path(__file__).resolve().parent
cases = json.loads((HERE / "cases.json").read_text())

passed = 0
fails = []


def run(cmd, cwd):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)


for c in cases:
    d = pathlib.Path(tempfile.mkdtemp(prefix="gen01."))
    (d / "main.x").write_text(c["src"])
    for rel, text in c.get("files", {}).items():
        p = d / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
    ok = False
    detail = ""
    if c["mode"] == "accept":
        want = c["expected"]
        results = []
        for mode in (["--interp"], []):
            r = run([XN, "run"] + mode + [str(d / "main.x")], ROOT)
            results.append((mode, r))
        ok = all(r.returncode == 0 and r.stdout == want for _, r in results)
        if not ok:
            mode, r = next(((m, r) for m, r in results if r.returncode or r.stdout != want), results[0])
            detail = f"{mode or ['compiled']} exit={r.returncode} out={r.stdout!r} err={(r.stderr or '').splitlines()[:2]}"
    else:
        r = run([XN, "build", str(d / "main.x"), "-o", str(d / "bin")], ROOT)
        ok = r.returncode != 0 and c["expected"] in (r.stderr or "")
        if not ok:
            detail = f"build exit={r.returncode} err={(r.stderr or '').splitlines()[:2]}"
    if ok:
        passed += 1
    else:
        fails.append((c["id"], detail))
    shutil.rmtree(d, ignore_errors=True)

print(f"GEN-QA {passed}/{len(cases)}")
for cid, detail in fails:
    print(f"FAIL {cid}: {detail}")
sys.exit(0 if passed == len(cases) else 1)
